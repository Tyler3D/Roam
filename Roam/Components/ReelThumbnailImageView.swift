import SwiftUI

/// Disk-backed thumbnail first (instant after share), then signed URL fetch with write-through cache.
struct ReelThumbnailImageView: View {
    let reelId: UUID
    let signedUrl: String?
    var contentMode: ContentMode = .fill

    @State private var uiImage: UIImage?

    private var placeholder: some View {
        RoamColors.logan.opacity(0.12)
    }

    private var remoteURL: URL? {
        guard let s = signedUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let u = URL(string: s) { return u }
        return URLComponents(string: s)?.url
    }

    var body: some View {
        ZStack {
            placeholder
            if let ui = uiImage {
                Image(uiImage: ui)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .task(id: taskKey) {
            await resolveImage()
        }
    }

    /// Signed URLs rotate; refetch when URL string changes.
    private var taskKey: String {
        "\(reelId.uuidString.lowercased())|\(signedUrl ?? "")"
    }

    @MainActor
    private func resolveImage() async {
        if let data = ReelThumbnailDiskCache.load(reelId: reelId), let ui = UIImage(data: data) {
            uiImage = ui
            return
        }
        uiImage = nil
        guard let url = remoteURL else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let ui = UIImage(data: data) else { return }
            uiImage = ui
            if let jpeg = ui.jpegData(compressionQuality: 0.85) {
                try? ReelThumbnailDiskCache.save(reelId: reelId, jpegData: jpeg)
            }
        } catch {
            uiImage = nil
        }
    }
}
