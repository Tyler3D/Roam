import SwiftUI
import UIKit

struct ItemDetailView: View {
    let item: SharedItem

    @State private var metadataTitle: String?
    @State private var metadataIcon: UIImage?
    @State private var metadataImage: UIImage?
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var videoTypeIdentifiers: [String] = []
    @State private var videoDataSize: Int?
    @State private var videoLoadError: String?
    @State private var avAssetStatus: String?
    @State private var avAssetDuration: Double?
    @State private var extractedFrames: [UIImage] = []
    @State private var frameExtractionLog: [String] = []

    @State private var ogScrapeLog: [String] = []
    @State private var ogVideoURL: String?
    @State private var ogAllTags: [String: String] = [:]
    @State private var ogScrapedFrames: [UIImage] = []
    @State private var ogScrapeError: String?

    @State private var oEmbedFields: [String: String] = [:]
    @State private var oEmbedError: String?
    @State private var oEmbedThumbnail: UIImage?

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
                if isLoading {
                    Text("Waiting for metadata fetch...")
                        .foregroundStyle(.secondary)
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
                if isLoading {
                    Text("Waiting for fetch...")
                        .foregroundStyle(.secondary)
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

        let r = await ReelMetadataService.extract(url: url, shareText: item.text)

        metadataTitle = r.metadataTitle
        metadataIcon = r.metadataIcon
        metadataImage = r.metadataImage
        errorMessage = r.errorMessage

        videoTypeIdentifiers = r.videoTypeIdentifiers
        videoDataSize = r.videoDataSize
        videoLoadError = r.videoLoadError
        avAssetStatus = r.avAssetStatus
        avAssetDuration = r.avAssetDuration
        extractedFrames = r.extractedFrames
        frameExtractionLog = r.frameExtractionLog

        ogScrapeLog = r.ogScrapeLog
        ogVideoURL = r.ogVideoURL
        ogAllTags = r.ogAllTags
        ogScrapedFrames = r.ogScrapedFrames
        ogScrapeError = r.ogScrapeError

        oEmbedFields = r.oEmbedFields
        oEmbedError = r.oEmbedError
        oEmbedThumbnail = r.oEmbedThumbnail
    }
}
