import SwiftUI
import UIKit

struct ReelDetailPage: View {
    let reelId: String

    private static let maxIngestRetries = 5

    @Environment(\.apiClient) private var apiClient
    @Environment(\.roamStores) private var stores
    @EnvironmentObject private var shareIngress: ShareIngressCoordinator
    @State private var detail: APIClient.SavedReelDetailDTO?
    @State private var loadError: String?
    @State private var titleEdits: [UUID: String] = [:]
    @State private var locationQueries: [UUID: String] = [:]
    @State private var selectedCandidateIds: Set<UUID> = []
    @State private var selectedSharedCollectionIds: Set<UUID> = []
    @State private var collections: [APIClient.CollectionReadDTO] = []
    @State private var isPromoting = false
    @State private var promoteError: String?
    @State private var showPromoteSuccess = false
    @State private var showOriginalSuggestions = false
    @State private var showAddIdea = false
    @State private var showNewCollectionSheet = false
    @State private var isRetryingIngest = false
    @State private var retryIngestError: String?
    @State private var loadedAutoSavedIdea: Idea?
    @State private var isAttachingShared = false
    @State private var attachSharedError: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let detail {
                content(detail)
            } else if let loadError {
                Text(loadError)
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.error)
            } else {
                ProgressView("loading…")
                    .font(RoamFont.mono(11))
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let d = detail, isAutoSavedSingle(d), let first = d.ideasNonEmpty.first {
                    NavigationLink {
                        IdeaDetailPage(ideaId: first.id.uuidString)
                    } label: {
                        Text("edit")
                            .font(RoamFont.mono(10, weight: .semibold))
                            .foregroundStyle(RoamColors.reviewAccent)
                    }
                } else {
                    Button("add idea") { showAddIdea = true }
                        .font(RoamFont.mono(10, weight: .medium))
                        .disabled(detail == nil || detail?.status == "processing")
                }
            }
        }
        .sheet(isPresented: $showAddIdea) {
            if detail != nil {
                AddReelIdeaSheet(reelId: reelId) {
                    showAddIdea = false
                    Task {
                        await stores.ideas.refresh()
                        await load()
                    }
                }
            }
        }
        .sheet(isPresented: $showNewCollectionSheet) {
            NewSharedCollectionSheet(apiClient: apiClient) { newId in
                selectedSharedCollectionIds.insert(newId)
                showNewCollectionSheet = false
                Task { await reloadCollectionsOnly() }
            }
        }
        .task { await load() }
    }

    private var navigationTitleText: String {
        guard let d = detail else { return "review reel" }
        return isAutoSavedSingle(d) ? "saved" : "review reel"
    }

    private var isIngestScanningThisReel: Bool {
        guard let rid = shareIngress.ingestScanState?.reelId, !rid.isEmpty else { return false }
        return rid == reelId.lowercased()
    }

    @ViewBuilder
    private func content(_ d: APIClient.SavedReelDetailDTO) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if isIngestScanningThisReel {
                        reelIngestSearchingBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                    }

                    if d.jobStatus == "failed" || d.status == "failed" {
                        failedBlock(d)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }

                    if isAutoSavedSingle(d) {
                        autoSavedReviewContent(d)
                    } else if usesMultiStyleReview(d) {
                        multiPlaceReviewScroll(d)
                    } else {
                        legacyReelDetailContent(d)
                    }
                }
                .padding(.bottom, usesMultiStyleReview(d) ? 130 : 8)
            }
            .background(RoamColors.background)

            if usesMultiStyleReview(d) {
                VStack(spacing: 6) {
                    if let promoteError {
                        Text(promoteError)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Button {
                        Task { await promote(d) }
                    } label: {
                        Group {
                            if isPromoting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(primarySaveButtonTitle(d))
                                    .font(Font.system(size: 15, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            selectedPending(d).isEmpty || isPromoting
                                ? RoamColors.reviewBorder
                                : RoamColors.reviewAccent
                        )
                        .foregroundStyle(
                            selectedPending(d).isEmpty || isPromoting
                                ? RoamColors.textMuted
                                : Color.white
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(isPromoting || selectedPending(d).isEmpty)
                    .padding(.horizontal, 20)

                    VStack(spacing: 4) {
                        Text(
                            "Always saved to \(collections.first { $0.isPersonalDefault }?.name ?? "My saves")."
                        )
                        .font(RoamFont.mono(9))
                        .foregroundStyle(RoamColors.textMuted)
                        .multilineTextAlignment(.center)
                        Text("Places appear in your ideas and on the map")
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 10)
                }
                .frame(maxWidth: .infinity)
                .background(RoamColors.background)
            }
        }
        .overlay(alignment: .top) {
            if showPromoteSuccess {
                Text("saved to your collections")
                    .font(RoamFont.mono(10, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoamColors.greenTint)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Review layout modes

    private func isAutoSavedSingle(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        d.status == "promoted"
            && d.ideasNonEmpty.count == 1
            && pendingCandidates(d).isEmpty
            && d.jobStatus != "failed"
            && d.status != "failed"
    }

    private func usesMultiStyleReview(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        canPromotePending(d) && !pendingCandidates(d).isEmpty
    }

    private func promotedCandidateForIdea(_ d: APIClient.SavedReelDetailDTO, ideaId: UUID) -> APIClient.ReelCandidateDetailDTO? {
        d.candidates.first { $0.promotedIdeaId == ideaId }
    }

    @ViewBuilder
    private func legacyReelDetailContent(_ d: APIClient.SavedReelDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let rid = UUID(uuidString: reelId) {
                ReelThumbnailImageView(reelId: rid, signedUrl: d.thumbnailSignedUrl, contentMode: .fit)
                    .frame(minHeight: 120)
                    .frame(maxHeight: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            Text(d.title.isEmpty ? d.reelUrl : d.title)
                .font(RoamFont.mono(12, weight: .medium))
                .foregroundStyle(RoamColors.loganDark)
                .padding(.horizontal, 16)

            if d.status == "needs_review", d.ideasNonEmpty.isEmpty, pendingCandidates(d).isEmpty {
                Text("Nothing matched—tap add idea to create one yourself.")
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.textMuted)
                    .padding(.horizontal, 16)
            }

            ideasSection(d)
                .padding(.horizontal, 16)

            if !d.candidates.isEmpty, pendingCandidates(d).isEmpty || !canPromotePending(d) {
                DisclosureGroup(isExpanded: $showOriginalSuggestions) {
                    candidatesSection(d, readOnly: true)
                } label: {
                    Text("all suggestions")
                        .font(RoamFont.mono(10, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func multiPlaceReviewScroll(_ d: APIClient.SavedReelDetailDTO) -> some View {
        let ordered = pendingCandidates(d).sorted { $0.sortIndex < $1.sortIndex }
        VStack(alignment: .leading, spacing: 0) {
            reelPreviewCard(d, showCaption: true)
                .padding(.horizontal, 20)
                .padding(.top, 8)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(ordered.count) place\(ordered.count == 1 ? "" : "s") found")
                        .font(Font.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoamColors.text)
                    Text("Select which to save")
                        .font(Font.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                }
                Spacer()
                if ordered.count >= 2 {
                    Button("Select all") {
                        selectedCandidateIds = Set(ordered.map(\.id))
                    }
                    .font(Font.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            reviewSaveToBar(d)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            ForEach(Array(ordered.enumerated()), id: \.element.id) { idx, c in
                multiPlaceCandidateCard(d, c, rank: idx + 1)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

            Button {
                dismiss()
            } label: {
                Text("Skip this reel →")
                    .font(Font.system(size: 12))
                    .foregroundStyle(RoamColors.textMuted)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func reelPreviewCard(_ d: APIClient.SavedReelDetailDTO, showCaption: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let rid = UUID(uuidString: reelId) {
                    ReelThumbnailImageView(reelId: rid, signedUrl: d.thumbnailSignedUrl, contentMode: .fill)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.18, green: 0.12, blue: 0.28), Color(red: 0.1, green: 0.08, blue: 0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 140)
                }

                LinearGradient(
                    colors: [.black.opacity(0.45), .clear, .black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 140)

                Button {
                    if let url = URL(string: d.reelUrl) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 44, height: 44)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .offset(x: 2)
                        }
                }
                .buttonStyle(.plain)

                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.94, green: 0.58, blue: 0.2),
                                        Color(red: 0.86, green: 0.2, blue: 0.45),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 16, height: 16)
                        Text(d.title.isEmpty ? d.reelUrl : d.title)
                            .font(Font.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            if showCaption {
                let caption = d.candidates.sorted { $0.sortIndex < $1.sortIndex }.first?.cardDescription ?? ""
                if !caption.isEmpty {
                    Text(caption)
                        .font(Font.system(size: 12))
                        .foregroundStyle(RoamColors.textMuted)
                        .lineLimit(3)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
    }

    private func reviewSaveToBar(_: APIClient.SavedReelDetailDTO) -> some View {
        let personalName = collections.first { $0.isPersonalDefault }?.name ?? "My saves"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Text("Also add to:")
                    .font(Font.system(size: 12))
                    .foregroundStyle(RoamColors.textMuted)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(collections.filter { !$0.isPersonalDefault }) { c in
                            let on = selectedSharedCollectionIds.contains(c.id)
                            Button {
                                if on { selectedSharedCollectionIds.remove(c.id) }
                                else { selectedSharedCollectionIds.insert(c.id) }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 14))
                                        .foregroundStyle(on ? RoamColors.reviewAccent : RoamColors.reviewBorder)
                                    collectionMemberDots(c, maxDots: 3)
                                    Text(c.name)
                                        .font(Font.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(on ? RoamColors.reviewAccentLight : Color.clear)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(on ? RoamColors.reviewAccent : RoamColors.reviewBorder, lineWidth: on ? 1.5 : 1.5))
                                .foregroundStyle(on ? RoamColors.text : RoamColors.textMuted)
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            showNewCollectionSheet = true
                        } label: {
                            Text("+ new")
                                .font(Font.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(RoamColors.surface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(RoamColors.reviewAccent, lineWidth: 1.5))
                                .foregroundStyle(RoamColors.reviewAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Every selected place is also saved to \(personalName).")
                .font(Font.system(size: 11))
                .foregroundStyle(RoamColors.textMuted)
        }
        .padding(12)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func collectionMemberDots(_ c: APIClient.CollectionReadDTO, maxDots: Int) -> some View {
        let previews = Array((c.memberPreview ?? []).prefix(maxDots))
        if previews.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 1) {
                ForEach(Array(previews.enumerated()), id: \.offset) { i, _ in
                    Circle()
                        .fill(collectionDotPalette[i % collectionDotPalette.count])
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private var collectionDotPalette: [Color] {
        [RoamColors.reviewSuccess, RoamColors.reviewPartnerPink, RoamColors.reviewSquadBlue]
    }

    /// Personal default is always linked on promote/ingest; never send or show it as a toggleable chip.
    private var personalDefaultCollectionId: UUID? {
        collections.first { $0.isPersonalDefault }?.id
    }

    private func stripPersonalFromSharedSelection() {
        guard let pid = personalDefaultCollectionId else { return }
        selectedSharedCollectionIds.remove(pid)
    }

    private func multiPlaceCandidateCard(_ d: APIClient.SavedReelDetailDTO, _ c: APIClient.ReelCandidateDetailDTO, rank: Int) -> some View {
        let checked = selectedCandidateIds.contains(c.id)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    if checked { selectedCandidateIds.remove(c.id) }
                    else { selectedCandidateIds.insert(c.id) }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(checked ? RoamColors.reviewSuccess : RoamColors.reviewBorder, lineWidth: 2)
                            .frame(width: 24, height: 24)
                        if checked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(RoamColors.reviewSuccess)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 5) {
                    TextField(
                        "title",
                        text: Binding(
                            get: {
                                if let t = titleEdits[c.id] { return t }
                                return c.previewTitle
                            },
                            set: { titleEdits[c.id] = $0 }
                        )
                    )
                    .font(Font.system(size: 15, weight: .semibold))
                    .foregroundStyle(RoamColors.text)

                    HStack(alignment: .center, spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 10))
                            .foregroundStyle(RoamColors.textMuted)
                        Text(c.cardAddressLine ?? "—")
                            .font(Font.system(size: 12))
                            .foregroundStyle(RoamColors.textMuted)
                            .lineLimit(2)
                    }

                    Text(c.cardCategory.uppercased())
                        .font(RoamFont.mono(9, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(checked ? RoamColors.reviewSuccess.opacity(0.15) : RoamColors.reviewSurfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    TextField(
                        "location (maps search)",
                        text: Binding(
                            get: {
                                if let q = locationQueries[c.id] { return q }
                                return c.resolvedPlaceName ?? c.mapsQuery ?? ""
                            },
                            set: { locationQueries[c.id] = $0 }
                        )
                    )
                    .font(RoamFont.mono(10))
                    .textFieldStyle(.roundedBorder)
                }

                Text("#\(rank)")
                    .font(RoamFont.mono(18, weight: .bold))
                    .foregroundStyle(checked ? RoamColors.reviewSuccess : RoamColors.reviewBorder)
                    .frame(width: 28)
            }
            .padding(14)
        }
        .background(checked ? RoamColors.reviewSuccessBg : RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(checked ? RoamColors.reviewSuccess : RoamColors.reviewBorder, lineWidth: checked ? 1.5 : 1.5)
        )
    }

    private func primarySaveButtonTitle(_ d: APIClient.SavedReelDetailDTO) -> String {
        let n = selectedPending(d).count
        if n == 0 { return "Select places to save" }
        let personalName = collections.first { $0.isPersonalDefault }?.name ?? "My Saves"
        let shared = collections.filter { selectedSharedCollectionIds.contains($0.id) }
        if shared.isEmpty {
            return "Save \(n) place\(n == 1 ? "" : "s") to \(personalName)"
        }
        let first = shared[0].name
        let extra = shared.count > 1 ? " +\(shared.count - 1)" : ""
        return "Save \(n) place\(n == 1 ? "" : "s") to \(first)\(extra)"
    }

    @ViewBuilder
    private func autoSavedReviewContent(_ d: APIClient.SavedReelDetailDTO) -> some View {
        if let idea = d.ideasNonEmpty.first {
            let cand = promotedCandidateForIdea(d, ideaId: idea.id)
            let blurb = (loadedAutoSavedIdea?.notes ?? cand?.cardDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(alignment: .leading, spacing: 0) {
                reelPreviewCard(d, showCaption: false)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(RoamColors.reviewSuccess)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-saved to My Saves")
                            .font(.system(size: 14, weight: .semibold))
                        Text("1 place extracted from this reel")
                            .font(.system(size: 12))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoamColors.reviewSuccessBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(RoamColors.reviewSuccess, lineWidth: 1.5)
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(idea.title)
                            .font(.system(size: 18, weight: .bold))
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10))
                                .foregroundStyle(RoamColors.textMuted)
                            Text(loadedAutoSavedIdea?.placeName ?? idea.placeName ?? "—")
                                .font(.system(size: 12))
                                .foregroundStyle(RoamColors.textMuted)
                        }
                        HStack(spacing: 6) {
                            Text((cand?.cardCategory ?? "place").uppercased())
                                .font(RoamFont.mono(9, weight: .medium))
                                .foregroundStyle(RoamColors.textMuted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(RoamColors.reviewSurfaceAlt)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text("FROM REEL")
                                .font(RoamFont.mono(9, weight: .medium))
                                .foregroundStyle(RoamColors.reviewAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(RoamColors.reviewAccentLight)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        if !blurb.isEmpty {
                            Text(blurb)
                                .font(.system(size: 12))
                                .foregroundStyle(RoamColors.textMuted)
                                .lineSpacing(3)
                        }
                    }
                    .padding(16)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Also add to a shared collection?")
                            .font(.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(collections.filter { !$0.isPersonalDefault }) { c in
                                    let on = selectedSharedCollectionIds.contains(c.id)
                                    Button {
                                        if on { selectedSharedCollectionIds.remove(c.id) }
                                        else { selectedSharedCollectionIds.insert(c.id) }
                                    } label: {
                                        HStack(spacing: 4) {
                                            collectionMemberDots(c, maxDots: 3)
                                            Text(c.name)
                                                .font(.system(size: 11, weight: on ? .semibold : .medium))
                                        }
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3)
                                        .background(on ? RoamColors.reviewAccentLight : Color.clear)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(on ? RoamColors.reviewAccent : RoamColors.reviewBorder))
                                        .foregroundStyle(on ? RoamColors.reviewAccent : RoamColors.textMuted)
                                    }
                                    .buttonStyle(.plain)
                                }
                                Button {
                                    showNewCollectionSheet = true
                                } label: {
                                    Text("+ New collection")
                                        .font(.system(size: 11, weight: .medium))
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 3)
                                        .overlay(Capsule().stroke(RoamColors.reviewBorder))
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let attachSharedError {
                            Text(attachSharedError)
                                .font(RoamFont.mono(10))
                                .foregroundStyle(RoamColors.error)
                        }

                        if !selectedSharedCollectionIds.isEmpty {
                            Button {
                                Task { await attachSharedForAutoSaved(ideaId: idea.id) }
                            } label: {
                                if isAttachingShared {
                                    ProgressView()
                                } else {
                                    Text("Add to selected collections")
                                        .font(RoamFont.mono(11, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(RoamColors.reviewAccent)
                            .disabled(isAttachingShared)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoamColors.background)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(RoamColors.reviewBorder)
                            .frame(height: 1)
                    }
                }
                .background(RoamColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(RoamColors.reviewBorder, lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.top, 16)

                HStack(spacing: 8) {
                    Button {
                        openMapsForAutoSaved(idea: idea)
                    } label: {
                        Text("Open in Maps")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoamColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        IdeaDetailPage(ideaId: idea.id.uuidString)
                    } label: {
                        Text("Plan this →")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(RoamColors.reviewAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
    }

    private func openMapsForAutoSaved(idea: APIClient.SavedReelIdeaSummaryDTO) {
        if let lat = loadedAutoSavedIdea?.placeLatitude, let lng = loadedAutoSavedIdea?.placeLongitude {
            let q = idea.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "http://maps.apple.com/?ll=\(lat),\(lng)&q=\(q)") {
                UIApplication.shared.open(url)
            }
        } else if let name = idea.placeName?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "http://maps.apple.com/?q=\(name)") {
            UIApplication.shared.open(url)
        }
    }

    private func attachSharedForAutoSaved(ideaId: UUID) async {
        attachSharedError = nil
        isAttachingShared = true
        defer { isAttachingShared = false }
        let ids: [UUID] = {
            guard let p = personalDefaultCollectionId else {
                return Array(selectedSharedCollectionIds)
            }
            return Array(selectedSharedCollectionIds.filter { $0 != p })
        }()
        guard !ids.isEmpty else { return }
        do {
            try await apiClient.attachIdeaSharedCollections(ideaId: ideaId, sharedCollectionIds: ids)
            selectedSharedCollectionIds = []
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
        } catch {
            attachSharedError = error.localizedDescription
        }
    }

    private func failedBlock(_ d: APIClient.SavedReelDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let err = d.jobError?.trimmingCharacters(in: .whitespacesAndNewlines), !err.isEmpty {
                Text(err)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.error)
            } else {
                Text("Processing failed")
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.error)
            }
            if d.ingestRetriesUsed < Self.maxIngestRetries {
                if let retryIngestError {
                    Text(retryIngestError)
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.error)
                }
                Button {
                    Task { await retryFailedIngest(d) }
                } label: {
                    if isRetryingIngest {
                        ProgressView().scaleEffect(0.85)
                    } else {
                        Text("retry")
                            .font(RoamFont.mono(11, weight: .medium))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(RoamColors.loganDeep)
                .disabled(isRetryingIngest)
            } else {
                Text("Retry limit reached (\(Self.maxIngestRetries) attempts).")
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.textMuted)
            }
        }
    }

    private var reelIngestSearchingBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
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

    private func ideasSection(_ d: APIClient.SavedReelDetailDTO) -> some View {
        let rows = d.ideasNonEmpty
        return Group {
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ideas")
                        .font(RoamFont.mono(10, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1)

                    ForEach(rows) { idea in
                        NavigationLink {
                            IdeaDetailPage(ideaId: idea.id.uuidString)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.title)
                                    .font(RoamFont.mono(11, weight: .medium))
                                    .foregroundStyle(RoamColors.loganDark)
                                if let p = idea.placeName, !p.isEmpty {
                                    Text(p)
                                        .font(RoamFont.mono(9))
                                        .foregroundStyle(RoamColors.textMuted)
                                }
                                Text(idea.status)
                                    .font(RoamFont.mono(8))
                                    .foregroundStyle(RoamColors.textMuted)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                    }
                }
            }
        }
    }

    private func pendingCandidates(_ d: APIClient.SavedReelDetailDTO) -> [APIClient.ReelCandidateDetailDTO] {
        d.candidates.filter { $0.promotedIdeaId == nil }
    }

    private func selectedPending(_ d: APIClient.SavedReelDetailDTO) -> [APIClient.ReelCandidateDetailDTO] {
        pendingCandidates(d).filter { selectedCandidateIds.contains($0.id) }
    }

    private func canPromotePending(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        (d.status == "needs_review" || d.status == "promoted") && d.status != "processing" && d.status != "failed"
    }

    @ViewBuilder
    private func candidatesSection(_ d: APIClient.SavedReelDetailDTO, readOnly: Bool) -> some View {
        let ordered = d.candidates.sorted { $0.sortIndex < $1.sortIndex }
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ordered) { c in
                let pending = c.promotedIdeaId == nil
                VStack(alignment: .leading, spacing: 6) {
                    if readOnly || !pending {
                        Text(c.previewTitle.isEmpty ? "—" : c.previewTitle)
                            .font(RoamFont.mono(11))
                            .foregroundStyle(RoamColors.loganDark)
                    } else {
                        TextField(
                            "title",
                            text: Binding(
                                get: {
                                    if let t = titleEdits[c.id] { return t }
                                    return c.previewTitle
                                },
                                set: { titleEdits[c.id] = $0 }
                            )
                        )
                        .font(RoamFont.mono(11))
                        .textFieldStyle(.roundedBorder)

                        TextField(
                            "location (maps search)",
                            text: Binding(
                                get: {
                                    if let q = locationQueries[c.id] { return q }
                                    return c.resolvedPlaceName ?? ""
                                },
                                set: { locationQueries[c.id] = $0 }
                            )
                        )
                        .font(RoamFont.mono(10))
                        .textFieldStyle(.roundedBorder)
                    }

                    if c.isSynthetic && pending && !readOnly {
                        Text("summary — edit title before adding")
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                    if let rn = c.resolvedPlaceName, !rn.isEmpty {
                        Text(rn)
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                    if c.promotedIdeaId != nil {
                        Text("promoted")
                            .font(RoamFont.mono(8))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func load() async {
        loadError = nil
        do {
            detail = try await apiClient.getReel(id: reelId)
            if let d = detail {
                syncSelections(for: d)
                if isAutoSavedSingle(d), let first = d.ideasNonEmpty.first {
                    loadedAutoSavedIdea = try? await apiClient.getIdea(id: first.id.uuidString)
                } else {
                    loadedAutoSavedIdea = nil
                }
            } else {
                loadedAutoSavedIdea = nil
            }
        } catch {
            loadError = error.localizedDescription
            return
        }
        do {
            collections = try await apiClient.listCollections()
            stripPersonalFromSharedSelection()
        } catch {
            /* reel detail still usable; shared chips may be empty */
        }
    }

    private func reloadCollectionsOnly() async {
        do {
            collections = try await apiClient.listCollections()
            stripPersonalFromSharedSelection()
        } catch { /* ignore */ }
    }

    private func syncSelections(for d: APIClient.SavedReelDetailDTO) {
        let pending = pendingCandidates(d).map(\.id)
        selectedCandidateIds = Set(pending)
    }

    private func promote(_ d: APIClient.SavedReelDetailDTO) async {
        promoteError = nil
        isPromoting = true
        defer { isPromoting = false }
        let pending = selectedPending(d)
        guard !pending.isEmpty else { return }

        let items: [APIClient.ReelPromoteItem] = pending.map { c in
            let edited = titleEdits[c.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let useTitle: String?
            if let edited, !edited.isEmpty {
                useTitle = edited
            } else if !c.previewTitle.isEmpty {
                useTitle = c.previewTitle
            } else {
                useTitle = nil
            }
            let loc = locationQueries[c.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let mapsQ: String? = (loc?.isEmpty == false) ? loc : nil
            return APIClient.ReelPromoteItem(
                candidateId: c.id,
                title: useTitle,
                mapsQuery: mapsQ,
                placeAddress: nil,
                category: nil
            )
        }
        let sharedIds: [UUID] = {
            guard let p = personalDefaultCollectionId else {
                return Array(selectedSharedCollectionIds)
            }
            return Array(selectedSharedCollectionIds.filter { $0 != p })
        }()
        do {
            _ = try await apiClient.promoteReel(
                reelId: reelId,
                promotions: items,
                sharedCollectionIds: sharedIds
            )
            await stores.ideas.refresh()
            await stores.reels.refresh()
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
            await load()
            withAnimation {
                showPromoteSuccess = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                await MainActor.run {
                    withAnimation { showPromoteSuccess = false }
                }
            }
        } catch {
            promoteError = error.localizedDescription
        }
    }

    private func retryFailedIngest(_ d: APIClient.SavedReelDetailDTO) async {
        retryIngestError = nil
        guard let url = URL(string: d.reelUrl) else {
            retryIngestError = "Invalid reel URL"
            return
        }
        isRetryingIngest = true
        defer { isRetryingIngest = false }
        let pack = await ReelMetadataService.extract(url: url, shareText: nil)
        do {
            let resp = try await apiClient.retryFailedReelIngest(
                reelId: reelId,
                shareText: nil,
                reelTitle: pack.ingestReelTitle,
                ogDescription: pack.ingestOgDescription,
                ogKeywords: pack.ingestOgKeywords,
                thumbnailJPEG: pack.thumbnailJPEG,
                frameJPEGs: pack.frameJPEGs
            )
            let trimmedReel = resp.reelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let trackedReelId = trimmedReel.isEmpty ? reelId : trimmedReel
            shareIngress.beginIngestJobTracking(
                jobId: resp.jobId,
                reelId: trackedReelId,
                apiClient: apiClient,
                stores: stores
            )
            await load()
            await stores.reels.refresh()
        } catch {
            retryIngestError = error.localizedDescription
        }
    }
}

// MARK: - New shared collection

private struct NewSharedCollectionSheet: View {
    let apiClient: APIClient
    var onCreated: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var friends: [APIClient.FriendshipRowDTO] = []
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var peopleSearchQuery = ""
    @State private var searchFriendMatches: [RoamUser] = []
    @State private var isSearchingPeople = false
    @State private var searchPeopleTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("name") {
                    TextField("collection name", text: $name)
                        .font(RoamFont.mono(12))
                }
                Section("people") {
                    TextField("search friends", text: $peopleSearchQuery)
                        .font(RoamFont.mono(11))
                        .onChange(of: peopleSearchQuery) { _, newVal in
                            searchPeopleTask?.cancel()
                            let q = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !q.isEmpty else {
                                searchFriendMatches = []
                                return
                            }
                            searchPeopleTask = Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                guard !Task.isCancelled else { return }
                                await runPeopleSearch(q)
                            }
                        }
                    if isLoading {
                        ProgressView()
                    } else {
                        let trimmedSearch = peopleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedSearch.isEmpty {
                            if isSearchingPeople {
                                ProgressView()
                            } else if searchFriendMatches.isEmpty {
                                Text("No matching friends.")
                                    .font(RoamFont.mono(10))
                                    .foregroundStyle(RoamColors.textMuted)
                            } else {
                                ForEach(searchFriendMatches, id: \.id) { u in
                                    if let uid = UUID(uuidString: u.id) {
                                        Button {
                                            if selectedFriendIds.contains(uid) {
                                                selectedFriendIds.remove(uid)
                                            } else {
                                                selectedFriendIds.insert(uid)
                                            }
                                        } label: {
                                            HStack {
                                                Text(u.displayName)
                                                    .font(RoamFont.mono(11))
                                                Spacer()
                                                if selectedFriendIds.contains(uid) {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(RoamColors.loganDeep)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } else if friends.isEmpty {
                            Text("No friends yet — add friends first.")
                                .font(RoamFont.mono(10))
                                .foregroundStyle(RoamColors.textMuted)
                        } else {
                            ForEach(friends) { f in
                                if let fid = f.friendId {
                                    Button {
                                        if selectedFriendIds.contains(fid) {
                                            selectedFriendIds.remove(fid)
                                        } else {
                                            selectedFriendIds.insert(fid)
                                        }
                                    } label: {
                                        HStack {
                                            Text(
                                                [f.friendFirstName, f.friendLastName]
                                                    .compactMap { $0 }
                                                    .joined(separator: " ")
                                            )
                                            .font(RoamFont.mono(11))
                                            Spacer()
                                            if selectedFriendIds.contains(fid) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(RoamColors.loganDeep)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.error)
                    }
                }
            }
            .navigationTitle("new collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("create") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { await loadFriends() }
        }
    }

    private func loadFriends() async {
        isLoading = true
        defer { isLoading = false }
        do {
            friends = try await apiClient.listFriends()
        } catch {
            friends = []
        }
    }

    private func runPeopleSearch(_ q: String) async {
        isSearchingPeople = true
        defer { isSearchingPeople = false }
        do {
            let r = try await apiClient.searchFriends(query: q)
            searchFriendMatches = r.friends
        } catch {
            searchFriendMatches = []
        }
    }

    private func save() async {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let created = try await apiClient.createSharedCollection(
                name: n,
                description: nil,
                memberUserIds: Array(selectedFriendIds)
            )
            onCreated(created.id)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Add idea on reel

private struct AddReelIdeaSheet: View {
    let reelId: String
    var onDone: () -> Void

    @Environment(\.apiClient) private var apiClient
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var searchQuery = ""
    @State private var searchResults: [APIClient.PlaceSearchRowDTO] = []
    @State private var selectedPlaceId: UUID?
    @State private var isSearching = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("title") {
                    TextField("idea title", text: $title)
                        .font(RoamFont.mono(12))
                }
                Section("place (optional)") {
                    TextField("search places", text: $searchQuery)
                        .font(RoamFont.mono(11))
                        .onChange(of: searchQuery) { _, newVal in
                            searchTask?.cancel()
                            let q = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard q.count >= 2 else {
                                searchResults = []
                                return
                            }
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 350_000_000)
                                guard !Task.isCancelled else { return }
                                await runSearch(q)
                            }
                        }
                    if isSearching {
                        ProgressView()
                    }
                    ForEach(searchResults) { row in
                        Button {
                            selectedPlaceId = row.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).font(RoamFont.mono(11))
                                    if let a = row.address, !a.isEmpty {
                                        Text(a).font(RoamFont.mono(9)).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selectedPlaceId == row.id {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }
                if let error {
                    Section {
                        Text(error)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.error)
                    }
                }
            }
            .navigationTitle("new idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("save") { Task { await save() } }
                        .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func runSearch(_ q: String) async {
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await apiClient.searchPlacesList(query: q, limit: 8)
        } catch {
            searchResults = []
        }
    }

    private func save() async {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            _ = try await apiClient.createIdeaOnReel(
                reelId: reelId,
                title: t,
                notes: "",
                placeId: selectedPlaceId
            )
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
