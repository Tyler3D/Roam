import SwiftUI
import LinkPresentation
import AVFoundation
import UniformTypeIdentifiers

struct ItemDetailView: View {
    let item: SharedItem

    @State private var metadataTitle: String?
    @State private var metadataIcon: UIImage?
    @State private var metadataImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Video investigation state (LinkPresentation)
    @State private var videoTypeIdentifiers: [String] = []
    @State private var videoDataSize: Int?
    @State private var videoLoadError: String?
    @State private var avAssetStatus: String?
    @State private var avAssetDuration: Double?
    @State private var extractedFrames: [UIImage] = []
    @State private var frameExtractionLog: [String] = []

    // OG scraping state
    @State private var ogScrapeLog: [String] = []
    @State private var ogVideoURL: String?
    @State private var ogAllTags: [String: String] = [:]
    @State private var ogScrapedFrames: [UIImage] = []
    @State private var ogScrapeError: String?
    @State private var isScraping = false

    // oEmbed state
    @State private var oEmbedFields: [String: String] = [:]
    @State private var oEmbedError: String?
    @State private var oEmbedThumbnail: UIImage?
    @State private var isFetchingOEmbed = false

    var body: some View {
        List {
            Section("Raw Share Data") {
                row("URL", value: item.url)
                row("Text", value: item.text)
                row("Date", value: item.dateShared.formatted())
                row("Type Identifiers", value: item.attachmentTypeIdentifiers.joined(separator: "\n"))
            }

            Section("LinkPresentation Metadata") {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Fetching metadata...")
                            .foregroundStyle(.secondary)
                    }
                } else if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                } else if metadataTitle != nil || metadataImage != nil {
                    row("Title", value: metadataTitle)

                    if let icon = metadataIcon {
                        LabeledContent("Icon") {
                            Image(uiImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    if let image = metadataImage {
                        VStack(alignment: .leading) {
                            Text("Preview Image")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                } else {
                    Text("No metadata available")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Video Provider Investigation") {
                if videoTypeIdentifiers.isEmpty && videoLoadError == nil && videoDataSize == nil {
                    if isLoading {
                        Text("Waiting for metadata fetch...")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No video provider found")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if !videoTypeIdentifiers.isEmpty {
                        row("Registered Type IDs", value: videoTypeIdentifiers.joined(separator: "\n"))
                    }

                    if let size = videoDataSize {
                        row("Video Data Size", value: formatBytes(size))
                    }

                    if let error = videoLoadError {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Video Load Error")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(error)
                                .font(.body)
                                .foregroundStyle(.red)
                        }
                    }

                    if let status = avAssetStatus {
                        row("AVAsset Status", value: status)
                    }

                    if let duration = avAssetDuration {
                        row("Video Duration", value: String(format: "%.1fs", duration))
                    }

                    if !frameExtractionLog.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Frame Extraction Log")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(frameExtractionLog, id: \.self) { line in
                                Text(line)
                                    .font(.caption2)
                                    .monospaced()
                            }
                        }
                    }
                }
            }

            if !extractedFrames.isEmpty {
                Section("Extracted Frames (\(extractedFrames.count))") {
                    ForEach(Array(extractedFrames.enumerated()), id: \.offset) { index, frame in
                        VStack(alignment: .leading) {
                            Text("Frame \(index)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(uiImage: frame)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            Section("OG Scrape Investigation") {
                if isScraping {
                    HStack {
                        ProgressView()
                        Text("Fetching HTML...")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = ogScrapeError {
                    Text(error).foregroundStyle(.red)
                } else if ogAllTags.isEmpty && ogScrapeLog.isEmpty {
                    Text("Waiting for metadata fetch...")
                        .foregroundStyle(.secondary)
                } else {
                    if let videoURL = ogVideoURL {
                        row("og:video", value: videoURL)
                    } else {
                        Text("No og:video tag found")
                            .foregroundStyle(.orange)
                    }

                    if !ogAllTags.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("All OG Tags")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(ogAllTags.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(key)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospaced()
                                    Text(value)
                                        .font(.caption)
                                        .textSelection(.enabled)
                                        .lineLimit(3)
                                }
                            }
                        }
                    }

                    if !ogScrapeLog.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Scrape Log")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(ogScrapeLog, id: \.self) { line in
                                Text(line)
                                    .font(.caption2)
                                    .monospaced()
                            }
                        }
                    }
                }
            }

            if !ogScrapedFrames.isEmpty {
                Section("OG Scraped Frames (\(ogScrapedFrames.count))") {
                    ForEach(Array(ogScrapedFrames.enumerated()), id: \.offset) { index, frame in
                        VStack(alignment: .leading) {
                            Text("Frame \(index)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(uiImage: frame)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            Section("Instagram oEmbed API") {
                if isFetchingOEmbed {
                    HStack {
                        ProgressView()
                        Text("Fetching oEmbed...")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = oEmbedError {
                    Text(error).foregroundStyle(.red)
                } else if oEmbedFields.isEmpty {
                    Text("Waiting for fetch...")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(oEmbedFields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(key)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospaced()
                            Text(value)
                                .font(.caption)
                                .textSelection(.enabled)
                                .lineLimit(5)
                        }
                    }

                    if let thumb = oEmbedThumbnail {
                        VStack(alignment: .leading) {
                            Text("oEmbed Thumbnail")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(uiImage: thumb)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { await fetchMetadata() }
    }

    @ViewBuilder
    private func row(_ label: String, value: String?) -> some View {
        if let value, !value.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private func fetchMetadata() async {
        guard let urlString = item.url, let url = URL(string: urlString) else {
            errorMessage = "No URL to fetch metadata for."
            return
        }

        isLoading = true
        defer { isLoading = false }

        let provider = LPMetadataProvider()
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            metadataTitle = metadata.title

            if let iconProvider = metadata.iconProvider {
                metadataIcon = await loadImage(from: iconProvider)
            }
            if let imageProvider = metadata.imageProvider {
                metadataImage = await loadImage(from: imageProvider)
            }
            if let videoProvider = metadata.videoProvider {
                await investigateVideoProvider(videoProvider)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        await scrapeOGTags(from: url)
        await fetchOEmbed(for: url)
    }

    private func investigateVideoProvider(_ provider: NSItemProvider) async {
        videoTypeIdentifiers = provider.registeredTypeIdentifiers

        // Try loading as movie Data
        let movieTypes = [
            UTType.movie.identifier,
            UTType.mpeg4Movie.identifier,
            UTType.quickTimeMovie.identifier,
            UTType.video.identifier,
            "public.movie",
            "public.mpeg-4",
        ]

        for typeID in movieTypes {
            guard provider.hasItemConformingToTypeIdentifier(typeID) else { continue }

            addLog("Trying loadDataRepresentation for: \(typeID)")

            do {
                let data = try await loadData(from: provider, typeIdentifier: typeID)
                videoDataSize = data.count
                addLog("Got \(formatBytes(data.count)) of data")
                await tryExtractFrames(from: data)
                return
            } catch {
                addLog("loadDataRepresentation failed: \(error.localizedDescription)")
            }

            // Try loading as URL instead
            addLog("Trying loadItem as URL for: \(typeID)")
            do {
                let url = try await loadURL(from: provider, typeIdentifier: typeID)
                addLog("Got URL: \(url.absoluteString)")
                addLog("Is file URL: \(url.isFileURL)")

                if url.isFileURL {
                    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                    let size = attrs[.size] as? Int ?? 0
                    videoDataSize = size
                    addLog("File size: \(formatBytes(size))")
                }

                await tryExtractFramesFromURL(url)
                return
            } catch {
                addLog("loadItem as URL failed: \(error.localizedDescription)")
            }
        }

        // If nothing worked with specific types, try all registered identifiers
        for typeID in provider.registeredTypeIdentifiers {
            guard !movieTypes.contains(typeID) else { continue }
            addLog("Trying fallback type: \(typeID)")

            do {
                let data = try await loadData(from: provider, typeIdentifier: typeID)
                videoDataSize = data.count
                addLog("Got \(formatBytes(data.count)) from \(typeID)")
                await tryExtractFrames(from: data)
                return
            } catch {
                addLog("Fallback \(typeID) failed: \(error.localizedDescription)")
            }
        }

        videoLoadError = "Could not load video data from any type identifier"
    }

    private func tryExtractFrames(from data: Data) async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            try data.write(to: tempURL)
            addLog("Wrote temp file: \(formatBytes(data.count))")
            await tryExtractFramesFromURL(tempURL)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            addLog("Failed to write temp file: \(error.localizedDescription)")
        }
    }

    private func tryExtractFramesFromURL(_ url: URL) async {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            avAssetDuration = durationSeconds
            avAssetStatus = "Loaded (duration: \(String(format: "%.1fs", durationSeconds)))"
            addLog("AVAsset loaded, duration: \(String(format: "%.1fs", durationSeconds))")

            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            addLog("Video tracks: \(videoTracks.count)")

            if videoTracks.isEmpty {
                avAssetStatus = "No video tracks found"
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1280)

            // Extract 1 frame per second, capped at 10
            let frameCount = min(Int(durationSeconds), 10)
            guard frameCount > 0 else {
                addLog("Duration too short for frame extraction")
                return
            }

            let interval = durationSeconds / Double(frameCount)
            addLog("Extracting \(frameCount) frames (1 every \(String(format: "%.1fs", interval)))")

            var frames: [UIImage] = []
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    let uiImage = UIImage(cgImage: cgImage)
                    frames.append(uiImage)
                    addLog("Frame \(i): \(Int(uiImage.size.width))x\(Int(uiImage.size.height))")
                } catch {
                    addLog("Frame \(i) failed: \(error.localizedDescription)")
                }
            }

            extractedFrames = frames
            addLog("Extraction complete: \(frames.count) frames")
        } catch {
            avAssetStatus = "Failed: \(error.localizedDescription)"
            addLog("AVAsset load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - OG Tag Scraping

    private func scrapeOGTags(from url: URL) async {
        isScraping = true
        defer { isScraping = false }

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                addOGLog("HTTP \(httpResponse.statusCode)")
                addOGLog("Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            }

            guard let html = String(data: data, encoding: .utf8) else {
                ogScrapeError = "Could not decode HTML as UTF-8"
                addOGLog("Failed to decode response as UTF-8 (\(formatBytes(data.count)))")
                return
            }

            addOGLog("HTML size: \(formatBytes(data.count))")

            let tags = parseOGTags(from: html)
            ogAllTags = tags
            addOGLog("Found \(tags.count) OG tags")

            if let videoURLString = tags["og:video"] ?? tags["og:video:url"] ?? tags["og:video:secure_url"] {
                ogVideoURL = videoURLString
                addOGLog("Found og:video: \(videoURLString.prefix(100))...")

                if let videoURL = URL(string: videoURLString) {
                    await downloadAndExtractFrames(from: videoURL)
                }
            } else {
                addOGLog("No og:video tag in HTML")

                let videoRelated = tags.filter { $0.key.contains("video") }
                if !videoRelated.isEmpty {
                    addOGLog("Video-related tags: \(videoRelated.keys.joined(separator: ", "))")
                }
            }
        } catch {
            ogScrapeError = error.localizedDescription
            addOGLog("Fetch failed: \(error.localizedDescription)")
        }
    }

    private func parseOGTags(from html: String) -> [String: String] {
        var tags: [String: String] = [:]

        // Match <meta property="og:xxx" content="yyy"> and <meta name="xxx" content="yyy">
        let patterns = [
            #"<meta\s+property\s*=\s*"([^"]+)"\s+content\s*=\s*"([^"]*)"#,
            #"<meta\s+content\s*=\s*"([^"]*)"\s+property\s*=\s*"([^"]+)"#,
            #"<meta\s+name\s*=\s*"([^"]+)"\s+content\s*=\s*"([^"]*)"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            let matches = regex.matches(in: html, range: range)

            for match in matches {
                guard match.numberOfRanges >= 3,
                      let keyRange = Range(match.range(at: 1), in: html),
                      let valueRange = Range(match.range(at: 2), in: html) else { continue }

                let key = String(html[keyRange])
                let value = String(html[valueRange])

                // For the reversed pattern, swap key and value
                if pattern.contains("content.*property") {
                    tags[value] = key
                } else {
                    tags[key] = value
                }
            }
        }

        return tags
    }

    private func downloadAndExtractFrames(from videoURL: URL) async {
        addOGLog("Downloading video from og:video URL...")

        var request = URLRequest(url: videoURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                addOGLog("Video download: HTTP \(httpResponse.statusCode)")
                addOGLog("Video size: \(formatBytes(data.count))")
                addOGLog("Video Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            }

            guard data.count > 1000 else {
                addOGLog("Response too small to be a video (\(data.count) bytes)")
                return
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            try data.write(to: tempURL)
            addOGLog("Wrote video to temp file")

            let asset = AVURLAsset(url: tempURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            addOGLog("AVAsset duration: \(String(format: "%.1fs", durationSeconds))")

            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            addOGLog("Video tracks: \(videoTracks.count)")

            guard !videoTracks.isEmpty, durationSeconds > 0 else {
                addOGLog("No usable video tracks")
                try? FileManager.default.removeItem(at: tempURL)
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1280)

            let frameCount = min(Int(durationSeconds), 10)
            guard frameCount > 0 else { return }

            let interval = durationSeconds / Double(frameCount)
            addOGLog("Extracting \(frameCount) frames...")

            var frames: [UIImage] = []
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    frames.append(UIImage(cgImage: cgImage))
                } catch {
                    addOGLog("OG Frame \(i) failed: \(error.localizedDescription)")
                }
            }

            ogScrapedFrames = frames
            addOGLog("OG extraction complete: \(frames.count) frames")

            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            addOGLog("Video download/extraction failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Instagram oEmbed

    private func fetchOEmbed(for url: URL) async {
        isFetchingOEmbed = true
        defer { isFetchingOEmbed = false }

        guard var components = URLComponents(string: "https://api.instagram.com/oembed") else {
            oEmbedError = "Failed to build oEmbed URL"
            return
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "maxwidth", value: "720"),
            URLQueryItem(name: "omitscript", value: "true"),
        ]

        guard let oEmbedURL = components.url else {
            oEmbedError = "Invalid oEmbed URL"
            return
        }

        var request = URLRequest(url: oEmbedURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        oEmbedFields["_request_url"] = oEmbedURL.absoluteString

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                oEmbedFields["_http_status"] = "\(httpResponse.statusCode)"
                oEmbedFields["_content_type"] = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

                guard httpResponse.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "(no body)"
                    oEmbedError = "HTTP \(httpResponse.statusCode): \(String(body.prefix(300)))"
                    return
                }
            }

            let rawBody = String(data: data, encoding: .utf8) ?? "(binary, \(data.count) bytes)"

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                oEmbedError = "Not JSON. Raw response (\(data.count) bytes):\n\(String(rawBody.prefix(500)))"
                return
            }

            var fields: [String: String] = [:]
            for (key, value) in json {
                if key == "html" {
                    let htmlStr = String(describing: value)
                    fields[key] = String(htmlStr.prefix(300)) + (htmlStr.count > 300 ? "..." : "")
                } else {
                    fields[key] = String(describing: value)
                }
            }
            oEmbedFields = fields

            if let thumbnailURLString = json["thumbnail_url"] as? String,
               let thumbnailURL = URL(string: thumbnailURLString) {
                let (thumbData, _) = try await URLSession.shared.data(from: thumbnailURL)
                oEmbedThumbnail = UIImage(data: thumbData)
            }
        } catch {
            oEmbedError = error.localizedDescription
        }
    }

    private func addOGLog(_ message: String) {
        ogScrapeLog.append(message)
    }

    private func addLog(_ message: String) {
        frameExtractionLog.append(message)
    }

    private func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                continuation.resume(returning: image as? UIImage)
            }
        }
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "VideoDebug", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data returned"]))
                }
            }
        }
    }

    private func loadURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "VideoDebug", code: -2, userInfo: [NSLocalizedDescriptionKey: "Item was not a URL (got \(type(of: item)))"]))
                }
            }
        }
    }
}
