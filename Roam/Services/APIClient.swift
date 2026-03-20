import FirebaseAuth
import Foundation

extension APIClient {
    /// Mock-network client for `#Preview` and any view read outside the authenticated shell.
    static var previewForSwiftUIPreviews: APIClient {
        let cfg = AppConfig()
        cfg.networkEnv = .mock
        return APIClient(authManager: AuthManager(isMock: true), appConfig: cfg)
    }
}

final class APIClient {
    private let authManager: AuthManager
    private let appConfig: AppConfig

    init(authManager: AuthManager, appConfig: AppConfig) {
        self.authManager = authManager
        self.appConfig = appConfig
    }

    // MARK: - Transport

    func apiFetch<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
        let data = try await apiData(path: path, method: method, body: body, contentType: contentType)
        return try JSONDecoder.roam.decode(T.self, from: data)
    }

    /// For 204 No Content (e.g. DELETE, mark-all-read).
    func apiPerform(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws {
        _ = try await apiData(path: path, method: method, body: body, contentType: contentType, allowEmptyBody: true)
    }

    private func apiData(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json",
        allowEmptyBody: Bool = false
    ) async throws -> Data {
        guard appConfig.isNetworkEnabled, let baseURL = appConfig.baseURL else {
            throw APIError.offline
        }

        let token = try await authManager.getIdToken()

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        let bearer = "Bearer \(token)"
        request.setValue(bearer, forHTTPHeaderField: "Authorization")
        // API Gateway may replace Authorization with a Cloud Run invoker JWT; backend reads Firebase from here.
        request.setValue(bearer, forHTTPHeaderField: "X-Roam-Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = body
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = try? JSONDecoder().decode(ErrorDetail.self, from: data)
            throw APIError.httpError(status: httpResponse.statusCode, message: detail?.detail ?? "Request failed")
        }

        if allowEmptyBody, data.isEmpty {
            return Data()
        }
        return data
    }

    // MARK: - User / auth sync

    func ensureBackendUser(username: String) async throws {
        guard appConfig.isNetworkEnabled else { return }

        let dn = authManager.user?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = dn.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let firstName = parts.first.map(String.init) ?? ""
        let lastName = parts.count > 1 ? String(parts[1]) : ""

        struct UserCreatePayload: Encodable {
            let username: String
            let email: String?
            let firstName: String
            let lastName: String
            let photoUrl: String?
        }

        let user = authManager.user
        let payload = UserCreatePayload(
            username: username,
            email: user?.email,
            firstName: firstName,
            lastName: lastName,
            photoUrl: user?.photoURL?.absoluteString
        )
        let body = try JSONEncoder.roam.encode(payload)
        let _: RoamUser = try await apiFetch(path: "/api/users", method: "POST", body: body)
    }

    func syncBackendUser() async throws -> Bool {
        guard appConfig.isNetworkEnabled else { return false }

        do {
            let _: RoamUser = try await apiFetch(path: "/api/me")
            return true
        } catch APIError.httpError(let status, _) where status == 404 {
            return false
        } catch APIError.httpError(let status, _) where status == 403 {
            return true
        }
    }

    func verifyBackendUser() async throws {
        guard appConfig.isNetworkEnabled else { return }
        let _: RoamUser = try await apiFetch(path: "/api/users/verify", method: "POST")
    }

    func getMe() async throws -> RoamUser {
        try await apiFetch(path: "/api/me")
    }

    // MARK: - Ideas

    func listIdeas() async throws -> [Idea] {
        try await apiFetch(path: "/api/ideas")
    }

    func getIdea(id: String) async throws -> Idea {
        try await apiFetch(path: "/api/ideas/\(id.lowercased())")
    }

    func createIdea(title: String) async throws -> Idea {
        let payload = IdeaCreatePayload(title: title, notes: "", sourceUrl: "")
        let body = try JSONEncoder.roam.encode(payload)
        return try await apiFetch(path: "/api/ideas", method: "POST", body: body)
    }

    func deleteIdea(id: String) async throws {
        try await apiPerform(path: "/api/ideas/\(id.lowercased())", method: "DELETE")
    }

    func interpretIdea(id: String) async throws -> Idea {
        try await apiFetch(path: "/api/ideas/\(id.lowercased())/interpret", method: "POST")
    }

    func promoteIdea(id: String) async throws -> Plan {
        try await apiFetch(path: "/api/ideas/\(id.lowercased())/plan", method: "POST")
    }

    // MARK: - Plans

    func listPlans() async throws -> [Plan] {
        try await apiFetch(path: "/api/plans")
    }

    func getPlan(id: String) async throws -> Plan {
        try await apiFetch(path: "/api/plans/\(id.lowercased())")
    }

    // MARK: - Notifications

    func listNotifications() async throws -> [RoamNotification] {
        try await apiFetch(path: "/api/notifications")
    }

    func markNotificationRead(id: String) async throws -> RoamNotification {
        try await apiFetch(path: "/api/notifications/\(id.lowercased())/read", method: "POST")
    }

    func markAllNotificationsRead() async throws {
        try await apiPerform(path: "/api/notifications/read-all", method: "POST")
    }

    // MARK: - Ingest (reel)

    struct IngestCreateResponse: Decodable {
        let jobId: String
        let status: String
    }

    func submitIngest(reelUrl: String, shareText: String?) async throws -> IngestCreateResponse {
        guard appConfig.isNetworkEnabled, let baseURL = appConfig.baseURL else {
            throw APIError.offline
        }
        let token = try await authManager.getIdToken()
        guard let url = URL(string: "\(baseURL)/api/ingest") else {
            throw APIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let bearer = "Bearer \(token)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(bearer, forHTTPHeaderField: "Authorization")
        request.setValue(bearer, forHTTPHeaderField: "X-Roam-Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "reelUrl", value: reelUrl)
        if let shareText, !shareText.isEmpty {
            appendField(name: "shareText", value: shareText)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let detail = try? JSONDecoder().decode(ErrorDetail.self, from: data)
            throw APIError.httpError(status: httpResponse.statusCode, message: detail?.detail ?? "Ingest failed")
        }
        return try JSONDecoder.roam.decode(IngestCreateResponse.self, from: data)
    }
}

struct ErrorDetail: Decodable {
    let detail: String
}

enum APIError: LocalizedError {
    case offline
    case invalidURL
    case invalidResponse
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .offline: return "Offline (mock mode)"
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(_, let message): return message
        }
    }
}
