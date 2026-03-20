import FirebaseAuth
import Foundation

extension APIClient {
    /// Default for `#Preview` and `EnvironmentKey` fallbacks: production API base + real `AuthManager` (calls fail until signed in).
    static var previewForSwiftUIPreviews: APIClient {
        let cfg = AppConfig()
        return APIClient(authManager: AuthManager(), appConfig: cfg)
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
        let baseURL = appConfig.baseURL
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
        /// Server saved reel row for grid / review flow.
        let reelId: String?
        /// Duplicate ingest (job already done): first idea id for backward compatibility.
        let ideaId: String?
        /// Duplicate ingest: all idea ids from that reel job.
        let ideaIds: [String]?

        /// Immediate navigation when the server already returned idea id(s) (duplicate 202).
        var firstNavigableIdeaId: String? {
            if let ideaIds, let first = ideaIds.first, !first.isEmpty { return first }
            if let ideaId, !ideaId.isEmpty { return ideaId }
            return nil
        }
    }

    struct IngestPlaceSuggestion: Decodable {
        let id: UUID
        let resultId: UUID
        let placeId: UUID?
        let rawName: String?
        let confidence: Double?
        let isSelected: Bool
        let createdAt: Date
        let placeName: String?
    }

    struct IngestPipelineResult: Decodable {
        let id: UUID
        let ideaId: UUID?
        let jobId: UUID?
        let source: String
        let refinedTitle: String?
        let category: String?
        let estimatedMinutes: Int?
        let modelName: String?
        let promptVersion: String?
        let createdAt: Date
        let placeSuggestions: [IngestPlaceSuggestion]?
    }

    struct IngestJobResponse: Decodable {
        let id: UUID
        let userId: UUID
        let reelUrl: String
        let shareText: String?
        let reelTitle: String?
        let ogDescription: String?
        let ogKeywords: String?
        let status: String
        let error: String?
        let createdAt: Date
        let updatedAt: Date
        /// First pipeline result (same as `pipelineResults?.first` when present).
        let pipelineResult: IngestPipelineResult?
        /// All ideas produced for this reel (one per model candidate above threshold).
        let pipelineResults: [IngestPipelineResult]?

        var firstIdeaId: UUID? {
            if let id = pipelineResults?.first?.ideaId { return id }
            return pipelineResult?.ideaId
        }
    }

    func getIngestJob(jobId: String) async throws -> IngestJobResponse {
        try await apiFetch(path: "/api/ingest/\(jobId.lowercased())")
    }

    func submitIngest(
        reelUrl: String,
        shareText: String?,
        reelTitle: String? = nil,
        ogDescription: String? = nil,
        ogKeywords: String? = nil,
        thumbnailJPEG: Data? = nil,
        frameJPEGs: [Data] = []
    ) async throws -> IngestCreateResponse {
        let baseURL = appConfig.baseURL
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

        func appendFile(name: String, filename: String, mimeType: String, data: Data) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                    .data(using: .utf8)!
            )
            body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }

        appendField(name: "reelUrl", value: reelUrl)
        if let shareText, !shareText.isEmpty {
            appendField(name: "shareText", value: shareText)
        }
        if let reelTitle, !reelTitle.isEmpty {
            appendField(name: "reelTitle", value: reelTitle)
        }
        if let ogDescription, !ogDescription.isEmpty {
            appendField(name: "ogDescription", value: ogDescription)
        }
        if let ogKeywords, !ogKeywords.isEmpty {
            appendField(name: "ogKeywords", value: ogKeywords)
        }
        if let thumbnailJPEG, !thumbnailJPEG.isEmpty {
            appendFile(name: "thumbnail", filename: "thumb.jpg", mimeType: "image/jpeg", data: thumbnailJPEG)
        }
        for (i, frameData) in frameJPEGs.enumerated() where !frameData.isEmpty {
            appendFile(name: "frames", filename: "frame\(i).jpg", mimeType: "image/jpeg", data: frameData)
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

    // MARK: - Reels (saved reels + promote)

    struct ReelsSummaryResponse: Decodable {
        let needsReviewCount: Int
    }

    struct SavedReelListItemDTO: Decodable, Identifiable {
        let id: UUID
        let jobId: UUID
        let reelUrl: String
        let title: String
        let status: String
        let thumbnailSignedUrl: String?
        let createdAt: Date
        let updatedAt: Date
    }

    struct ReelCandidateDetailDTO: Decodable, Identifiable {
        let id: UUID
        let savedReelId: UUID
        let sortIndex: Int
        let previewTitle: String
        let isSynthetic: Bool
        let resolvedPlaceId: UUID?
        let promotedIdeaId: UUID?
        let createdAt: Date
        let resolvedPlaceName: String?
    }

    struct SavedReelIdeaSummaryDTO: Decodable, Identifiable {
        let id: UUID
        let title: String
        let status: String
        let placeId: UUID?
        let placeName: String?
    }

    struct PlaceSearchRowDTO: Decodable, Identifiable {
        let id: UUID
        let name: String
        let address: String?
    }

    struct SavedReelDetailDTO: Decodable {
        let id: UUID
        let jobId: UUID
        let reelUrl: String
        let title: String
        let status: String
        let thumbnailSignedUrl: String?
        let jobStatus: String
        let jobError: String?
        let candidates: [ReelCandidateDetailDTO]
        /// Lightweight ideas on this reel (may be empty on older API responses).
        let ideas: [SavedReelIdeaSummaryDTO]?
        let ideaIds: [UUID]
        let createdAt: Date
        let updatedAt: Date

        var ideasNonEmpty: [SavedReelIdeaSummaryDTO] { ideas ?? [] }
    }

    struct PromoteReelResponseDTO: Decodable {
        let ideaIds: [UUID]
        let reelStatus: String
    }

    func reelsSummary() async throws -> ReelsSummaryResponse {
        try await apiFetch(path: "/api/reels/summary")
    }

    func listReels(limit: Int = 50, offset: Int = 0) async throws -> [SavedReelListItemDTO] {
        try await apiFetch(path: "/api/reels?limit=\(limit)&offset=\(offset)")
    }

    func getReel(id: String) async throws -> SavedReelDetailDTO {
        try await apiFetch(path: "/api/reels/\(id.lowercased())")
    }

    struct ReelPromoteItem: Encodable {
        let candidateId: UUID
        let title: String?
        let mapsQuery: String?
        let placeAddress: String?
        let category: String?
    }

    private struct PromoteReelBodyEnc: Encodable {
        let promotions: [ReelPromoteItem]
    }

    func promoteReel(
        reelId: String,
        promotions: [ReelPromoteItem]
    ) async throws -> PromoteReelResponseDTO {
        let body = try JSONEncoder().encode(PromoteReelBodyEnc(promotions: promotions))
        return try await apiFetch(
            path: "/api/reels/\(reelId.lowercased())/promote",
            method: "POST",
            body: body
        )
    }

    func searchPlacesList(query: String, limit: Int = 8) async throws -> [PlaceSearchRowDTO] {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")
        let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return try await apiFetch(path: "/api/places/search-list?q=\(q)&limit=\(limit)")
    }

    private struct CreateIdeaOnReelBodyEnc: Encodable {
        let title: String
        let notes: String
        let placeId: UUID?
    }

    func createIdeaOnReel(reelId: String, title: String, notes: String, placeId: UUID?) async throws -> Idea {
        let body = try JSONEncoder.roam.encode(
            CreateIdeaOnReelBodyEnc(title: title, notes: notes, placeId: placeId)
        )
        return try await apiFetch(
            path: "/api/reels/\(reelId.lowercased())/ideas",
            method: "POST",
            body: body
        )
    }
}

struct ErrorDetail: Decodable {
    let detail: String
}

enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .invalidResponse: return "Invalid response"
        case .httpError(_, let message): return message
        }
    }
}
