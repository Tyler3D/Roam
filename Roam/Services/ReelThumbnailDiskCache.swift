import Foundation

/// On-disk JPEG thumbnails keyed by saved-reel id (instant grid after ingest).
enum ReelThumbnailDiskCache {
    private static let subfolder = "reel-thumbnails"

    private static func directoryURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Roam", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(reelId: UUID) throws -> URL {
        try directoryURL().appendingPathComponent("\(reelId.uuidString.lowercased()).jpg", isDirectory: false)
    }

    static func save(reelId: UUID, jpegData: Data) throws {
        guard !jpegData.isEmpty else { return }
        let url = try fileURL(reelId: reelId)
        try jpegData.write(to: url, options: .atomic)
    }

    /// Best-effort save after ingest when server returns `reelId`.
    static func saveAfterIngest(reelIdString: String?, jpegData: Data?) {
        guard let reelIdString, let jpegData, !jpegData.isEmpty,
              let id = UUID(uuidString: reelIdString) else { return }
        try? save(reelId: id, jpegData: jpegData)
    }

    static func load(reelId: UUID) -> Data? {
        guard let url = try? fileURL(reelId: reelId),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func remove(reelId: UUID) {
        guard let url = try? fileURL(reelId: reelId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func clearAll() {
        guard let dir = try? directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
