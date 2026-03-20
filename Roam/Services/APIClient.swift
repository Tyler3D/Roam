import FirebaseAuth
import Foundation

final class APIClient {
    private let authManager: AuthManager
    private let appConfig: AppConfig

    init(authManager: AuthManager, appConfig: AppConfig) {
        self.authManager = authManager
        self.appConfig = appConfig
    }

    // MARK: - Generic fetch with Bearer auth

    func apiFetch<T: Decodable>(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> T {
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

        return try JSONDecoder.roam.decode(T.self, from: data)
    }

    // MARK: - Backend User Sync (mirrors web AuthContext)

    func ensureBackendUser(username: String) async throws {
        guard appConfig.isNetworkEnabled else { return }

        struct CreatePayload: Encodable {
            let username: String
            let email: String?
            let displayName: String?
            let photoUrl: String?
        }

        let user = authManager.user
        let payload = CreatePayload(
            username: username,
            email: user?.email,
            displayName: user?.displayName,
            photoUrl: user?.photoURL?.absoluteString
        )
        let body = try JSONEncoder().encode(payload)
        let _: BackendUser = try await apiFetch(path: "/api/users", method: "POST", body: body)
    }

    func syncBackendUser() async throws -> Bool {
        guard appConfig.isNetworkEnabled else { return false }

        do {
            let _: BackendUser = try await apiFetch(path: "/api/me")
            return true
        } catch APIError.httpError(let status, _) where status == 404 {
            return false
        } catch APIError.httpError(let status, _) where status == 403 {
            return true
        }
    }

    func verifyBackendUser() async throws {
        guard appConfig.isNetworkEnabled else { return }
        let _: BackendUser = try await apiFetch(path: "/api/users/verify", method: "POST")
    }
}

// MARK: - Models

struct BackendUser: Decodable {
    let id: String
    let firebaseUid: String
    let username: String
    let email: String
    let displayName: String?
    let photoUrl: String?
    let isActive: Bool
    let emailVerified: Bool
    let createdAt: String
}

struct ErrorDetail: Decodable {
    let detail: String
}

// MARK: - Errors

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

// MARK: - JSONDecoder

extension JSONDecoder {
    static let roam: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}
