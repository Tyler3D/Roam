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
                await stores.reels.refresh()
            }
            .onAppear {
                reloadLocal()
                Task { await stores.reels.refresh() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reloadLocal()
                    Task {
                        await stores.reels.refresh()
                        await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
                    }
                }
            }
            .task {
                await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
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

    private func queuedReelCell(_ q: QueuedReelIngest) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let path = ShareQueueStore.thumbnailFileURL(for: q),
                       let ui = UIImage(contentsOfFile: path.path) {
                        Image(uiImage: ui)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoamColors.logan.opacity(0.12)
                    }
                }
                .frame(minHeight: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(queuedStatusChip(q.uploadStatus))
                    .font(RoamFont.mono(8, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(6)
            }

            Text(q.displayTitle)
                .font(RoamFont.mono(10))
                .lineLimit(2)
                .foregroundStyle(RoamColors.loganDark)
        }
        .padding(2)
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
                        reelCell(reel, highlight: isScanHighlightReel(reel))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var scanningBanner: some View {
        Text("Scanning for Roamable ideas")
            .font(RoamFont.mono(11, weight: .medium))
            .foregroundStyle(RoamColors.loganDark)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoamColors.logan.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func isScanHighlightReel(_ reel: APIClient.SavedReelListItemDTO) -> Bool {
        guard let rid = shareIngress.ingestScanState?.reelId else { return false }
        return reel.id.uuidString.lowercased() == rid
    }

    private func reelCell(_ reel: APIClient.SavedReelListItemDTO, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                ReelThumbnailImageView(reelId: reel.id, signedUrl: reel.thumbnailSignedUrl, contentMode: .fill)
                .frame(minHeight: 120)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(statusChip(reel.status))
                    .font(RoamFont.mono(8, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(6)
            }

            Text(reel.title.isEmpty ? reel.reelUrl : reel.title)
                .font(RoamFont.mono(10))
                .lineLimit(2)
                .foregroundStyle(RoamColors.loganDark)
        }
        .padding(2)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(highlight ? RoamColors.loganDeep : Color.clear, lineWidth: highlight ? 2 : 0)
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

/// Legacy name used by `ContentView` reel-only mode.
typealias ReelIngestionPage = ReelsPage
