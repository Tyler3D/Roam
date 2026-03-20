import Foundation

/// Persists `GET /api/reels` (+ summary count) for instant grid on launch; keyed by Firebase uid.
enum SavedReelsListDiskCache {
    private static let subfolder = "saved-reels-list"

    /// Drop on-disk snapshot if it has not been refreshed successfully in this long (multi-device drift; rare invalidation).
    static let maxStaleInterval: TimeInterval = 24 * 60 * 60

    private static func directoryURL() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Roam", isDirectory: true)
            .appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(userId: String) throws -> URL {
        try directoryURL().appendingPathComponent("\(userId).json", isDirectory: false)
    }

    static func load(userId: String) -> APIClient.SavedReelsListCacheEnvelope? {
        guard !userId.isEmpty,
              let url = try? fileURL(userId: userId),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let envelope = try? JSONDecoder.roam.decode(APIClient.SavedReelsListCacheEnvelope.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        let age = Date().timeIntervalSince(envelope.fetchedAt)
        if age > maxStaleInterval {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return envelope
    }

    static func save(userId: String, envelope: APIClient.SavedReelsListCacheEnvelope) {
        guard !userId.isEmpty, let url = try? fileURL(userId: userId) else { return }
        guard let data = try? JSONEncoder.roam.encode(envelope) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func remove(userId: String) {
        guard let url = try? fileURL(userId: userId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func clearAll() {
        guard let dir = try? directoryURL() else { return }
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
