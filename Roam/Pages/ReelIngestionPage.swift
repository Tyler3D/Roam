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
                    if let scan = shareIngress.ingestScanState,
                       let rid = scan.reelId,
                       stores.reels.reels.contains(where: { $0.id.uuidString.lowercased() == rid && $0.status == "processing" }) {
                        scanningBanner
                    }
                    reelsGridSection
                }
                .id(shareIngress.shareQueueEpoch)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 120)
            }
            .navigationTitle("")
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
                ToolbarItem(placement: .principal) {
                    Text("reels")
                        .font(RoamFont.mono(15, weight: .bold))
                        .foregroundStyle(RoamColors.text)
                }
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
        let queueRows = ShareQueueStore.itemsForGrid()
        let completelyEmpty = stores.reels.reels.isEmpty && localItems.isEmpty && queueRows.isEmpty
        let showSavedHeader = !completelyEmpty
            || stores.reels.isLoading
            || (stores.reels.lastError != nil && stores.reels.reels.isEmpty)

        VStack(alignment: .leading, spacing: 12) {
            if showSavedHeader {
                Text("saved")
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1)
            }

            if stores.reels.isLoading && stores.reels.reels.isEmpty {
                ProgressView("loading…")
                    .font(RoamFont.mono(11))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
            } else if let err = stores.reels.lastError, stores.reels.reels.isEmpty {
                Text(err)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.error)
            } else if completelyEmpty {
                ReelsOnboardingEmptyState()
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
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
        let attention = ReelCellAttention.forSavedReel(reel)
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
    case searching
    case needsReview
    case failed

    /// Purely data-driven: uses only `reel.status` so the cell updates as soon as the store refreshes.
    static func forSavedReel(_ reel: APIClient.SavedReelListItemDTO) -> ReelCellAttention {
        switch reel.status {
        case "processing": return .searching
        case "needs_review": return .needsReview
        case "failed": return .failed
        default: return .none
        }
    }

    var outlineColor: Color {
        switch self {
        case .none: return .clear
        case .searching: return RoamColors.loganDeep
        case .needsReview: return RoamColors.actionRequired
        case .failed: return RoamColors.error
        }
    }

    var outlineWidth: CGFloat {
        switch self {
        case .none: return 0
        case .searching: return 2
        case .needsReview, .failed: return 2.5
        }
    }

    var ribbon: (title: String, fill: Color)? {
        switch self {
        case .searching: return ("Searching…", RoamColors.loganDeep)
        case .needsReview: return ("Action required", RoamColors.actionRequired)
        case .failed: return ("Upload failed", RoamColors.error)
        case .none: return nil
        }
    }

    var showTrailingStatusChip: Bool {
        switch self {
        case .searching, .needsReview, .failed: return false
        case .none: return true
        }
    }
}

// MARK: - Empty state (no reels)

/// Consumer-style onboarding when there are no saved reels, queue items, or inbox links.
private struct ReelsOnboardingEmptyState: View {
    var body: some View {
        VStack(spacing: 0) {
            appsToRoamIllustration
                .padding(.bottom, 28)

            Text("No reels yet")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RoamColors.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("When you find a reel with a place you want to try, share it to Roam. We'll extract the places and save them for you.")
                .font(.system(size: 14))
                .foregroundStyle(RoamColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.bottom, 28)

            VStack(spacing: 10) {
                howStep(number: "1") {
                    (
                        Text("Open a reel in ")
                            + Text("Instagram").fontWeight(.semibold)
                            + Text(" or ")
                            + Text("TikTok").fontWeight(.semibold)
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(RoamColors.text)
                }

                howStep(number: "2", hint: "Roam appears in your share sheet like Messages or Mail") {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Tap the ")
                        Text("Share")
                            .fontWeight(.semibold)
                        Text(" button, then choose ")
                        Text("Roam")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(RoamColors.text)
                }

                howStep(number: "3") {
                    Text("Your reel shows up here — review and save the places")
                        .font(.system(size: 13))
                        .foregroundStyle(RoamColors.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                sourcePill(dot: .instagramGradient, label: "Instagram Reels")
                sourcePill(dot: .tiktokBlack, label: "TikTok")
            }
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
    }

    private var appsToRoamIllustration: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(spacing: 10) {
                instagramAppIcon
                tiktokAppIcon
            }

            VStack(spacing: 6) {
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(RoamColors.reviewBorder)
                        .frame(width: 40, height: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(RoamColors.reviewAccent)
                        .offset(x: 3)
                }
                Text("share")
                    .font(RoamFont.mono(8, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .frame(width: 44)

            Text("roam")
                .font(RoamFont.mono(10, weight: .bold))
                .foregroundStyle(.white)
                .tracking(-0.3)
                .frame(width: 56, height: 56)
                .background(RoamColors.reviewAccent)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: RoamColors.reviewAccent.opacity(0.35), radius: 8, y: 2)
        }
        .frame(height: 160)
        .frame(maxWidth: .infinity)
    }

    private var instagramAppIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.94, green: 0.58, blue: 0.20),
                            Color(red: 0.90, green: 0.41, blue: 0.24),
                            Color(red: 0.86, green: 0.15, blue: 0.26),
                            Color(red: 0.80, green: 0.14, blue: 0.40),
                            Color(red: 0.74, green: 0.09, blue: 0.53)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 2.5)
                .frame(width: 26, height: 26)
                .overlay {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .frame(width: 6, height: 6)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 3, height: 3)
                            .offset(x: 5, y: -5)
                    }
                }
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    private var tiktokAppIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 1 / 255, green: 1 / 255, blue: 1 / 255))
            ZStack {
                Text("♪")
                    .foregroundStyle(Color(red: 0.145, green: 0.956, blue: 0.933))
                    .offset(x: -3, y: -2)
                Text("♪")
                    .foregroundStyle(Color(red: 0.996, green: 0.173, blue: 0.333))
                    .offset(x: 1, y: 1)
                Text("♪")
                    .foregroundStyle(.white)
                    .offset(x: -1, y: -0.5)
            }
            .font(.system(size: 20, weight: .black))
        }
        .frame(width: 56, height: 56)
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }

    private func howStep(number: String, hint: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(RoamFont.mono(11, weight: .bold))
                .foregroundStyle(RoamColors.reviewAccent)
                .frame(width: 26, height: 26)
                .background(RoamColors.reviewAccentLight)
                .clipShape(Circle())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                }
            }
        }
        .padding(12)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private enum SourceDot {
        case instagramGradient
        case tiktokBlack
    }

    private func sourcePill(dot: SourceDot, label: String) -> some View {
        HStack(spacing: 5) {
            Group {
                switch dot {
                case .instagramGradient:
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.94, green: 0.58, blue: 0.20),
                                    Color(red: 0.74, green: 0.09, blue: 0.53)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                case .tiktokBlack:
                    Circle()
                        .fill(Color(red: 1 / 255, green: 1 / 255, blue: 1 / 255))
                }
            }
            .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(RoamColors.surface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
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
