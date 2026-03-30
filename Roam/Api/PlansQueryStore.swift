import Foundation
import Observation

@MainActor
@Observable
final class PlansQueryStore {
    private let api: APIClient
    private let staleDuration: TimeInterval = 30

    private(set) var plans: [Plan] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var lastFetchedAt: Date?

    init(api: APIClient) {
        self.api = api
    }

    var drafts: [Plan] {
        plans.filter { $0.status == .draft }
    }

    func loadIfStale() async {
        if let last = lastFetchedAt,
           Date().timeIntervalSince(last) < staleDuration,
           !plans.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            plans = try await api.listPlans()
            lastFetchedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func upcomingConfirmed(reference: Date = Date()) -> [Plan] {
        plans
            .filter { $0.status == .confirmed && ($0.scheduledAt.map { $0 >= reference } ?? false) }
            .sorted {
                guard let a = $0.scheduledAt, let b = $1.scheduledAt else { return false }
                return a < b
            }
    }

    func pastConfirmed(reference: Date = Date()) -> [Plan] {
        plans
            .filter {
                ($0.status == .confirmed || $0.status == .completed)
                    && ($0.scheduledAt.map { $0 < reference } ?? false)
            }
            .sorted {
                guard let a = $0.scheduledAt, let b = $1.scheduledAt else { return false }
                return a > b
            }
    }

    func upsert(_ plan: Plan) {
        if let idx = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[idx] = plan
        } else {
            plans.append(plan)
        }
    }
}
