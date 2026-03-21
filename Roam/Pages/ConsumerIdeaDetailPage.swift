import SwiftUI
import UIKit

/// Main Roam: idea detail screen aligned with the consumer HTML mock (hero, tags, added-by, actions).
struct ConsumerIdeaDetailPage: View {
    let route: ConsumerIdeaDetailRoute

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.roamStores) private var stores
    @Environment(\.apiClient) private var apiClient

    @State private var idea: Idea?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var isWorking = false
    @State private var showAttachCollections = false
    @State private var attachSelection: Set<UUID> = []
    @State private var heroPlaceImage: UIImage?

    var body: some View {
        Group {
            if let idea {
                detailContent(idea: idea)
            } else if isLoading {
                ProgressView("Loading…")
                    .tint(RoamColors.reviewAccent)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else if let errorText {
                Text(errorText)
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.error)
                    .padding()
            }
        }
        .background(RoamColors.background)
        .navigationTitle("idea")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAttachCollections) {
            attachCollectionsSheet
        }
        .task {
            await load()
            await pollWhileReelSuggesting()
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private func detailContent(idea: Idea) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                heroCard(idea: idea)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                sectionTitle("Added by")
                addedBySection(idea: idea)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                sectionTitle("In collections")
                collectionsSection
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                if shouldShowDescriptionSection(idea: idea) {
                    sectionTitle("Description")
                    Text(idea.notes)
                        .font(.system(size: 13))
                        .foregroundStyle(RoamColors.textMuted)
                        .italic()
                        .lineSpacing(4)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoamColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(RoamColors.reviewBorder, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                }

                actionButtons(idea: idea)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
            }
            .padding(.top, 8)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(RoamFont.mono(11, weight: .semibold))
            .foregroundStyle(RoamColors.textMuted)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
    }

    private func heroCard(idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                IdeaHeroPhotoStrip(
                    image: $heroPlaceImage,
                    loadKey: heroPhotoLoadKey(for: idea),
                    googlePlaceId: idea.googlePlaceId,
                    searchQuery: photoSearchQuery(for: idea),
                    latitude: idea.placeLatitude,
                    longitude: idea.placeLongitude
                )

                if let sourcePill = reelSourcePillText(idea: idea) {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.94, green: 0.58, blue: 0.20),
                                        Color(red: 0.74, green: 0.14, blue: 0.53)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 14, height: 14)
                        Text(sourcePill)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.white.opacity(0.88))
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(headline(for: idea))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(RoamColors.text)
                    .padding(.bottom, 6)

                addressRow(idea: idea)
                    .padding(.bottom, 10)

                FlowTagRow(tags: detailTags(for: idea))
                    .padding(.bottom, 12)

                Text(bodyCopy(for: idea))
                    .font(.system(size: 14))
                    .foregroundStyle(RoamColors.text)
                    .lineSpacing(4)
            }
            .padding(16)
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private func addressRow(idea: Idea) -> some View {
        let line = addressLine(for: idea)
        return Group {
            if !line.isEmpty {
                Label {
                    Text(line)
                        .font(.system(size: 13))
                        .foregroundStyle(RoamColors.textMuted)
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }

    private func addedBySection(idea: Idea) -> some View {
        let (name, initial, color) = addedByPresentation(idea: idea)
        let subtitle = addedBySubtitle(idea: idea)

        return HStack(spacing: 10) {
            Text(initial)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(color)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.horizontal, 2)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private var collectionsSection: some View {
        HStack(spacing: 6) {
            if let pid = stores.mapCollections.personalDefaultId,
               let personal = stores.mapCollections.collections.first(where: { $0.id == pid }) {
                collectionChip(
                    dot: RoamColors.reviewSuccess,
                    title: personal.name
                )
            }

            Button {
                attachSelection = []
                showAttachCollections = true
            } label: {
                HStack(spacing: 5) {
                    Text("+")
                        .font(.system(size: 13, weight: .medium))
                    Text("Add")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(RoamColors.reviewAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            RoamColors.reviewAccent.opacity(0.45),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
    }

    private func collectionChip(dot: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(RoamColors.text)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private var attachCollectionsSheet: some View {
        NavigationStack {
            List {
                ForEach(stores.mapCollections.sharedCollections) { c in
                    Button {
                        if attachSelection.contains(c.id) {
                            attachSelection.remove(c.id)
                        } else {
                            attachSelection.insert(c.id)
                        }
                    } label: {
                        HStack {
                            Text(c.name)
                                .foregroundStyle(RoamColors.text)
                            Spacer()
                            if attachSelection.contains(c.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(RoamColors.reviewAccent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAttachCollections = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await saveAttachSelections() }
                    }
                    .disabled(attachSelection.isEmpty || isWorking)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func actionButtons(idea: Idea) -> some View {
        let shareURL = googleMapsShareURL(for: idea)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    openInMaps(idea: idea)
                } label: {
                    Label("Open in Maps", systemImage: "paperplane.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(RoamColors.reviewAccent)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: RoamColors.reviewAccent.opacity(0.28), radius: 8, y: 2)

                if let shareURL {
                    ShareLink(
                        item: shareURL,
                        subject: Text(headline(for: idea)),
                        message: Text(shareMessageLine(for: idea))
                    ) {
                        Label("Share", systemImage: "link")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(RoamColors.text)
                    .background(RoamColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
                    )
                }
            }

            Button(role: .destructive) {
                Task { await deleteIdea() }
            } label: {
                Text("Delete idea")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .disabled(isWorking)
        }
    }

    // MARK: - Data

    private func headline(for idea: Idea) -> String {
        if let d = idea.displayName, !d.isEmpty { return d }
        return idea.title
    }

    private func photoSearchQuery(for idea: Idea) -> String {
        let title = headline(for: idea)
        let addr = addressLine(for: idea)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = addr.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return t }
        return "\(t) \(a)"
    }

    private func heroPhotoLoadKey(for idea: Idea) -> String {
        let lat = idea.placeLatitude.map { String($0) } ?? ""
        let lng = idea.placeLongitude.map { String($0) } ?? ""
        let gid = idea.googlePlaceId ?? ""
        return "\(idea.id)|\(gid)|\(lat)|\(lng)|\(photoSearchQuery(for: idea))"
    }

    private func bodyCopy(for idea: Idea) -> String {
        let notes = idea.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let refined = idea.pipelineResult?.refinedTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !refined.isEmpty {
            return refined
        }
        if !notes.isEmpty { return notes }
        return idea.title
    }

    private func shouldShowDescriptionSection(idea: Idea) -> Bool {
        let notes = idea.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notes.isEmpty else { return false }
        let body = bodyCopy(for: idea)
        return notes.caseInsensitiveCompare(body) != .orderedSame
    }

    private func addressLine(for idea: Idea) -> String {
        let hint = route.addressHint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hint.isEmpty { return hint }
        return (idea.placeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func detailTags(for idea: Idea) -> [(String, Bool)] {
        var out: [(String, Bool)] = []
        let cat = (idea.pipelineResult?.category ?? route.categorySnapshot ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !cat.isEmpty {
            out.append((cat.lowercased(), false))
        }
        if idea.savedReelId != nil {
            out.append(("from reel", true))
        }
        return out
    }

    private func reelSourcePillText(idea: Idea) -> String? {
        guard idea.savedReelId != nil else { return nil }
        if let handle = instagramHandle(from: idea.sourceUrl) {
            return "from @\(handle)"
        }
        if !idea.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "from reel"
        }
        return nil
    }

    private func instagramHandle(from urlString: String) -> String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let host = url.host?.lowercased(), host.contains("instagram.com") {
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let first = path.split(separator: "/").first.map(String.init) ?? ""
            let handle = first.replacingOccurrences(of: "@", with: "")
            if !handle.isEmpty, handle != "p", handle != "reel", handle != "stories" { return handle }
        }
        if let range = trimmed.range(of: #"@([A-Za-z0-9._]+)"#, options: .regularExpression) {
            let match = String(trimmed[range])
            return match.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        }
        return nil
    }

    private func addedByPresentation(idea: Idea) -> (name: String, initial: String, color: Color) {
        let userStore = stores.user
        let meUser = userStore.me
        let meId = meUser?.id.lowercased()
        let owner = idea.userId.lowercased()
        if let meId, owner == meId {
            let dn = meUser?.displayName ?? "You"
            let initial = dn.prefix(1).uppercased()
            return ("You", String(initial), RoamColors.reviewSuccess)
        }
        let label = route.addedByDisplayName ?? "Someone"
        let initial = label.prefix(1).uppercased()
        let idx = route.addedByColorIndex ?? 0
        return (label, String(initial), MapPinPalette.color(forIndex: idx))
    }

    private func addedBySubtitle(idea: Idea) -> String? {
        var parts: [String] = []
        let formatted = idea.createdAt.formatted(date: .abbreviated, time: .omitted)
        parts.append(formatted)
        if idea.savedReelId != nil {
            if let h = instagramHandle(from: idea.sourceUrl) {
                parts.append("from reel by @\(h)")
            } else {
                parts.append("from reel")
            }
        }
        return parts.joined(separator: " · ")
    }

    /// Google Maps deep link so recipients open (or can open) the place in Maps.
    private func googleMapsShareURL(for idea: Idea) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/search/")
        let queryValue: String
        if let lat = idea.placeLatitude, let lng = idea.placeLongitude {
            queryValue = "\(lat),\(lng)"
        } else {
            let title = headline(for: idea).trimmingCharacters(in: .whitespacesAndNewlines)
            let place = addressLine(for: idea).trimmingCharacters(in: .whitespacesAndNewlines)
            if !place.isEmpty, !title.isEmpty {
                queryValue = "\(title) \(place)"
            } else if !place.isEmpty {
                queryValue = place
            } else if !title.isEmpty {
                queryValue = title
            } else {
                return nil
            }
        }
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: queryValue)
        ]
        return components?.url
    }

    private func shareMessageLine(for idea: Idea) -> String {
        let place = addressLine(for: idea)
        if place.isEmpty { return headline(for: idea) }
        return place
    }

    private func openInMaps(idea: Idea) {
        let name = headline(for: idea).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let lat = idea.placeLatitude, let lng = idea.placeLongitude {
            let url = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(name)")
            if let url { openURL(url) }
            return
        }
        let q = addressLine(for: idea).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
        if let url = URL(string: "https://maps.apple.com/?q=\(q)") {
            openURL(url)
        }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let loaded = try await apiClient.getIdea(id: route.ideaId)
            idea = loaded
            stores.ideas.replaceLocal(loaded)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func pollWhileReelSuggesting() async {
        guard let start = idea, start.status == .suggesting, start.pipelineResult == nil else { return }
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let reloaded = try? await apiClient.getIdea(id: route.ideaId) else { continue }
            idea = reloaded
            stores.ideas.replaceLocal(reloaded)
            if reloaded.pipelineResult != nil || reloaded.status != .suggesting {
                break
            }
        }
    }

    private func deleteIdea() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await stores.ideas.deleteIdea(id: route.ideaId)
            await stores.mapCollections.refreshPins()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func saveAttachSelections() async {
        guard let ideaUUID = UUID(uuidString: route.ideaId) else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await apiClient.attachIdeaSharedCollections(
                ideaId: ideaUUID,
                sharedCollectionIds: Array(attachSelection)
            )
            await stores.mapCollections.refreshPins()
            showAttachCollections = false
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Hero (Google Places photo)

private struct IdeaHeroPhotoStrip: View {
    @Binding var image: UIImage?
    let loadKey: String
    let googlePlaceId: String?
    let searchQuery: String
    let latitude: Double?
    let longitude: Double?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.83, green: 0.78, blue: 0.66),
                        Color(red: 0.72, green: 0.66, blue: 0.53)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .font(.system(size: 28))
                            .foregroundStyle(.black.opacity(0.22))
                        Text("Photo from Google Maps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.black.opacity(0.25))
                    }
                }
            }
        }
        .frame(height: 160)
        .clipped()
        .task(id: loadKey) {
            image = nil
            let gid = googlePlaceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gid.isEmpty || !trimmed.isEmpty else { return }
            let loaded = await GooglePlacePhotoService.fetchPlaceHeroUIImage(
                googlePlaceId: gid.isEmpty ? nil : gid,
                searchQuery: trimmed,
                latitude: latitude,
                longitude: longitude
            )
            await MainActor.run {
                image = loaded
            }
        }
    }
}

// MARK: - Tag flow layout

private struct FlowTagRow: View {
    let tags: [(String, Bool)]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                Text(tag.0)
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(tag.1 ? RoamColors.reviewAccent : RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tag.1 ? RoamColors.reviewAccentLight : RoamColors.reviewSurfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(
                                tag.1 ? RoamColors.reviewAccent.opacity(0.22) : RoamColors.reviewBorder.opacity(0.6),
                                lineWidth: 1
                            )
                    )
            }
        }
    }
}

/// Simple wrapping horizontal flow for tags.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var rowW: CGFloat = 0
        var totalH: CGFloat = 0
        var lineMaxH: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if rowW + size.width > maxW, rowW > 0 {
                totalH += lineMaxH + spacing
                rowW = 0
                lineMaxH = 0
            }
            rowW += size.width + (rowW > 0 ? spacing : 0)
            lineMaxH = max(lineMaxH, size.height)
        }
        totalH += lineMaxH
        return CGSize(width: maxW, height: totalH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineH: CGFloat = 0

        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineH + spacing
                lineH = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}
