import SwiftUI
import UIKit

// MARK: - Palette (matches [ThemeColors.swift](../Roam/Theme/ThemeColors.swift) / reels page)

private enum ShareExtColors {
    static let background = Color(red: 245 / 255, green: 243 / 255, blue: 250 / 255)
    static let surface = Color.white.opacity(0.96)
    static let greenDeep = Color(red: 74 / 255, green: 158 / 255, blue: 84 / 255)
    static let loganDark = Color(red: 74 / 255, green: 64 / 255, blue: 112 / 255)
    static let logan = Color(red: 171 / 255, green: 161 / 255, blue: 198 / 255)
    static let textMuted = Color(red: 168 / 255, green: 159 / 255, blue: 192 / 255)
    static let loganWash = Color(red: 171 / 255, green: 161 / 255, blue: 198 / 255).opacity(0.22)
    static let bannerTint = Color(red: 171 / 255, green: 161 / 255, blue: 198 / 255).opacity(0.12)
}

private let gridThumbAspect: CGFloat = 9.0 / 16.0

// MARK: - Ribbon (outside thumb clip so it is not cut off)

private struct ReelSavedRibbon: View {
    var body: some View {
        Text("Reel saved")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: 3,
                    bottomTrailingRadius: 14,
                    topTrailingRadius: 6,
                    style: .continuous
                )
                .fill(ShareExtColors.greenDeep.opacity(0.92))
            )
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
    }
}

// MARK: - Grid cells

private struct QueueHeroCell: View {
    let item: QueuedReelIngest

    var body: some View {
        ZStack {
            Color.clear
                .aspectRatio(gridThumbAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay {
                    Group {
                        if let path = ShareQueueStore.thumbnailFileURL(for: item),
                           let ui = UIImage(contentsOfFile: path.path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ShareExtColors.loganWash
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(ShareExtColors.greenDeep, lineWidth: 2)
                )
        }
        .overlay(alignment: .topLeading) {
            ReelSavedRibbon()
                .padding(.top, 10)
                .padding(.leading, 8)
        }
    }
}

private struct SnapshotCachedCell: View {
    let tile: ReelsGridPreviewTile

    var body: some View {
        Color.clear
            .aspectRatio(gridThumbAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                ZStack(alignment: .bottomLeading) {
                    Group {
                        if let url = ReelsGridPreviewSnapshot.previewThumbnailFileURL(reelIdLowercased: tile.id),
                           FileManager.default.fileExists(atPath: url.path),
                           let ui = UIImage(contentsOfFile: url.path) {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        } else {
                            ShareExtColors.loganWash
                        }
                    }
                    Text(tile.title)
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundStyle(ShareExtColors.loganDark)
                        .lineLimit(2)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .background(
                            LinearGradient(
                                colors: [.clear, ShareExtColors.surface.opacity(0.92)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct GhostReelCell: View {
    var body: some View {
        ShareExtColors.loganWash
            .aspectRatio(gridThumbAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Main confirmation (compact card; host app visible behind scrim)

struct ShareReelsConfirmationView: View {
    let queueItemId: UUID
    let onDone: () -> Void
    let onOpenRoam: () -> Void

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        let item = ShareQueueStore.item(id: queueItemId)
        let snapshotFillers = Array(ReelsGridPreviewSnapshot.loadTiles().prefix(5))

        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 36, 340)
            let cardMaxHeight = min(geo.size.height * 0.78, 560)

            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("roam")
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .foregroundStyle(ShareExtColors.loganDark)
                            Text("reels")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(ShareExtColors.textMuted)
                                .textCase(.uppercase)
                                .tracking(1.2)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Searching for Roamable ideas.")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(ShareExtColors.loganDark)
                            Text("Give us a minute.")
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(ShareExtColors.textMuted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(ShareExtColors.bannerTint)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text("Upload and scanning finish when you open Roam.")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(ShareExtColors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)

                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            if let item {
                                QueueHeroCell(item: item)
                            } else {
                                GhostReelCell()
                            }

                            ForEach(0..<5, id: \.self) { idx in
                                if idx < snapshotFillers.count {
                                    SnapshotCachedCell(tile: snapshotFillers[idx])
                                } else {
                                    GhostReelCell()
                                }
                            }
                        }

                        Button(action: onDone) {
                            Text("Done")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(ShareExtColors.loganDark)
                                .foregroundStyle(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button(action: onOpenRoam) {
                            Text("Open Roam")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(ShareExtColors.greenDeep)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .frame(width: cardWidth)
                    .background(ShareExtColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(ShareExtColors.logan.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, geo.safeAreaInsets.top + 8)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 12)
                }
                .frame(maxHeight: cardMaxHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

// MARK: - No link

struct ShareExtensionNoLinkView: View {
    let onDone: () -> Void

    var body: some View {
        GeometryReader { geo in
            let cardWidth = min(geo.size.width - 40, 320)

            ZStack {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()

                VStack(spacing: 14) {
                    Text("roam")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(ShareExtColors.loganDark)

                    Text("Couldn’t read a link")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(ShareExtColors.loganDark)
                        .multilineTextAlignment(.center)
                    Text("Share a reel URL from Instagram, then try again.")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(ShareExtColors.textMuted)
                        .multilineTextAlignment(.center)

                    Button(action: onDone) {
                        Text("Done")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(ShareExtColors.loganDark)
                            .foregroundStyle(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .frame(width: cardWidth)
                .background(ShareExtColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(ShareExtColors.logan.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, geo.safeAreaInsets.top + 24)
            }
        }
    }
}
