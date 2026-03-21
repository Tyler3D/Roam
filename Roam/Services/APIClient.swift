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

    /// Used to skip network work (e.g. share-queue upload) when there is no Firebase session.
    var isUserSignedIn: Bool { authManager.isSignedIn }

    /// Partitions on-disk caches (e.g. saved reels list) per account.
    var signedInUserIdForCache: String? { authManager.user?.uid }

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

    private struct IdeaSharedCollectionsAttachPayload: Encodable {
        let sharedCollectionIds: [UUID]
    }

    /// Idempotent: adds `collection_ideas` rows for shared collections the user belongs to.
    func attachIdeaSharedCollections(ideaId: UUID, sharedCollectionIds: [UUID]) async throws {
        guard !sharedCollectionIds.isEmpty else { return }
        let body = try JSONEncoder.roam.encode(IdeaSharedCollectionsAttachPayload(sharedCollectionIds: sharedCollectionIds))
        try await apiPerform(
            path: "/api/ideas/\(ideaId.uuidString.lowercased())/shared-collections",
            method: "POST",
            body: body
        )
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

    /// Re-run ingest for a saved reel whose server job is `failed` (same multipart shape as `submitIngest`, without `reelUrl`).
    func retryFailedReelIngest(
        reelId: String,
        shareText: String?,
        reelTitle: String? = nil,
        ogDescription: String? = nil,
        ogKeywords: String? = nil,
        thumbnailJPEG: Data? = nil,
        frameJPEGs: [Data] = []
    ) async throws -> IngestCreateResponse {
        let baseURL = appConfig.baseURL
        let token = try await authManager.getIdToken()
        let rid = reelId.lowercased()
        guard let url = URL(string: "\(baseURL)/api/reels/\(rid)/retry-ingest") else {
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
            throw APIError.httpError(status: httpResponse.statusCode, message: detail?.detail ?? "Retry failed")
        }
        return try JSONDecoder.roam.decode(IngestCreateResponse.self, from: data)
    }

    // MARK: - Reels (saved reels + promote)

    struct ReelsSummaryResponse: Decodable {
        let needsReviewCount: Int
    }

    struct SavedReelListItemDTO: Codable, Identifiable {
        let id: UUID
        let jobId: UUID
        let reelUrl: String
        let title: String
        let status: String
        let thumbnailSignedUrl: String?
        let createdAt: Date
        let updatedAt: Date
    }

    /// On-disk snapshot for `ReelsQueryStore` (Application Support, per Firebase uid).
    struct SavedReelsListCacheEnvelope: Codable {
        let fetchedAt: Date
        let needsReviewCount: Int
        let reels: [SavedReelListItemDTO]
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
        let previewDescription: String?
        let category: String?
        let placeAddress: String?
        let mapsQuery: String?
        let confidence: Double?

        var cardDescription: String { (previewDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var cardCategory: String {
            let c = (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return c.isEmpty ? "other" : c
        }
        var cardAddressLine: String? {
            let a = (placeAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty { return a }
            let r = (resolvedPlaceName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !r.isEmpty { return r }
            let m = (mapsQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return m.isEmpty ? nil : m
        }
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
        /// Server may omit on older deployments; treat as 0.
        let ingestRetryCount: Int?
        let jobStatus: String
        let jobError: String?
        let candidates: [ReelCandidateDetailDTO]
        /// Lightweight ideas on this reel (may be empty on older API responses).
        let ideas: [SavedReelIdeaSummaryDTO]?
        let ideaIds: [UUID]
        let createdAt: Date
        let updatedAt: Date

        var ideasNonEmpty: [SavedReelIdeaSummaryDTO] { ideas ?? [] }

        var ingestRetriesUsed: Int { ingestRetryCount ?? 0 }
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

    func deleteReel(id: String) async throws {
        try await apiPerform(path: "/api/reels/\(id.lowercased())", method: "DELETE")
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
        let collectionIds: [UUID]
    }

    func promoteReel(
        reelId: String,
        promotions: [ReelPromoteItem],
        sharedCollectionIds: [UUID] = []
    ) async throws -> PromoteReelResponseDTO {
        let body = try JSONEncoder.roam.encode(
            PromoteReelBodyEnc(promotions: promotions, collectionIds: sharedCollectionIds)
        )
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
        let collectionIds: [UUID]
    }

    func createIdeaOnReel(
        reelId: String,
        title: String,
        notes: String,
        placeId: UUID?,
        sharedCollectionIds: [UUID] = []
    ) async throws -> Idea {
        let body = try JSONEncoder.roam.encode(
            CreateIdeaOnReelBodyEnc(
                title: title,
                notes: notes,
                placeId: placeId,
                collectionIds: sharedCollectionIds
            )
        )
        return try await apiFetch(
            path: "/api/reels/\(reelId.lowercased())/ideas",
            method: "POST",
            body: body
        )
    }

    // MARK: - Collections + map pins

    struct CollectionMemberPreviewDTO: Decodable {
        let userId: UUID
        let firstName: String?
        let lastName: String?
        let photoUrl: String?
    }

    struct CollectionReadDTO: Decodable, Identifiable {
        let id: UUID
        let creatorId: UUID
        let name: String
        let description: String?
        let isPersonalDefault: Bool
        let createdAt: Date
        let memberPreview: [CollectionMemberPreviewDTO]?
    }

    struct CollectionMapPinDTO: Decodable, Identifiable {
        let id: UUID
        let title: String
        let notes: String
        let displayName: String?
        let placeId: UUID?
        let placeName: String?
        let placeAddress: String?
        let placeLatitude: Double?
        let placeLongitude: Double?
        let category: String?
        let createdAt: Date
        let addedByUserId: UUID
        let addedByFirstName: String?
        let addedByLastName: String?
        let addedByColorIndex: Int?

        var pinTitle: String {
            let d = (displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return d.isEmpty ? title : d
        }

        var addedByDisplayName: String {
            let f = (addedByFirstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let l = (addedByLastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let combined = [f, l].filter { !$0.isEmpty }.joined(separator: " ")
            return combined.isEmpty ? "Someone" : combined
        }

        var colorIndex: Int { addedByColorIndex ?? 0 }
    }

    /// Matches backend `FriendshipRead` (accepted rows and pending request rows).
    struct FriendshipReadDTO: Decodable, Identifiable {
        let id: UUID
        let requesterId: UUID?
        let addresseeId: UUID?
        let status: String?
        let createdAt: Date?
        let friendId: UUID?
        let friendFirstName: String?
        let friendLastName: String?
        let friendPhotoUrl: String?
    }

    /// Legacy alias — same JSON shape as `FriendshipReadDTO`.
    typealias FriendshipRowDTO = FriendshipReadDTO

    struct FriendSearchResultDTO: Decodable {
        let friends: [RoamUser]
        let others: [RoamUser]
    }

    func listFriends() async throws -> [FriendshipReadDTO] {
        try await apiFetch(path: "/api/friends")
    }

    func listFriendRequests() async throws -> [FriendshipReadDTO] {
        try await apiFetch(path: "/api/friends/requests")
    }

    func listSentFriendRequests() async throws -> [FriendshipReadDTO] {
        try await apiFetch(path: "/api/friends/sent")
    }

    func searchFriends(query: String) async throws -> FriendSearchResultDTO {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        let enc = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return try await apiFetch(path: "/api/friends/search?q=\(enc)")
    }

    private struct FriendRequestBody: Encodable {
        let targetUserId: UUID
    }

    func sendFriendRequest(targetUserId: UUID) async throws -> FriendshipReadDTO {
        let body = try JSONEncoder.roam.encode(FriendRequestBody(targetUserId: targetUserId))
        return try await apiFetch(path: "/api/friends/request", method: "POST", body: body)
    }

    func acceptFriendRequest(friendshipId: UUID) async throws -> FriendshipReadDTO {
        try await apiFetch(
            path: "/api/friends/\(friendshipId.uuidString.lowercased())/accept",
            method: "POST"
        )
    }

    func removeFriendship(friendshipId: UUID) async throws {
        try await apiPerform(
            path: "/api/friends/\(friendshipId.uuidString.lowercased())",
            method: "DELETE"
        )
    }

    func listCollections() async throws -> [CollectionReadDTO] {
        try await apiFetch(path: "/api/collections")
    }

    func listEverythingMapPins() async throws -> [CollectionMapPinDTO] {
        try await apiFetch(path: "/api/collections/everything/ideas")
    }

    func listCollectionMapPins(collectionId: UUID) async throws -> [CollectionMapPinDTO] {
        try await apiFetch(path: "/api/collections/\(collectionId.uuidString.lowercased())/ideas")
    }

    private struct CollectionCreatePayload: Encodable {
        let name: String
        let description: String?
        let memberUserIds: [UUID]
    }

    func createSharedCollection(
        name: String,
        description: String? = nil,
        memberUserIds: [UUID]
    ) async throws -> CollectionReadDTO {
        let body = try JSONEncoder.roam.encode(
            CollectionCreatePayload(
                name: name,
                description: description,
                memberUserIds: memberUserIds
            )
        )
        return try await apiFetch(path: "/api/collections", method: "POST", body: body)
    }

    private struct CollectionMemberAddPayload: Encodable {
        let userId: UUID
    }

    func addCollectionMember(collectionId: UUID, userId: UUID) async throws {
        let body = try JSONEncoder.roam.encode(CollectionMemberAddPayload(userId: userId))
        try await apiPerform(
            path: "/api/collections/\(collectionId.uuidString.lowercased())/members",
            method: "POST",
            body: body
        )
    }

    func removeCollectionMember(collectionId: UUID, memberUserId: UUID) async throws {
        try await apiPerform(
            path: "/api/collections/\(collectionId.uuidString.lowercased())/members/\(memberUserId.uuidString.lowercased())",
            method: "DELETE"
        )
    }

    func deleteCollection(collectionId: UUID) async throws {
        try await apiPerform(
            path: "/api/collections/\(collectionId.uuidString.lowercased())",
            method: "DELETE"
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
