import Foundation
import Observation

@MainActor
@Observable
final class UserQueryStore {
    private let api: APIClient

    private(set) var me: RoamUser?
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
            me = try await api.getMe()
        } catch {
            lastError = error.localizedDescription
        }
    }
}
