import Foundation
import Observation

@MainActor
@Observable
final class ReelsQueryStore {
    private let api: APIClient

    private(set) var reels: [APIClient.SavedReelListItemDTO] = []
    private(set) var needsReviewCount: Int = 0
    private(set) var isLoading = false
    private(set) var lastError: String?

    init(api: APIClient) {
        self.api = api
        restoreFromDiskIfPossible()
    }

    /// Show last successful fetch immediately (cold launch / offline).
    private func restoreFromDiskIfPossible() {
        guard let uid = api.signedInUserIdForCache,
              let envelope = SavedReelsListDiskCache.load(userId: uid) else { return }
        reels = envelope.reels
        needsReviewCount = envelope.needsReviewCount
    }

    /// After uploads / promotes / ingest, network refresh replaces memory and disk. TTL drops very old snapshots on read.
    func refresh() async {
        if reels.isEmpty {
            restoreFromDiskIfPossible()
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            async let list = api.listReels()
            async let summary = api.reelsSummary()
            reels = try await list
            needsReviewCount = try await summary.needsReviewCount
            persistToDisk()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshSummaryOnly() async {
        do {
            needsReviewCount = try await api.reelsSummary().needsReviewCount
            mergeSummaryIntoDiskCache()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistToDisk() {
        guard let uid = api.signedInUserIdForCache else { return }
        let envelope = APIClient.SavedReelsListCacheEnvelope(
            fetchedAt: Date(),
            needsReviewCount: needsReviewCount,
            reels: reels
        )
        SavedReelsListDiskCache.save(userId: uid, envelope: envelope)
        let previewTiles = reels.prefix(ReelsGridPreviewSnapshot.maxTileCount).map { r in
            ReelsGridPreviewTile(id: r.id.uuidString.lowercased(), title: Self.previewLine(for: r))
        }
        ReelsGridPreviewSnapshot.removeAllPreviewThumbnails()
        ReelsGridPreviewSnapshot.save(tiles: Array(previewTiles))
        Self.copyDiskThumbnailsToAppGroup(for: Array(reels.prefix(ReelsGridPreviewSnapshot.maxTileCount)))
    }

    private static func previewLine(for r: APIClient.SavedReelListItemDTO) -> String {
        let t = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return String(t.prefix(240)) }
        return String(r.reelUrl.prefix(240))
    }

    private func mergeSummaryIntoDiskCache() {
        guard let uid = api.signedInUserIdForCache,
              let existing = SavedReelsListDiskCache.load(userId: uid) else { return }
        let merged = APIClient.SavedReelsListCacheEnvelope(
            fetchedAt: existing.fetchedAt,
            needsReviewCount: needsReviewCount,
            reels: existing.reels
        )
        SavedReelsListDiskCache.save(userId: uid, envelope: merged)
        let previewTiles = existing.reels.prefix(ReelsGridPreviewSnapshot.maxTileCount).map { r in
            ReelsGridPreviewTile(id: r.id.uuidString.lowercased(), title: Self.previewLine(for: r))
        }
        ReelsGridPreviewSnapshot.removeAllPreviewThumbnails()
        ReelsGridPreviewSnapshot.save(tiles: Array(previewTiles))
        Self.copyDiskThumbnailsToAppGroup(for: Array(existing.reels.prefix(ReelsGridPreviewSnapshot.maxTileCount)))
    }

    private static func copyDiskThumbnailsToAppGroup(for reels: [APIClient.SavedReelListItemDTO]) {
        for r in reels {
            guard let data = ReelThumbnailDiskCache.load(reelId: r.id), !data.isEmpty else { continue }
            ReelsGridPreviewSnapshot.writePreviewThumbnail(
                reelIdLowercased: r.id.uuidString.lowercased(),
                jpegData: data
            )
        }
    }
}
