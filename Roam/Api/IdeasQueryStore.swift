import Foundation
import Observation

@MainActor
@Observable
final class IdeasQueryStore {
    private let api: APIClient
    private let staleDuration: TimeInterval = 30

    private(set) var ideas: [Idea] = []
    private(set) var isLoading = false
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
            ideas = try await api.listIdeas()
            lastFetchedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    @discardableResult
    func createIdea(title: String) async throws -> Idea {
        let idea = try await api.createIdea(title: title)
        ideas.insert(idea, at: 0)
        lastFetchedAt = Date()
        return idea
    }

    func deleteIdea(id: String) async throws {
        try await api.deleteIdea(id: id)
        ideas.removeAll { $0.id == id }
    }

    func interpretIdea(id: String) async throws {
        let updated = try await api.interpretIdea(id: id)
        if let idx = ideas.firstIndex(where: { $0.id == id }) {
            ideas[idx] = updated
        }
    }

    func promoteIdea(id: String) async throws -> Plan {
        let plan = try await api.promoteIdea(id: id)
        let updated = try await api.getIdea(id: id)
        if let idx = ideas.firstIndex(where: { $0.id == id }) {
            ideas[idx] = updated
        }
        return plan
    }

    func replaceLocal(_ idea: Idea) {
        if let idx = ideas.firstIndex(where: { $0.id == idea.id }) {
            ideas[idx] = idea
        }
    }
}
