import SwiftUI

/// Main Roam (`mainRoam`): ideas list matching the consumer HTML concept — collection chips, reels review banner, map-pin rows.
struct ConsumerIdeasHomePage: View {
    @Environment(\.roamStores) private var stores

    /// Switch main tab to Reels (review queue).
    var onSwitchToReels: (() -> Void)?

    init(onSwitchToReels: (() -> Void)? = nil) {
        self.onSwitchToReels = onSwitchToReels
    }

    private var mc: MapCollectionsQueryStore { stores.mapCollections }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                collectionChipBar
                    .padding(.bottom, 4)

                if stores.reels.needsReviewCount > 0, let go = onSwitchToReels {
                    reviewBanner(onTap: go)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }

                if mc.isLoadingPins && mc.mapPins.isEmpty {
                    ProgressView("loading ideas…")
                        .font(RoamFont.mono(11))
                        .tint(RoamColors.reviewAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let err = mc.lastError, mc.mapPins.isEmpty {
                    Text(err)
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Button("Retry") {
                        Task { await mc.refreshPins() }
                    }
                    .font(RoamFont.mono(11, weight: .medium))
                    .foregroundStyle(RoamColors.reviewAccent)
                } else if mc.mapPins.isEmpty {
                    if mc.selection == .everything {
                        ConsumerIdeasReelOnboardingEmptyState()
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    } else {
                        RoamEmptyState(
                            icon: "◌",
                            title: "nothing here yet",
                            subtitle: "try Everything or save places from reels"
                        )
                        .padding(.top, 24)
                    }
                }

                LazyVStack(spacing: 10) {
                    ForEach(mc.mapPins) { pin in
                        NavigationLink(value: ConsumerIdeaDetailRoute.from(pin: pin)) {
                            ConsumerIdeaRow(
                                pin: pin,
                                selection: mc.selection,
                                personalName: personalName,
                                sharedCollectionTitle: sharedCollectionTitle(selection: mc.selection)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
            .padding(.top, 8)
        }
        .background(RoamColors.background)
        .navigationTitle("Ideas")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
            await stores.reels.refreshSummaryOnly()
        }
        .task {
            await stores.mapCollections.loadCollectionsIfStale()
            await stores.mapCollections.refreshPins()
            await stores.reels.refreshSummaryOnly()
        }
    }

    private var personalName: String {
        mc.collections.first { $0.isPersonalDefault }?.name ?? "My saves"
    }

    private func sharedCollectionTitle(selection: MapCollectionsQueryStore.ChipSelection) -> String? {
        if case .sharedCollection(let id) = selection {
            return mc.sharedCollections.first { $0.id == id }?.name
        }
        return nil
    }

    // MARK: - Chips

    private var collectionChipBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                consumerChip(
                    title: "Everything",
                    selected: mc.selection == .everything,
                    count: mc.selection == .everything ? mc.mapPins.count : nil,
                    dots: { EmptyView() }
                ) {
                    Task { await mc.setSelection(.everything) }
                }

                consumerChip(
                    title: personalName,
                    selected: mc.selection == .mySaves,
                    count: mc.selection == .mySaves ? mc.mapPins.count : nil,
                    dots: { Circle().fill(RoamColors.reviewSuccess).frame(width: 6, height: 6) }
                ) {
                    Task { await mc.setSelection(.mySaves) }
                }

                ForEach(mc.sharedCollections) { c in
                    consumerChip(
                        title: c.name,
                        selected: mc.selection == .sharedCollection(c.id),
                        count: mc.selection == .sharedCollection(c.id) ? mc.mapPins.count : nil,
                        dots: { memberDotsView(for: c) }
                    ) {
                        Task { await mc.setSelection(.sharedCollection(c.id)) }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 4)
        }
    }

    private func consumerChip<Dots: View>(
        title: String,
        selected: Bool,
        count: Int?,
        @ViewBuilder dots: () -> Dots,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                dots()
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let count {
                    Text("\(count)")
                        .font(RoamFont.mono(10, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.7) : RoamColors.textMuted)
                }
            }
            .foregroundStyle(selected ? Color.white : RoamColors.textMuted)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(selected ? RoamColors.reviewAccent : RoamColors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(selected ? RoamColors.reviewAccent : RoamColors.reviewBorder, lineWidth: selected ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(selected ? 0.12 : 0.05), radius: selected ? 8 : 3, y: selected ? 2 : 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func memberDotsView(for c: APIClient.CollectionReadDTO) -> some View {
        let previews = Array((c.memberPreview ?? []).prefix(3))
        if previews.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 2) {
                ForEach(Array(previews.enumerated()), id: \.offset) { _, m in
                    Circle()
                        .fill(MapPinPalette.color(forIndex: abs(m.userId.hashValue % 8)))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    // MARK: - Review banner

    private func reviewBanner(onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(RoamColors.reviewAccent)
                        .frame(width: 32, height: 32)
                    Image(systemName: "film.stack")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stores.reels.needsReviewCount) reels to review")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoamColors.text)
                    Text("Tap to turn suggestions into ideas")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                }
                Spacer(minLength: 0)
                Text("›")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RoamColors.reviewAccent)
            }
            .padding(12)
            .background(RoamColors.reviewAccentLight)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(RoamColors.reviewAccent.opacity(0.2), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state (Everything, zero places)

/// Matches consumer HTML: reel → Roam → map onboarding when there are no ideas yet.
private struct ConsumerIdeasReelOnboardingEmptyState: View {
    var body: some View {
        VStack(spacing: 0) {
            reelToMapIllustration
                .padding(.bottom, 28)

            Text("Save a reel, get places")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(RoamColors.text)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)

            Text("Share a reel from Instagram or TikTok and Roam turns it into places you can actually find later.")
                .font(.system(size: 14))
                .foregroundStyle(RoamColors.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 16)
                .padding(.bottom, 28)

            VStack(spacing: 12) {
                onboardingStep(number: "1", text: "Find a reel with a place you like")
                onboardingStep(number: "2") {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Tap ")
                        Text("Share")
                            .fontWeight(.semibold)
                        Text(" and choose ")
                        Text("Roam")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(RoamColors.text)
                }
                onboardingStep(number: "3", text: "Places appear here and on your map")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var reelToMapIllustration: some View {
        ZStack {
            // Phone + reel preview (center, nudged left)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RoamColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(RoamColors.reviewBorder, lineWidth: 2.5)
                    )
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.94, green: 0.58, blue: 0.20),
                                    Color(red: 0.90, green: 0.41, blue: 0.24),
                                    Color(red: 0.86, green: 0.15, blue: 0.26),
                                    Color(red: 0.80, green: 0.14, blue: 0.40)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .opacity(0.15)
                        )
                        .frame(height: 90)
                        .overlay {
                            ZStack {
                                Circle()
                                    .fill(Color.white.opacity(0.6))
                                    .frame(width: 20, height: 20)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.black.opacity(0.35))
                                    .offset(x: 1)
                            }
                        }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            .frame(width: 80, height: 140)
            .offset(x: -18)

            // Arrow (share flow) — right of phone, vertical toward Roam
            VStack(spacing: 0) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RoamColors.reviewAccent.opacity(0.45))
                    .rotationEffect(.degrees(90))
                Rectangle()
                    .fill(RoamColors.reviewAccent.opacity(0.4))
                    .frame(width: 2, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
            .offset(x: 38, y: -8)

            // Roam target tile
            Text("roam")
                .font(RoamFont.mono(8, weight: .bold))
                .foregroundStyle(.white)
                .tracking(-0.3)
                .frame(width: 36, height: 36)
                .background(RoamColors.reviewAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: RoamColors.reviewAccent.opacity(0.35), radius: 8, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.trailing, 4)
                .padding(.top, 8)

            // Map pin
            VStack(spacing: 2) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, RoamColors.reviewSuccess)
                Text("On your map")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(RoamColors.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 4)
            .padding(.bottom, 4)
        }
        .frame(width: 200, height: 180)
        .frame(maxWidth: .infinity)
    }

    private func onboardingStep(number: String, text: String) -> some View {
        onboardingStep(number: number) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(RoamColors.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func onboardingStep(number: String, @ViewBuilder text: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(number)
                .font(RoamFont.mono(12, weight: .bold))
                .foregroundStyle(RoamColors.reviewAccent)
                .frame(width: 28, height: 28)
                .background(RoamColors.reviewAccentLight)
                .clipShape(Circle())

            text()
                .frame(maxWidth: .infinity, alignment: .leading)
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
}

// MARK: - Row

private struct ConsumerIdeaRow: View {
    let pin: APIClient.CollectionMapPinDTO
    let selection: MapCollectionsQueryStore.ChipSelection
    let personalName: String
    let sharedCollectionTitle: String?

    private var categoryLabel: String {
        let raw = (pin.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "idea" }
        return raw.lowercased()
    }

    private var addressLine: String {
        let a = (pin.placeAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { return a }
        return (pin.placeName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var desc: String {
        let n = pin.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !n.isEmpty { return n }
        return pin.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(pin.pinTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RoamColors.text)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Text(categoryLabel)
                    .font(RoamFont.mono(9, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoamColors.reviewSurfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .padding(.bottom, 6)

            Text(desc)
                .font(.system(size: 13))
                .foregroundStyle(RoamColors.textMuted)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 8)

            HStack(alignment: .center) {
                if !addressLine.isEmpty {
                    Label {
                        Text(addressLine)
                            .font(.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                    .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    Circle()
                        .fill(MapPinPalette.color(forIndex: pin.colorIndex))
                        .frame(width: 6, height: 6)
                    Text(addedByShortLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(RoamColors.textMuted)
                }
            }

            filterContextPills
        }
        .padding(14)
        .padding(.horizontal, 2)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private var addedByShortLabel: String {
        let name = pin.addedByDisplayName
        if name == "Someone" { return name }
        let parts = name.split(separator: " ")
        if let first = parts.first {
            return String(first)
        }
        return name
    }

    @ViewBuilder
    private var filterContextPills: some View {
        switch selection {
        case .everything:
            EmptyView()
        case .mySaves:
            pillRow {
                collectionPill(dot: RoamColors.reviewSuccess, title: personalName)
            }
        case .sharedCollection:
            if let name = sharedCollectionTitle, !name.isEmpty {
                pillRow {
                    collectionPill(dot: RoamColors.reviewPartnerPink, title: name)
                }
            } else {
                EmptyView()
            }
        }
    }

    private func pillRow(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) {
            content()
        }
        .padding(.top, 8)
    }

    private func collectionPill(dot: Color, title: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(dot)
                .frame(width: 4, height: 4)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(RoamColors.textMuted)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(RoamColors.reviewSurfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Navigation value for consumer idea detail.
struct ConsumerIdeaDetailRoute: Hashable {
    let ideaId: String
    var addressHint: String?
    var addedByDisplayName: String?
    var addedByColorIndex: Int?
    var categorySnapshot: String?

    static func from(pin: APIClient.CollectionMapPinDTO) -> ConsumerIdeaDetailRoute {
        ConsumerIdeaDetailRoute(
            ideaId: pin.id.uuidString.lowercased(),
            addressHint: pin.placeAddress ?? pin.placeName,
            addedByDisplayName: pin.addedByDisplayName,
            addedByColorIndex: pin.colorIndex,
            categorySnapshot: pin.category
        )
    }
}
