import Combine
import Foundation
import SwiftUI

/// After Instagram → Roam share: extension saves a `SharedItem`, sets a handoff flag, opens `roam://share`.
/// Main app uploads ingest, refreshes lists; opens **Ideas** when the job auto-created one idea, else switches to **Reels** for review.
@MainActor
final class ShareIngressCoordinator: ObservableObject {
    @Published var pendingIdeaNavigationId: String?
    @Published var pendingSwitchToReels = false
    @Published var lastError: String?

    private var isRunning = false

    func clearPendingNavigation() {
        pendingIdeaNavigationId = nil
    }

    func clearPendingSwitchToReels() {
        pendingSwitchToReels = false
    }

    func dismissError() {
        lastError = nil
    }

    func runIfNeeded(apiClient: APIClient, stores: RoamStores) async {
        guard !isRunning else { return }
        guard SharedStore.consumePendingShareHandoff() else { return }
        guard let item = SharedStore.loadAll().first else { return }
        guard let urlString = reelURLString(from: item), let url = URL(string: urlString) else {
            lastError = "No URL in shared item"
            return
        }

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

            if let immediate = resp.firstNavigableIdeaId, !immediate.isEmpty {
                pendingIdeaNavigationId = immediate.lowercased()
            } else if let ideaId = try await pollFirstIdeaOrNil(apiClient: apiClient, jobId: resp.jobId) {
                pendingIdeaNavigationId = ideaId.lowercased()
            } else {
                pendingSwitchToReels = true
            }

            Task {
                try? await Self.refreshWhenJobSettles(apiClient: apiClient, jobId: resp.jobId, stores: stores)
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

    /// After job completes: idea id if auto-promoted, `nil` if user should review in Reels.
    private func pollFirstIdeaOrNil(apiClient: APIClient, jobId: String) async throws -> String? {
        let maxAttempts = 120
        for _ in 0..<maxAttempts {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let job = try await apiClient.getIngestJob(jobId: jobId)
            switch job.status {
            case "done":
                return job.firstIdeaId?.uuidString
            case "failed":
                let trimmed = job.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let msg = trimmed.isEmpty ? "Ingest failed" : trimmed
                throw APIError.httpError(status: 500, message: msg)
            default:
                break
            }
        }
        throw APIError.httpError(status: 408, message: "Ingest timed out")
    }

    private static func refreshWhenJobSettles(apiClient: APIClient, jobId: String, stores: RoamStores) async throws {
        for _ in 0..<120 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let job = try await apiClient.getIngestJob(jobId: jobId)
            if job.status == "done" || job.status == "failed" {
                await stores.ideas.refresh()
                await stores.reels.refresh()
                return
            }
        }
    }
}
