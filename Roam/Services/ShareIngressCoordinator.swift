import Combine
import Foundation
import SwiftUI

/// Tracks an ingest job so Reels can show a scanning banner until the job finishes.
struct IngestScanState: Equatable {
    let jobId: String
    let reelId: String?
}

/// After Instagram → Roam share: extension saves a `SharedItem`, sets a handoff flag, opens `roam://share`.
/// Main app uploads ingest, refreshes lists, switches to **Reels** with a scanning banner until the job settles.
@MainActor
final class ShareIngressCoordinator: ObservableObject {
    @Published var pendingSwitchToReels = false
    /// Non-nil while polling `GET /api/ingest/{jobId}` for terminal status.
    @Published var ingestScanState: IngestScanState?
    @Published var lastError: String?
    /// Bumps when the on-device share queue changes (extension save or upload flush).
    @Published private(set) var shareQueueEpoch = 0

    private var isRunning = false
    private var isFlushingQueue = false

    func clearPendingSwitchToReels() {
        pendingSwitchToReels = false
    }

    func dismissError() {
        lastError = nil
    }

    /// When the host app opens `roam://share`, switch to Reels immediately (before ingest / metadata work).
    func prioritizeReelsTabForShareHandoff() {
        pendingSwitchToReels = true
    }

    /// Uploads items saved by the share extension from the app group (no need to have opened the app from the sheet).
    func flushShareQueue(apiClient: APIClient, stores: RoamStores) async {
        guard !isFlushingQueue else { return }
        guard apiClient.isUserSignedIn else { return }
        let pending = ShareQueueStore.itemsPendingUpload()
        guard !pending.isEmpty else { return }
        isFlushingQueue = true
        defer { isFlushingQueue = false }

        for item in pending {
            ShareQueueStore.markUploading(id: item.id)
            shareQueueEpoch += 1
            do {
                let thumb = ShareQueueStore.loadThumbnailData(for: item)
                let frames = ShareQueueStore.loadFrameData(for: item)
                let resp = try await apiClient.submitIngest(
                    reelUrl: item.reelUrl,
                    shareText: item.shareText,
                    reelTitle: item.reelTitle,
                    ogDescription: item.ogDescription,
                    ogKeywords: item.ogKeywords,
                    thumbnailJPEG: thumb,
                    frameJPEGs: frames
                )
                ReelThumbnailDiskCache.saveAfterIngest(reelIdString: resp.reelId, jpegData: thumb)
                ShareQueueStore.remove(id: item.id)
                await stores.ideas.refresh()
                await stores.reels.refresh()
            } catch {
                if let apiErr = error as? APIError, case .httpError(let status, _) = apiErr, status == 401 {
                    ShareQueueStore.resetToPending(id: item.id)
                } else {
                    ShareQueueStore.markFailed(id: item.id, message: error.localizedDescription)
                }
            }
            shareQueueEpoch += 1
        }
    }

    func runIfNeeded(apiClient: APIClient, stores: RoamStores) async {
        guard !isRunning else { return }
        guard SharedStore.consumePendingShareHandoff() else { return }
        guard let item = SharedStore.loadAll().first else { return }
        guard let urlString = reelURLString(from: item), let url = URL(string: urlString) else {
            lastError = "No URL in shared item"
            return
        }

        // Jump to Reels before slow OG/thumbnail extraction and network ingest so the user isn't stuck on another tab under the system dimming.
        pendingSwitchToReels = true

        isRunning = true
        lastError = nil
        defer { isRunning = false }

        do {
            let pack = await ReelMetadataService.extract(url: url, shareText: item.text)
            let resp = try await apiClient.submitIngest(
                reelUrl: urlString,
                shareText: item.text,
                reelTitle: pack.ingestReelTitle,
                ogDescription: pack.ingestOgDescription,
                ogKeywords: pack.ingestOgKeywords,
                thumbnailJPEG: pack.thumbnailJPEG,
                frameJPEGs: pack.frameJPEGs
            )
            ReelThumbnailDiskCache.saveAfterIngest(reelIdString: resp.reelId, jpegData: pack.thumbnailJPEG)
            SharedStore.remove(id: item.id)
            await stores.ideas.refresh()
            await stores.reels.refresh()

            let jobId = resp.jobId.lowercased()
            let reelNorm: String? = {
                guard let s = resp.reelId?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
                return s.lowercased()
            }()

            ingestScanState = IngestScanState(jobId: jobId, reelId: reelNorm)

            Task { [weak self] in
                await self?.pollUntilSettled(apiClient: apiClient, jobId: jobId, stores: stores)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func reelURLString(from item: SharedItem) -> String? {
        if let u = item.url, !u.isEmpty { return u }
        if let t = item.text, let url = URL(string: t), url.scheme == "http" || url.scheme == "https" {
            return t
        }
        return nil
    }

    private func pollUntilSettled(apiClient: APIClient, jobId: String, stores: RoamStores) async {
        let maxAttempts = 120
        for attempt in 0..<maxAttempts {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            do {
                let job = try await apiClient.getIngestJob(jobId: jobId)
                switch job.status {
                case "done":
                    await stores.ideas.refresh()
                    await stores.reels.refresh()
                    ingestScanState = nil
                    return
                case "failed":
                    await stores.ideas.refresh()
                    await stores.reels.refresh()
                    let trimmed = job.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let msg = trimmed.isEmpty ? "Ingest failed" : trimmed
                    ingestScanState = nil
                    lastError = msg
                    return
                default:
                    break
                }
            } catch {
                // Transient errors: keep polling until timeout.
            }
        }

        await stores.ideas.refresh()
        await stores.reels.refresh()
        ingestScanState = nil
        lastError = "Ingest timed out"
    }
}
