import AVFoundation
import Foundation
import LinkPresentation
import UIKit
import UniformTypeIdentifiers

/// Shared LinkPresentation + optional OG / oEmbed enrichment for debug UI and reel ingest.
enum ReelMetadataService {

    struct ExtractResult {
        var metadataTitle: String?
        var metadataIcon: UIImage?
        var metadataImage: UIImage?
        var errorMessage: String?

        var videoTypeIdentifiers: [String] = []
        var videoDataSize: Int?
        var videoLoadError: String?
        var avAssetStatus: String?
        var avAssetDuration: Double?
        var extractedFrames: [UIImage] = []
        var frameExtractionLog: [String] = []

        var ogScrapeLog: [String] = []
        var ogVideoURL: String?
        var ogAllTags: [String: String] = [:]
        var ogScrapedFrames: [UIImage] = []
        var ogScrapeError: String?

        var oEmbedFields: [String: String] = [:]
        var oEmbedError: String?
        var oEmbedThumbnail: UIImage?

        /// Values suitable for `POST /api/ingest` multipart fields.
        var ingestReelTitle: String?
        var ingestOgDescription: String?
        var ingestOgKeywords: String?
        var thumbnailJPEG: Data?
        var frameJPEGs: [Data] = []
    }

    static func extract(url: URL, shareText: String?) async -> ExtractResult {
        var result = ExtractResult()

        let provider = LPMetadataProvider()
        do {
            let metadata = try await provider.startFetchingMetadata(for: url)
            result.metadataTitle = metadata.title

            if let iconProvider = metadata.iconProvider {
                result.metadataIcon = await loadImage(from: iconProvider)
            }
            if let imageProvider = metadata.imageProvider {
                result.metadataImage = await loadImage(from: imageProvider)
            }
            if let videoProvider = metadata.videoProvider {
                await investigateVideoProvider(videoProvider, result: &result)
            }
        } catch {
            result.errorMessage = error.localizedDescription
        }

        await scrapeOGTags(from: url, result: &result)
        await fetchOEmbed(for: url, result: &result)

        result.ingestReelTitle = result.metadataTitle
            ?? result.oEmbedFields["title"]
            ?? shareText?.split(separator: "\n").first.map(String.init)

        result.ingestOgDescription = result.ogAllTags["og:description"]
        result.ingestOgKeywords = result.ogAllTags["keywords"]
            ?? result.ogAllTags["og:keywords"]

        if let img = result.metadataImage {
            result.thumbnailJPEG = img.jpegData(compressionQuality: 0.85)
        } else if let thumb = result.oEmbedThumbnail {
            result.thumbnailJPEG = thumb.jpegData(compressionQuality: 0.85)
        }

        let frames = result.extractedFrames.isEmpty ? result.ogScrapedFrames : result.extractedFrames
        result.frameJPEGs = frames.compactMap { $0.jpegData(compressionQuality: 0.85) }

        return result
    }

    // MARK: - LinkPresentation / video

    private static func investigateVideoProvider(_ provider: NSItemProvider, result: inout ExtractResult) async {
        result.videoTypeIdentifiers = provider.registeredTypeIdentifiers

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

            addLog(&result, "Trying loadDataRepresentation for: \(typeID)")

            do {
                let data = try await loadData(from: provider, typeIdentifier: typeID)
                result.videoDataSize = data.count
                addLog(&result, "Got \(formatBytes(data.count)) of data")
                await tryExtractFrames(from: data, result: &result)
                return
            } catch {
                addLog(&result, "loadDataRepresentation failed: \(error.localizedDescription)")
            }

            addLog(&result, "Trying loadItem as URL for: \(typeID)")
            do {
                let fileURL = try await loadURL(from: provider, typeIdentifier: typeID)
                addLog(&result, "Got URL: \(fileURL.absoluteString)")
                addLog(&result, "Is file URL: \(fileURL.isFileURL)")

                if fileURL.isFileURL {
                    let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let size = attrs[.size] as? Int ?? 0
                    result.videoDataSize = size
                    addLog(&result, "File size: \(formatBytes(size))")
                }

                await tryExtractFramesFromURL(fileURL, result: &result)
                return
            } catch {
                addLog(&result, "loadItem as URL failed: \(error.localizedDescription)")
            }
        }

        for typeID in provider.registeredTypeIdentifiers {
            guard !movieTypes.contains(typeID) else { continue }
            addLog(&result, "Trying fallback type: \(typeID)")

            do {
                let data = try await loadData(from: provider, typeIdentifier: typeID)
                result.videoDataSize = data.count
                addLog(&result, "Got \(formatBytes(data.count)) from \(typeID)")
                await tryExtractFrames(from: data, result: &result)
                return
            } catch {
                addLog(&result, "Fallback \(typeID) failed: \(error.localizedDescription)")
            }
        }

        result.videoLoadError = "Could not load video data from any type identifier"
    }

    private static func tryExtractFrames(from data: Data, result: inout ExtractResult) async {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        do {
            try data.write(to: tempURL)
            addLog(&result, "Wrote temp file: \(formatBytes(data.count))")
            await tryExtractFramesFromURL(tempURL, result: &result)
            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            addLog(&result, "Failed to write temp file: \(error.localizedDescription)")
        }
    }

    private static func tryExtractFramesFromURL(_ url: URL, result: inout ExtractResult) async {
        let asset = AVURLAsset(url: url)

        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            result.avAssetDuration = durationSeconds
            result.avAssetStatus = "Loaded (duration: \(String(format: "%.1fs", durationSeconds)))"
            addLog(&result, "AVAsset loaded, duration: \(String(format: "%.1fs", durationSeconds))")

            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            addLog(&result, "Video tracks: \(videoTracks.count)")

            if videoTracks.isEmpty {
                result.avAssetStatus = "No video tracks found"
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1280)

            let frameCount = min(Int(durationSeconds), 10)
            guard frameCount > 0 else {
                addLog(&result, "Duration too short for frame extraction")
                return
            }

            let interval = durationSeconds / Double(frameCount)
            addLog(&result, "Extracting \(frameCount) frames (1 every \(String(format: "%.1fs", interval)))")

            var frames: [UIImage] = []
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    let uiImage = UIImage(cgImage: cgImage)
                    frames.append(uiImage)
                    addLog(&result, "Frame \(i): \(Int(uiImage.size.width))x\(Int(uiImage.size.height))")
                } catch {
                    addLog(&result, "Frame \(i) failed: \(error.localizedDescription)")
                }
            }

            result.extractedFrames = frames
            addLog(&result, "Extraction complete: \(frames.count) frames")
        } catch {
            result.avAssetStatus = "Failed: \(error.localizedDescription)"
            addLog(&result, "AVAsset load failed: \(error.localizedDescription)")
        }
    }

    // MARK: - OG

    private static func scrapeOGTags(from url: URL, result: inout ExtractResult) async {
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
                addOGLog(&result, "HTTP \(httpResponse.statusCode)")
                addOGLog(&result, "Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            }

            guard let html = String(data: data, encoding: .utf8) else {
                result.ogScrapeError = "Could not decode HTML as UTF-8"
                addOGLog(&result, "Failed to decode response as UTF-8 (\(formatBytes(data.count)))")
                return
            }

            addOGLog(&result, "HTML size: \(formatBytes(data.count))")

            let tags = parseOGTags(from: html)
            result.ogAllTags = tags
            addOGLog(&result, "Found \(tags.count) OG tags")

            if let videoURLString = tags["og:video"] ?? tags["og:video:url"] ?? tags["og:video:secure_url"] {
                result.ogVideoURL = videoURLString
                addOGLog(&result, "Found og:video: \(videoURLString.prefix(100))...")

                if let videoURL = URL(string: videoURLString) {
                    await downloadAndExtractFrames(from: videoURL, result: &result)
                }
            } else {
                addOGLog(&result, "No og:video tag in HTML")

                let videoRelated = tags.filter { $0.key.contains("video") }
                if !videoRelated.isEmpty {
                    addOGLog(&result, "Video-related tags: \(videoRelated.keys.joined(separator: ", "))")
                }
            }
        } catch {
            result.ogScrapeError = error.localizedDescription
            addOGLog(&result, "Fetch failed: \(error.localizedDescription)")
        }
    }

    private static func parseOGTags(from html: String) -> [String: String] {
        var tags: [String: String] = [:]

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

                if pattern.contains("content.*property") {
                    tags[value] = key
                } else {
                    tags[key] = value
                }
            }
        }

        return tags
    }

    private static func downloadAndExtractFrames(from videoURL: URL, result: inout ExtractResult) async {
        addOGLog(&result, "Downloading video from og:video URL...")

        var request = URLRequest(url: videoURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                addOGLog(&result, "Video download: HTTP \(httpResponse.statusCode)")
                addOGLog(&result, "Video size: \(formatBytes(data.count))")
                addOGLog(&result, "Video Content-Type: \(httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")
            }

            guard data.count > 1000 else {
                addOGLog(&result, "Response too small to be a video (\(data.count) bytes)")
                return
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")

            try data.write(to: tempURL)
            addOGLog(&result, "Wrote video to temp file")

            let asset = AVURLAsset(url: tempURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            addOGLog(&result, "AVAsset duration: \(String(format: "%.1fs", durationSeconds))")

            let tracks = try await asset.load(.tracks)
            let videoTracks = tracks.filter { $0.mediaType == .video }
            addOGLog(&result, "Video tracks: \(videoTracks.count)")

            guard !videoTracks.isEmpty, durationSeconds > 0 else {
                addOGLog(&result, "No usable video tracks")
                try? FileManager.default.removeItem(at: tempURL)
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 1280)

            let frameCount = min(Int(durationSeconds), 10)
            guard frameCount > 0 else { return }

            let interval = durationSeconds / Double(frameCount)
            addOGLog(&result, "Extracting \(frameCount) frames...")

            var frames: [UIImage] = []
            for i in 0..<frameCount {
                let time = CMTime(seconds: Double(i) * interval, preferredTimescale: 600)
                do {
                    let (cgImage, _) = try await generator.image(at: time)
                    frames.append(UIImage(cgImage: cgImage))
                } catch {
                    addOGLog(&result, "OG Frame \(i) failed: \(error.localizedDescription)")
                }
            }

            result.ogScrapedFrames = frames
            addOGLog(&result, "OG extraction complete: \(frames.count) frames")

            try? FileManager.default.removeItem(at: tempURL)
        } catch {
            addOGLog(&result, "Video download/extraction failed: \(error.localizedDescription)")
        }
    }

    // MARK: - oEmbed

    private static func fetchOEmbed(for url: URL, result: inout ExtractResult) async {
        guard var components = URLComponents(string: "https://api.instagram.com/oembed") else {
            result.oEmbedError = "Failed to build oEmbed URL"
            return
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: url.absoluteString),
            URLQueryItem(name: "maxwidth", value: "720"),
            URLQueryItem(name: "omitscript", value: "true"),
        ]

        guard let oEmbedURL = components.url else {
            result.oEmbedError = "Invalid oEmbed URL"
            return
        }

        var request = URLRequest(url: oEmbedURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            var fields: [String: String] = ["_request_url": oEmbedURL.absoluteString]

            if let httpResponse = response as? HTTPURLResponse {
                fields["_http_status"] = "\(httpResponse.statusCode)"
                fields["_content_type"] = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "unknown"

                guard httpResponse.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? "(no body)"
                    result.oEmbedError = "HTTP \(httpResponse.statusCode): \(String(body.prefix(300)))"
                    result.oEmbedFields = fields
                    return
                }
            }

            let rawBody = String(data: data, encoding: .utf8) ?? "(binary, \(data.count) bytes)"

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                result.oEmbedError = "Not JSON. Raw response (\(data.count) bytes):\n\(String(rawBody.prefix(500)))"
                result.oEmbedFields = fields
                return
            }

            for (key, value) in json {
                if key == "html" {
                    let htmlStr = String(describing: value)
                    fields[key] = String(htmlStr.prefix(300)) + (htmlStr.count > 300 ? "..." : "")
                } else {
                    fields[key] = String(describing: value)
                }
            }
            result.oEmbedFields = fields

            if let thumbnailURLString = json["thumbnail_url"] as? String,
               let thumbnailURL = URL(string: thumbnailURLString) {
                let (thumbData, _) = try await URLSession.shared.data(from: thumbnailURL)
                result.oEmbedThumbnail = UIImage(data: thumbData)
            }
        } catch {
            result.oEmbedError = error.localizedDescription
        }
    }

    // MARK: - NSItemProvider helpers

    private static func loadImage(from provider: NSItemProvider) async -> UIImage? {
        await withCheckedContinuation { continuation in
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                continuation.resume(returning: image as? UIImage)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "ReelMetadata", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data returned"]))
                }
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider, typeIdentifier: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier) { item, error in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "ReelMetadata", code: -2, userInfo: [NSLocalizedDescriptionKey: "Item was not a URL"]))
                }
            }
        }
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    private static func addLog(_ result: inout ExtractResult, _ message: String) {
        result.frameExtractionLog.append(message)
    }

    private static func addOGLog(_ result: inout ExtractResult, _ message: String) {
        result.ogScrapeLog.append(message)
    }
}
