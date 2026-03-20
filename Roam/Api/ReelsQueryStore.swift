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
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            async let list = api.listReels()
            async let summary = api.reelsSummary()
            reels = try await list
            needsReviewCount = try await summary.needsReviewCount
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshSummaryOnly() async {
        do {
            needsReviewCount = try await api.reelsSummary().needsReviewCount
        } catch {
            lastError = error.localizedDescription
        }
    }
}
