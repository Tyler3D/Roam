import Foundation

/// App-group file queue: metadata + JPEGs saved by the share extension; uploaded when the main app runs.
enum ShareQueueStore {
    private static let appGroupID = SharedStore.appGroupID
    private static let ioLock = NSLock()

    private static var queueRoot: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return nil
        }
        let dir = base.appendingPathComponent("Library/Application Support/Roam/share-ingest-queue", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var manifestURL: URL? {
        queueRoot?.appendingPathComponent("manifest.json", isDirectory: false)
    }

    private static func itemFolder(id: UUID) -> URL? {
        queueRoot?.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
    }

    // MARK: - Manifest

    static func loadAll() -> [QueuedReelIngest] {
        ioLock.lock()
        defer { ioLock.unlock() }
        guard let url = manifestURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([QueuedReelIngest].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func updateItem(id: UUID, _ mutate: (inout QueuedReelIngest) -> Void) {
        ioLock.lock()
        defer { ioLock.unlock() }
        var items = loadAllUnlocked()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
        saveAllUnlocked(items)
    }

    private static func loadAllUnlocked() -> [QueuedReelIngest] {
        guard let url = manifestURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([QueuedReelIngest].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func saveAllUnlocked(_ items: [QueuedReelIngest]) {
        guard let url = manifestURL else { return }
        if let data = try? JSONEncoder().encode(items) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    // MARK: - Public

    /// Insert a new row (URL only); extension will attach metadata + files next.
    @discardableResult
    static func enqueue(reelUrl: String, shareText: String?, attachmentTypeIdentifiers: [String]) -> UUID {
        let id = UUID()
        let item = QueuedReelIngest(
            id: id,
            reelUrl: reelUrl,
            shareText: shareText,
            attachmentTypeIdentifiers: attachmentTypeIdentifiers,
            createdAt: Date(),
            reelTitle: nil,
            ogDescription: nil,
            ogKeywords: nil,
            thumbnailFilename: nil,
            frameFilenames: [],
            uploadStatus: .pendingUpload,
            lastUploadError: nil
        )
        ioLock.lock()
        defer { ioLock.unlock() }
        var items = loadAllUnlocked()
        items.insert(item, at: 0)
        saveAllUnlocked(items)
        if let folder = itemFolder(id: id) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return id
    }

    static func attachPack(id: UUID, pack: ReelMetadataService.ExtractResult) {
        ioLock.lock()
        defer { ioLock.unlock() }
        var items = loadAllUnlocked()
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        guard let folder = itemFolder(id: id) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var item = items[idx]
        item.reelTitle = pack.ingestReelTitle
        item.ogDescription = pack.ingestOgDescription
        item.ogKeywords = pack.ingestOgKeywords

        if let jpeg = pack.thumbnailJPEG, !jpeg.isEmpty {
            let name = "thumb.jpg"
            try? jpeg.write(to: folder.appendingPathComponent(name), options: [.atomic])
            item.thumbnailFilename = name
        }

        var frameNames: [String] = []
        for (i, data) in pack.frameJPEGs.enumerated() where !data.isEmpty {
            let name = "frame\(i).jpg"
            try? data.write(to: folder.appendingPathComponent(name), options: [.atomic])
            frameNames.append(name)
        }
        item.frameFilenames = frameNames
        item.uploadStatus = .pendingUpload
        item.lastUploadError = nil
        items[idx] = item
        saveAllUnlocked(items)
    }

    static func itemsPendingUpload() -> [QueuedReelIngest] {
        loadAll().filter { $0.uploadStatus == .pendingUpload }
    }

    /// Newest first; includes uploading / failed / pending.
    static func itemsForGrid() -> [QueuedReelIngest] {
        loadAll().sorted { $0.createdAt > $1.createdAt }
    }

    static func item(id: UUID) -> QueuedReelIngest? {
        loadAll().first { $0.id == id }
    }

    static func thumbnailFileURL(for item: QueuedReelIngest) -> URL? {
        guard let name = item.thumbnailFilename else { return nil }
        return itemFolder(id: item.id)?.appendingPathComponent(name)
    }

    static func loadFrameData(for item: QueuedReelIngest) -> [Data] {
        guard let folder = itemFolder(id: item.id) else { return [] }
        return item.frameFilenames.compactMap { try? Data(contentsOf: folder.appendingPathComponent($0)) }
    }

    static func loadThumbnailData(for item: QueuedReelIngest) -> Data? {
        guard let url = thumbnailFileURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func markUploading(id: UUID) {
        updateItem(id: id) {
            $0.uploadStatus = .uploading
            $0.lastUploadError = nil
        }
    }

    static func markFailed(id: UUID, message: String) {
        updateItem(id: id) {
            $0.uploadStatus = .failed
            $0.lastUploadError = message
        }
    }

    static func remove(id: UUID) {
        ioLock.lock()
        defer { ioLock.unlock() }
        var items = loadAllUnlocked()
        items.removeAll { $0.id == id }
        saveAllUnlocked(items)
        if let folder = itemFolder(id: id) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static func resetToPending(id: UUID) {
        updateItem(id: id) {
            $0.uploadStatus = .pendingUpload
            $0.lastUploadError = nil
        }
    }
}
