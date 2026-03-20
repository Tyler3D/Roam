import SwiftUI

/// Server-backed saved reels grid + local share inbox until upload. See [`POST /api/ingest`](backend/app/api/ingest.py).
struct ReelsPage: View {
    @Environment(\.apiClient) private var apiClient
    @Environment(\.roamStores) private var stores
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var shareIngress: ShareIngressCoordinator
    @State private var path = NavigationPath()
    @State private var localItems: [SharedItem] = []
    @State private var ingestError: String?
    @State private var ingestingId: UUID?

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    /// Fixed portrait frame so grid cells stay aligned regardless of thumbnail pixel dimensions.
    private static let gridThumbnailAspect: CGFloat = 9.0 / 16.0

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !localItems.isEmpty {
                        localInboxSection
                    }
                    onDeviceQueueSection
                    if shareIngress.ingestScanState != nil {
                        scanningBanner
                    }
                    reelsGridSection
                }
                .id(shareIngress.shareQueueEpoch)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .navigationTitle("reels")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { token in
                if token.hasPrefix("q:") {
                    let rest = String(token.dropFirst(2))
                    if let u = UUID(uuidString: rest) {
                        QueuedReelPreviewPage(queueId: u)
                    } else {
                        Text("invalid link")
                            .font(RoamFont.mono(11))
                    }
                } else {
                    ReelDetailPage(reelId: token)
                }
            }
            .toolbar {
                if !localItems.isEmpty {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button("Clear all local", role: .destructive) {
                                SharedStore.clearAll()
                                localItems = []
                            }
                        } label: {
                            Text("⋯")
                                .font(RoamFont.mono(16))
                        }
                    }
                }
            }
            .refreshable {
                await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
                await stores.reels.refresh()
                shareIngress.ensurePollingForProcessingReels(apiClient: apiClient, stores: stores)
            }
            .onAppear {
                reloadLocal()
                shareIngress.ensurePollingForProcessingReels(apiClient: apiClient, stores: stores)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reloadLocal()
                    Task {
                        await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
                        await stores.reels.refresh()
                        shareIngress.ensurePollingForProcessingReels(apiClient: apiClient, stores: stores)
                    }
                }
            }
            .task {
                await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
                await stores.reels.refresh()
                shareIngress.ensurePollingForProcessingReels(apiClient: apiClient, stores: stores)
            }
        }
    }

    private var onDeviceQueueSection: some View {
        let rows = ShareQueueStore.itemsForGrid()
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("on this device")
                        .font(RoamFont.mono(10, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1)

                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(rows) { q in
                            Button {
                                path.append("q:\(q.id.uuidString.lowercased())")
                            } label: {
                                queuedReelCell(q)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func queuedReelCell(_ q: QueuedReelIngest) -> some View {
        let uploadFailed = q.uploadStatus == .failed
        let deviceProcessing = !uploadFailed
            && (q.uploadStatus == .pendingUpload || q.uploadStatus == .uploading)
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .aspectRatio(Self.gridThumbnailAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            Group {
                                if let path = ShareQueueStore.thumbnailFileURL(for: q),
                                   let ui = UIImage(contentsOfFile: path.path) {
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    RoamColors.logan.opacity(0.12)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if !uploadFailed, !deviceProcessing {
                        Text(queuedStatusChip(q.uploadStatus))
                            .font(RoamFont.mono(8, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }

                if uploadFailed {
                    ReelAttentionRibbon(title: "Upload failed", fill: RoamColors.error)
                        .padding(.top, 6)
                        .padding(.leading, 6)
                } else if deviceProcessing {
                    ReelAttentionRibbon(
                        title: q.uploadStatus == .uploading ? "Uploading…" : "Reel processing",
                        fill: RoamColors.processingTeal
                    )
                    .padding(.top, 6)
                    .padding(.leading, 6)
                }
            }

            Text(q.displayTitle)
                .font(RoamFont.mono(10))
                .lineLimit(2)
                .foregroundStyle(RoamColors.loganDark)
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    uploadFailed ? RoamColors.error : (deviceProcessing ? RoamColors.processingTeal : Color.clear),
                    lineWidth: uploadFailed || deviceProcessing ? 2.5 : 0
                )
        )
    }

    private func queuedStatusChip(_ status: QueuedUploadStatus) -> String {
        switch status {
        case .pendingUpload: return "device"
        case .uploading: return "…"
        case .failed: return "retry"
        }
    }

    @ViewBuilder
    private var localInboxSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("inbox")
                .font(RoamFont.mono(10, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
                .tracking(1)
            if let ingestError {
                Text(ingestError)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.error)
            }
            ForEach(localItems) { item in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.url ?? item.text ?? "Unknown")
                            .font(RoamFont.mono(11))
                            .lineLimit(2)
                        Text(item.dateShared, style: .relative)
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                    Spacer(minLength: 0)
                    if reelURL(for: item) != nil {
                        Button {
                            Task { await ingestLocal(item) }
                        } label: {
                            Text("save")
                                .font(RoamFont.mono(10, weight: .medium))
                        }
                        .disabled(ingestingId != nil)
                        .buttonStyle(.bordered)
                        .tint(RoamColors.loganDeep)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var reelsGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("saved")
                .font(RoamFont.mono(10, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
                .tracking(1)

            if stores.reels.isLoading && stores.reels.reels.isEmpty {
                ProgressView("loading…")
                    .font(RoamFont.mono(11))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else if let err = stores.reels.lastError, stores.reels.reels.isEmpty {
                Text(err)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.error)
            } else if stores.reels.reels.isEmpty && localItems.isEmpty && ShareQueueStore.itemsForGrid().isEmpty {
                RoamEmptyState(
                    icon: "▦",
                    title: "no reels yet",
                    subtitle: "Share from Instagram — it saves here on your phone first, then uploads when you open Roam."
                )
                .padding(.top, 24)
            } else if stores.reels.reels.isEmpty {
                RoamEmptyState(
                    icon: "▦",
                    title: "no saved reels",
                    subtitle: "Use save on an inbox link to upload."
                )
                .padding(.top, 8)
            }

            LazyVGrid(columns: gridColumns, spacing: 12) {
                ForEach(stores.reels.reels) { reel in
                    Button {
                        path.append(reel.id.uuidString.lowercased())
                    } label: {
                        reelCell(reel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scanningBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Searching for Roamable ideas.")
                .font(RoamFont.mono(11, weight: .medium))
                .foregroundStyle(RoamColors.loganDark)
            Text("Give us a minute.")
                .font(RoamFont.mono(10))
                .foregroundStyle(RoamColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoamColors.logan.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func reelCell(_ reel: APIClient.SavedReelListItemDTO) -> some View {
        let attention = ReelCellAttention.forSavedReel(
            reel,
            scanReelId: shareIngress.ingestScanState?.reelId
        )
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .aspectRatio(Self.gridThumbnailAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .overlay {
                            ReelThumbnailImageView(reelId: reel.id, signedUrl: reel.thumbnailSignedUrl, contentMode: .fill)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if attention.showTrailingStatusChip {
                        Text(statusChip(reel.status))
                            .font(RoamFont.mono(8, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }

                if let ribbon = attention.ribbon {
                    ReelAttentionRibbon(title: ribbon.title, fill: ribbon.fill)
                        .padding(.top, 6)
                        .padding(.leading, 6)
                }
            }

            Text(reel.title.isEmpty ? reel.reelUrl : reel.title)
                .font(RoamFont.mono(10))
                .lineLimit(2)
                .foregroundStyle(RoamColors.loganDark)
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(attention.outlineColor, lineWidth: attention.outlineWidth)
        )
    }

    private func statusChip(_ status: String) -> String {
        switch status {
        case "needs_review": return "review"
        case "promoted": return "saved"
        case "processing": return "…"
        case "failed": return "err"
        default: return status
        }
    }

    private func reloadLocal() {
        localItems = SharedStore.loadAll()
    }

    private func reelURL(for item: SharedItem) -> String? {
        if let u = item.url, !u.isEmpty { return u }
        if let t = item.text, let url = URL(string: t), url.scheme == "http" || url.scheme == "https" {
            return t
        }
        return nil
    }

    private func ingestLocal(_ item: SharedItem) async {
        guard let urlString = reelURL(for: item), let url = URL(string: urlString) else {
            ingestError = "No URL to ingest"
            return
        }
        ingestError = nil
        ingestingId = item.id
        defer { ingestingId = nil }
        do {
            let pack = await ReelMetadataService.extract(url: url, shareText: item.text)
            let create = try await apiClient.submitIngest(
                reelUrl: urlString,
                shareText: item.text,
                reelTitle: pack.ingestReelTitle,
                ogDescription: pack.ingestOgDescription,
                ogKeywords: pack.ingestOgKeywords,
                thumbnailJPEG: pack.thumbnailJPEG,
                frameJPEGs: pack.frameJPEGs
            )
            ReelThumbnailDiskCache.saveAfterIngest(reelIdString: create.reelId, jpegData: pack.thumbnailJPEG)
            SharedStore.remove(id: item.id)
            reloadLocal()
            await stores.ideas.refresh()
            await stores.reels.refresh()
            let jobId = create.jobId
            Task {
                for _ in 0..<120 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let job = try? await apiClient.getIngestJob(jobId: jobId) else { continue }
                    if job.status == "done" || job.status == "failed" {
                        await stores.reels.refresh()
                        await stores.ideas.refresh()
                        break
                    }
                }
            }
        } catch {
            ingestError = error.localizedDescription
        }
    }
}

// MARK: - Reel grid attention (review / failed / in-flight scan)

private enum ReelCellAttention {
    case none
    case scanning
    case processing
    case needsReview
    case failed

    static func forSavedReel(_ reel: APIClient.SavedReelListItemDTO, scanReelId: String?) -> ReelCellAttention {
        let rid = reel.id.uuidString.lowercased()
        if let s = scanReelId?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty, s == rid {
            return .scanning
        }
        switch reel.status {
        case "failed": return .failed
        case "needs_review": return .needsReview
        case "processing": return .processing
        default: return .none
        }
    }

    var outlineColor: Color {
        switch self {
        case .none: return .clear
        case .scanning: return RoamColors.loganDeep
        case .processing: return RoamColors.processingTeal
        case .needsReview: return RoamColors.actionRequired
        case .failed: return RoamColors.error
        }
    }

    var outlineWidth: CGFloat {
        switch self {
        case .none: return 0
        case .scanning: return 2
        case .processing, .needsReview, .failed: return 2.5
        }
    }

    var ribbon: (title: String, fill: Color)? {
        switch self {
        case .scanning: return ("Searching…", RoamColors.loganDeep)
        case .processing: return ("Reel processing", RoamColors.processingTeal)
        case .needsReview: return ("Action required", RoamColors.actionRequired)
        case .failed: return ("Upload failed", RoamColors.error)
        case .none: return nil
        }
    }

    var showTrailingStatusChip: Bool {
        switch self {
        case .scanning, .processing, .needsReview, .failed: return false
        case .none: return true
        }
    }
}

private struct ReelAttentionRibbon: View {
    let title: String
    let fill: Color

    var body: some View {
        Text(title)
            .font(RoamFont.mono(7, weight: .semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .minimumScaleFactor(0.88)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 3,
                    bottomTrailingRadius: 14,
                    topTrailingRadius: 6,
                    style: .continuous
                )
                .fill(fill.opacity(0.92))
            )
            .shadow(color: Color.black.opacity(0.14), radius: 2, y: 1)
    }
}

/// Legacy name used by `ContentView` reel-only mode.
typealias ReelIngestionPage = ReelsPage
