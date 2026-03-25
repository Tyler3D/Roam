import Foundation
import Observation

@MainActor
@Observable
final class IdeasQueryStore {
    private let api: APIClient
    private let staleDuration: TimeInterval = 30
    private let pageLimit = 30

    private(set) var ideas: [Idea] = []
    private(set) var nextCursor: String?
    private(set) var hasMore: Bool = false
    /// From `include_total` on first-page refresh; used by Profile.
    private(set) var totalIdeasCount: Int?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var lastError: String?
    private var lastFetchedAt: Date?

    init(api: APIClient) {
        self.api = api
    }

    func loadIfStale() async {
        if let last = lastFetchedAt,
           Date().timeIntervalSince(last) < staleDuration,
           !ideas.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let page = try await api.listIdeasPage(cursor: nil, limit: pageLimit, includeTotal: true)
            ideas = page.items ?? []
            nextCursor = page.nextCursor
            hasMore = page.hasMore ?? false
            if let t = page.totalCount {
                totalIdeasCount = t
            }
            lastFetchedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, let cur = nextCursor, !cur.isEmpty else { return }
        guard !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await api.listIdeasPage(cursor: cur, limit: pageLimit, includeTotal: false)
            let newItems = page.items ?? []
            var seen = Set(ideas.map(\.id))
            for idea in newItems where !seen.contains(idea.id) {
                ideas.append(idea)
                seen.insert(idea.id)
            }
            nextCursor = page.nextCursor
            hasMore = page.hasMore ?? false
            lastFetchedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createIdea(title: String) async throws -> Idea {
        let idea = try await api.createIdea(title: title)
        ideas.insert(idea, at: 0)
        if let t = totalIdeasCount {
            totalIdeasCount = t + 1
        }
        lastFetchedAt = Date()
        return idea
    }

    func deleteIdea(id: String) async throws {
        try await api.deleteIdea(id: id)
        ideas.removeAll { $0.id == id }
        if let t = totalIdeasCount {
            totalIdeasCount = max(0, t - 1)
        }
    }

    func interpretIdea(id: String) async throws {
        let updated = try await api.interpretIdea(id: id)
        if let idx = ideas.firstIndex(where: { $0.id == id }) {
            ideas[idx] = updated
        } else {
            ideas.insert(updated, at: 0)
        }
    }

    func promoteIdea(id: String) async throws -> Plan {
        let plan = try await api.promoteIdea(id: id)
        let updated = try await api.getIdea(id: id)
        if let idx = ideas.firstIndex(where: { $0.id == id }) {
            ideas[idx] = updated
        } else {
            ideas.insert(updated, at: 0)
        }
        return plan
    }

    func replaceLocal(_ idea: Idea) {
        if let idx = ideas.firstIndex(where: { $0.id == idea.id }) {
            ideas[idx] = idea
        } else {
            ideas.insert(idea, at: 0)
        }
    }
}
