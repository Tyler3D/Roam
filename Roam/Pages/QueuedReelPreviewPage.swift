import SwiftUI

/// Detail for a reel that is cached on-device and not yet (or failed) uploaded.
struct QueuedReelPreviewPage: View {
    let queueId: UUID

    @Environment(\.apiClient) private var apiClient
    @Environment(\.roamStores) private var stores
    @EnvironmentObject private var shareIngress: ShareIngressCoordinator
    @State private var item: QueuedReelIngest?

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                Text("This reel is no longer on device.")
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.textMuted)
            }
        }
        .navigationTitle("saved on device")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
        .onChange(of: shareIngress.shareQueueEpoch) { _, _ in reload() }
    }

    @ViewBuilder
    private func content(_ q: QueuedReelIngest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let path = ShareQueueStore.thumbnailFileURL(for: q),
                   let ui = UIImage(contentsOfFile: path.path) {
                    Image(uiImage: ui)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(RoamColors.logan.opacity(0.12))
                        .frame(height: 120)
                        .overlay {
                            Text("no preview yet")
                                .font(RoamFont.mono(10))
                                .foregroundStyle(RoamColors.textMuted)
                        }
                }

                Text(q.displayTitle)
                    .font(RoamFont.mono(12, weight: .medium))
                    .foregroundStyle(RoamColors.loganDark)

                Text(q.reelUrl)
                    .font(RoamFont.mono(9))
                    .foregroundStyle(RoamColors.textMuted)
                    .textSelection(.enabled)

                if let d = q.ogDescription, !d.isEmpty {
                    Text(d)
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.loganDark)
                }

                statusRow(q)

                if q.uploadStatus == .failed, let err = q.lastUploadError, !err.isEmpty {
                    Text(err)
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.error)
                }

                if q.uploadStatus == .failed {
                    Button {
                        ShareQueueStore.resetToPending(id: q.id)
                        reload()
                        Task { await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores) }
                    } label: {
                        Text("retry upload")
                            .font(RoamFont.mono(11, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RoamColors.loganDeep)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func statusRow(_ q: QueuedReelIngest) -> some View {
        let label: String = {
            switch q.uploadStatus {
            case .pendingUpload: return "on device — will upload when you open Roam signed in"
            case .uploading: return "uploading…"
            case .failed: return "upload failed"
            }
        }()
        Text(label)
            .font(RoamFont.mono(10))
            .foregroundStyle(RoamColors.textMuted)
    }

    private func reload() {
        item = ShareQueueStore.item(id: queueId)
    }
}
