import Foundation

/// Slim reels list for the share extension mini-grid (app group). Written by the main app; no signed URLs.
struct ReelsGridPreviewTile: Codable, Equatable, Identifiable {
    let id: String
    let title: String
}

enum ReelsGridPreviewSnapshot {
    private static let appGroupID = SharedStore.appGroupID
    private static let fileName = "reels-grid-preview.json"
    private static let thumbsFolderName = "reel-preview-thumbs"
    static let maxTileCount = 12

    private static var roamSupportDir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let dir = base.appendingPathComponent("Library/Application Support/Roam", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var fileURL: URL? {
        roamSupportDir?.appendingPathComponent(fileName, isDirectory: false)
    }

    private static var previewThumbsDirectoryURL: URL? {
        guard let root = roamSupportDir else { return nil }
        let dir = root.appendingPathComponent(thumbsFolderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// JPEG written by the main app from `ReelThumbnailDiskCache` for share-extension grid tiles.
    static func previewThumbnailFileURL(reelIdLowercased: String) -> URL? {
        previewThumbsDirectoryURL?.appendingPathComponent("\(reelIdLowercased).jpg", isDirectory: false)
    }

    static func writePreviewThumbnail(reelIdLowercased: String, jpegData: Data) {
        guard !jpegData.isEmpty, let url = previewThumbnailFileURL(reelIdLowercased: reelIdLowercased) else { return }
        try? jpegData.write(to: url, options: .atomic)
    }

    static func removeAllPreviewThumbnails() {
        guard let dir = previewThumbsDirectoryURL else { return }
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return }
        for name in names where name.hasSuffix(".jpg") {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name, isDirectory: false))
        }
    }

    private struct Envelope: Codable {
        var savedAt: Date
        var tiles: [ReelsGridPreviewTile]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Persists up to `maxTileCount` titles for the extension grid. Call `removeAllPreviewThumbnails` before writing JPEGs from the main app.
    static func save(tiles: [ReelsGridPreviewTile]) {
        guard let url = fileURL else { return }
        let capped = Array(tiles.prefix(Self.maxTileCount))
        let envelope = Envelope(savedAt: Date(), tiles: capped)
        guard let data = try? encoder.encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadTiles() -> [ReelsGridPreviewTile] {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let envelope = try? decoder.decode(Envelope.self, from: data) else {
            return []
        }
        return envelope.tiles
    }

    static func clear() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        removeAllPreviewThumbnails()
    }
}
