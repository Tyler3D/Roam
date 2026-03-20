import Foundation

enum QueuedUploadStatus: String, Codable {
    case pendingUpload
    case uploading
    case failed
}

/// A reel captured from the share extension (or inbox), cached in the app group until uploaded.
struct QueuedReelIngest: Codable, Identifiable, Equatable {
    var id: UUID
    var reelUrl: String
    var shareText: String?
    var attachmentTypeIdentifiers: [String]
    var createdAt: Date

    var reelTitle: String?
    var ogDescription: String?
    var ogKeywords: String?

    /// Filenames inside the item folder, e.g. `thumb.jpg`, `frame0.jpg`
    var thumbnailFilename: String?
    var frameFilenames: [String]

    var uploadStatus: QueuedUploadStatus
    var lastUploadError: String?

    var displayTitle: String {
        let t = (reelTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return reelUrl
    }
}
