import Foundation
import Observation

@MainActor
@Observable
final class NotificationsQueryStore {
    private let api: APIClient
    private let staleDuration: TimeInterval = 30

    private(set) var notifications: [RoamNotification] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private var lastFetchedAt: Date?

    init(api: APIClient) {
        self.api = api
    }

    var unreadCount: Int {
        notifications.filter { !$0.isRead }.count
    }

    func loadIfStale() async {
        if let last = lastFetchedAt,
           Date().timeIntervalSince(last) < staleDuration,
           !notifications.isEmpty { return }
        await refresh()
    }

    func refresh() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            notifications = try await api.listNotifications()
            lastFetchedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func markRead(id: String) async throws {
        let updated = try await api.markNotificationRead(id: id)
        if let idx = notifications.firstIndex(where: { $0.id == id }) {
            notifications[idx] = updated
        }
    }

    func markAllRead() async throws {
        try await api.markAllNotificationsRead()
        await refresh()
    }
}
