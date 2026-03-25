import CoreLocation
import SwiftUI
import UIKit

/// Shared collection IDs used for the first promote on this reel (this device); hybrid saves reuse them read-only.
private enum ReelDetailPromotionSharedIdsStore {
    private static func key(_ reelId: String) -> String {
        "roam.reelPromoteSharedIds.\(reelId.lowercased())"
    }

    /// `nil` if we have not recorded a promote for this reel yet on this device.
    static func load(reelId: String) -> [UUID]? {
        let k = key(reelId)
        guard UserDefaults.standard.object(forKey: k) != nil else { return nil }
        let raw = UserDefaults.standard.array(forKey: k) as? [String] ?? []
        return raw.compactMap { UUID(uuidString: $0) }
    }

    static func save(reelId: String, sharedCollectionIds: [UUID]) {
        UserDefaults.standard.set(
            sharedCollectionIds.map { $0.uuidString.lowercased() },
            forKey: key(reelId)
        )
    }

    static func clear(reelId: String) {
        UserDefaults.standard.removeObject(forKey: key(reelId))
    }
}

struct ReelDetailPage: View {
    let reelId: String

    private static let maxIngestRetries = 5

    @Environment(\.apiClient) private var apiClient
    @Environment(\.roamStores) private var stores
    @Environment(AppConfig.self) private var appConfig
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
    @State private var newCollectionBanner: (title: String, subtitle: String)?
    @State private var isRetryingIngest = false
    @State private var retryIngestError: String?
    @State private var showDeleteReelConfirm = false
    @State private var isDeletingReel = false
    @State private var deleteReelError: String?
    @State private var isAttachingShared = false
    @State private var attachSharedError: String?
    @State private var locationPickerCandidateId: UUID?
    @State private var pickedPlaces: [UUID: PickedLocation] = [:]

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
            if let d = detail, isReadOnlyPromotedReel(d) {
                ToolbarItem(placement: .principal) {
                    Text("reel")
                        .font(RoamFont.mono(15, weight: .bold))
                        .foregroundStyle(RoamColors.text)
                }
            }
            if let d = detail {
                if !isReadOnlyPromotedReel(d) {
                    ToolbarItem(placement: .primaryAction) {
                        Button("add idea") { showAddIdea = true }
                            .font(RoamFont.mono(10, weight: .medium))
                            .disabled(d.status == "processing")
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("add idea") { showAddIdea = true }
                        .font(RoamFont.mono(10, weight: .medium))
                        .disabled(true)
                }
            }
        }
        .alert("Remove reel from history?", isPresented: $showDeleteReelConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                Task { await deleteSavedReelFromHistory() }
            }
        } message: {
            Text("Your saved places stay in Ideas; this only removes the reel from Reels.")
        }
        .alert("Couldn't remove reel", isPresented: Binding(
            get: { deleteReelError != nil },
            set: { if !$0 { deleteReelError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteReelError = nil }
        } message: {
            Text(deleteReelError ?? "")
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
            NewSharedCollectionSheet(apiClient: apiClient) { created, invitedFirstNames in
                selectedSharedCollectionIds.insert(created.id)
                showNewCollectionSheet = false
                Task { await reloadCollectionsOnly() }
                let sub = newCollectionBannerSubtitle(invitedFirstNames: invitedFirstNames)
                newCollectionBanner = ("\(created.name) created", sub)
            }
            .presentationDetents([.fraction(0.92), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { locationPickerCandidateId != nil },
            set: { if !$0 { locationPickerCandidateId = nil } }
        )) {
            if let candidateId = locationPickerCandidateId {
                let candidate = detail?.candidates.first(where: { $0.id == candidateId })
                let initialQuery = candidate?.resolvedPlaceName ?? candidate?.mapsQuery ?? candidate?.previewTitle ?? ""
                let initialCoord: CLLocationCoordinate2D? = {
                    if let lat = candidate?.placeLatitude, let lng = candidate?.placeLongitude {
                        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
                    }
                    return nil
                }()
                LocationPickerSheet(
                    initialQuery: initialQuery,
                    initialCoordinate: initialCoord,
                    onConfirm: { picked in
                        pickedPlaces[candidateId] = picked
                        locationQueries[candidateId] = picked.name
                        // Persist user-confirmed place to the backend.
                        Task {
                            _ = try? await apiClient.updateCandidatePlace(
                                reelId: reelId,
                                candidateId: candidateId.uuidString,
                                body: .init(
                                    placeName: picked.name,
                                    placeAddress: picked.address,
                                    latitude: picked.latitude,
                                    longitude: picked.longitude,
                                    mapsQuery: picked.name
                                )
                            )
                            // Refresh detail so the GET reflects the updated data.
                            if let refreshed = try? await apiClient.getReel(id: reelId) {
                                await MainActor.run { detail = refreshed }
                            }
                        }
                    }
                )
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: newCollectionBanner?.title) { _, newVal in
            guard newVal != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await MainActor.run { newCollectionBanner = nil }
            }
        }
        .task { await load() }
    }

    private var navigationTitleText: String {
        guard let d = detail else { return "review reel" }
        if isReadOnlyPromotedReel(d) { return "" }
        return "review reel"
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

                    if isHybridSavedPlusPending(d) {
                        hybridPartialSavedReelContent(d)
                    } else if isReadOnlyPromotedReel(d) {
                        readOnlySavedReelContent(d)
                    } else if usesMultiStyleReview(d) {
                        multiPlaceReviewScroll(d)
                    } else {
                        legacyReelDetailContent(d)
                    }
                }
                .padding(.bottom, showsPromoteDock(d) ? 130 : 8)
            }
            .background(RoamColors.background)

            if showsPromoteDock(d) {
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

    /// Fully saved / read-only reel: promoted, nothing left to review, not failed.
    private func isReadOnlyPromotedReel(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        d.status == "promoted"
            && pendingCandidates(d).isEmpty
            && d.jobStatus != "failed"
            && d.status != "failed"
    }

    /// At least one idea saved from this reel, and more candidates can still be promoted (read-only saved rows + review rows).
    private func isHybridSavedPlusPending(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        guard d.jobStatus != "failed", d.status != "failed" else { return false }
        guard canPromotePending(d) else { return false }
        guard !pendingCandidates(d).isEmpty else { return false }
        return !d.ideasNonEmpty.isEmpty
    }

    private func usesMultiStyleReview(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        canPromotePending(d) && !pendingCandidates(d).isEmpty
    }

    /// Save button dock: any promotable pending (initial multi-review or hybrid continuation).
    private func showsPromoteDock(_ d: APIClient.SavedReelDetailDTO) -> Bool {
        usesMultiStyleReview(d)
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

            readOnlyDeleteReelRow()
                .padding(.top, 12)
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

            if let b = newCollectionBanner {
                newCollectionSuccessBanner(b)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)
            }

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
            .padding(.bottom, 4)

            readOnlyDeleteReelRow()
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
            Text("Also add to a shared collection with friends?")
                .font(Font.system(size: 12))
                .foregroundStyle(RoamColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

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

                    NewSharedCollectionChipButton {
                        showNewCollectionSheet = true
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

    private func formatNotifiedNames(_ names: [String]) -> String {
        let n = names.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !n.isEmpty else { return "" }
        if n.count == 1 { return n[0] }
        if n.count == 2 { return "\(n[0]) & \(n[1])" }
        return n.dropLast().joined(separator: ", ") + " & " + (n.last ?? "")
    }

    private func newCollectionBannerSubtitle(invitedFirstNames: [String]) -> String {
        let formatted = formatNotifiedNames(invitedFirstNames)
        if formatted.isEmpty {
            return "Shared with you — add more members anytime."
        }
        return "\(formatted) will be notified"
    }

    @ViewBuilder
    private func newCollectionSuccessBanner(_ banner: (title: String, subtitle: String)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(RoamColors.reviewSuccess)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                if !banner.subtitle.isEmpty {
                    Text(banner.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoamColors.reviewSuccessBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RoamColors.reviewSuccess.opacity(0.35), lineWidth: 1)
        )
    }

    private func multiPlaceCandidateCard(_ d: APIClient.SavedReelDetailDTO, _ c: APIClient.ReelCandidateDetailDTO, rank: Int) -> some View {
        let checked = selectedCandidateIds.contains(c.id)
        let picked = pickedPlaces[c.id]
        let hasExactAddress = picked != nil || c.resolvedPlaceName != nil
        return VStack(alignment: .leading, spacing: 0) {
            // Header row: checkbox + title + category + rank
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

                    // "Detected in …" non-editable LLM description
                    if let detectedLocation = c.detectedInDisplayText {
                        HStack(alignment: .center, spacing: 3) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 9))
                                .foregroundStyle(RoamColors.textMuted)
                            Text("Detected in \(detectedLocation)")
                                .font(.system(size: 11))
                                .foregroundStyle(RoamColors.textMuted)
                                .lineLimit(1)
                        }
                    }

                    Text(c.cardCategory.uppercased())
                        .font(RoamFont.mono(9, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(checked ? RoamColors.reviewSuccess.opacity(0.15) : RoamColors.reviewSurfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text("#\(rank)")
                    .font(RoamFont.mono(18, weight: .bold))
                    .foregroundStyle(checked ? RoamColors.reviewSuccess : RoamColors.reviewBorder)
                    .frame(width: 28)
            }
            .padding(14)

            // Tappable location row
            Button {
                locationPickerCandidateId = c.id
            } label: {
                candidateLocationRow(c, picked: picked, hasExactAddress: hasExactAddress)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(checked ? RoamColors.reviewSuccessBg : RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(checked ? RoamColors.reviewSuccess : RoamColors.reviewBorder, lineWidth: 1.5)
        )
    }

    private func primarySaveButtonTitle(_ d: APIClient.SavedReelDetailDTO) -> String {
        let n = selectedPending(d).count
        if n == 0 { return "Select places to save" }
        return "Save \(n) place\(n == 1 ? "" : "s")"
    }

    private func candidateLocationRow(_ c: APIClient.ReelCandidateDetailDTO, picked: PickedLocation?, hasExactAddress: Bool) -> some View {
        let addressText: String
        let hintText: String
        let accentColor: Color
        let actionText: String

        if let picked {
            addressText = picked.address.isEmpty ? picked.name : picked.address
            hintText = "Tap to change location"
            accentColor = RoamColors.reviewAccent
            actionText = "Edit"
        } else if let addr = c.placeAddress, !addr.isEmpty {
            addressText = addr
            hintText = "Tap to adjust location"
            accentColor = RoamColors.reviewAccent
            actionText = "Edit"
        } else {
            addressText = "No exact address found"
            hintText = "Tap to set location manually"
            accentColor = RoamColors.reviewPartnerPink
            actionText = "Set"
        }

        return HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor.opacity(0.08))
                    .frame(width: 28, height: 28)
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 12))
                    .foregroundStyle(accentColor)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(addressText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hasExactAddress ? RoamColors.text : accentColor)
                    .lineLimit(1)
                Text(hintText)
                    .font(.system(size: 10))
                    .foregroundStyle(RoamColors.textMuted)
            }
            Spacer()
            Text(actionText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoamColors.reviewAccent)
        }
        .padding(10)
        .background(RoamColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(hasExactAddress ? RoamColors.reviewBorder : accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func ideasSortedByReelOrder(_ d: APIClient.SavedReelDetailDTO) -> [APIClient.SavedReelIdeaSummaryDTO] {
        let promotedPairs = d.candidates.filter { $0.promotedIdeaId != nil }.sorted { $0.sortIndex < $1.sortIndex }
        var out: [APIClient.SavedReelIdeaSummaryDTO] = []
        var seen = Set<UUID>()
        for c in promotedPairs {
            guard let pid = c.promotedIdeaId,
                  let idea = d.ideasNonEmpty.first(where: { $0.id == pid }),
                  !seen.contains(idea.id) else { continue }
            out.append(idea)
            seen.insert(idea.id)
        }
        for idea in d.ideasNonEmpty where !seen.contains(idea.id) {
            out.append(idea)
        }
        return out
    }

    private func skippedCandidatesReadOnly(_ d: APIClient.SavedReelDetailDTO) -> [APIClient.ReelCandidateDetailDTO] {
        d.candidates.filter { $0.promotedIdeaId == nil }.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func skipReasonLabel(_ c: APIClient.ReelCandidateDetailDTO) -> String {
        if c.isSynthetic { return "experience" }
        let hasPin = c.resolvedPlaceId != nil
        let hasMaps = !(c.mapsQuery ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAddr = !(c.placeAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !hasPin, !hasMaps, !hasAddr { return "no map pin" }
        let cat = (c.category ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cat.isEmpty ? "not saved" : String(cat.prefix(24))
    }

    private func reelCaptionReadOnly(_ d: APIClient.SavedReelDetailDTO) -> String {
        let sorted = d.candidates.sorted { $0.sortIndex < $1.sortIndex }
        for c in sorted {
            let t = c.cardDescription
            if !t.isEmpty { return t }
        }
        return ""
    }

    private func categoryTagLabel(_ c: APIClient.ReelCandidateDetailDTO?) -> String {
        let raw = c?.cardCategory ?? "other"
        if raw == "other" { return "place" }
        return raw.replacingOccurrences(of: "_", with: " ")
    }

    private func hybridLockedCollectionsBar() -> some View {
        let personalName = collections.first { $0.isPersonalDefault }?.name ?? "My saves"
        let lockedShared = collections.filter { !$0.isPersonalDefault && selectedSharedCollectionIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Collections for this reel")
                    .font(Font.system(size: 12, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(RoamColors.textMuted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if lockedShared.isEmpty {
                        Text("No shared collections")
                            .font(Font.system(size: 12))
                            .foregroundStyle(RoamColors.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoamColors.reviewSurfaceAlt)
                            .clipShape(Capsule())
                    } else {
                        ForEach(lockedShared) { c in
                            HStack(spacing: 5) {
                                collectionMemberDots(c, maxDots: 3)
                                Text(c.name)
                                    .font(Font.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoamColors.reviewAccentLight)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(RoamColors.reviewAccent.opacity(0.45), lineWidth: 1.2))
                            .foregroundStyle(RoamColors.text)
                        }
                    }
                }
            }
            Text("Locked after your first save — same collections apply to the rest of this reel.")
                .font(Font.system(size: 11))
                .foregroundStyle(RoamColors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every place is also saved to \(personalName).")
                .font(Font.system(size: 11))
                .foregroundStyle(RoamColors.textMuted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func hybridPartialSavedReelContent(_ d: APIClient.SavedReelDetailDTO) -> some View {
        let ideasOrdered = ideasSortedByReelOrder(d)
        let pendingOrdered = pendingCandidates(d).sorted { $0.sortIndex < $1.sortIndex }
        let savedCount = ideasOrdered.count
        let totalCand = d.candidates.count
        let savedDate = d.updatedAt.formatted(date: .abbreviated, time: .omitted)

        VStack(alignment: .leading, spacing: 0) {
            readOnlyReelPreviewCard(
                d,
                caption: reelCaptionReadOnly(d),
                savedLabel: savedDate,
                placeCount: savedCount,
                totalCandidateCount: totalCand
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)

            readOnlySavedBanner(
                placeCount: savedCount,
                dateLabel: savedDate,
                moreToSaveCount: pendingOrdered.count
            )
            .padding(.horizontal, 20)
            .padding(.top, 14)

            readOnlySavedPlacesSectionHeader(single: savedCount == 1, count: savedCount)
                .padding(.top, 12)

            ForEach(Array(ideasOrdered.enumerated()), id: \.element.id) { idx, idea in
                let cand = promotedCandidateForIdea(d, ideaId: idea.id)
                readOnlyPlaceCard(
                    idea: idea,
                    candidate: cand,
                    rank: idx + 1,
                    showRank: savedCount >= 2,
                    showFromReelTag: savedCount == 1,
                    personalCollectionName: collections.first { $0.isPersonalDefault }?.name ?? "My saves",
                    showCollectionsFooter: false
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            hybridLockedCollectionsBar()
                .padding(.horizontal, 20)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 0) {
                Text("Save more from this reel")
                    .font(RoamFont.mono(12, weight: .semibold))
                    .foregroundStyle(RoamColors.textMuted)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                Text("Select places below, then tap Save.")
                    .font(Font.system(size: 11))
                    .foregroundStyle(RoamColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                ForEach(Array(pendingOrdered.enumerated()), id: \.element.id) { idx, c in
                    multiPlaceCandidateCard(d, c, rank: savedCount + idx + 1)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
            }

            readOnlyDeleteReelRow()
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func readOnlySavedReelContent(_ d: APIClient.SavedReelDetailDTO) -> some View {
        let ideasOrdered = ideasSortedByReelOrder(d)
        let skipped = skippedCandidatesReadOnly(d)
        let n = ideasOrdered.count
        let savedDate = d.updatedAt.formatted(date: .abbreviated, time: .omitted)
        let personalName = collections.first { $0.isPersonalDefault }?.name ?? "My saves"

        VStack(alignment: .leading, spacing: 0) {
            readOnlyReelPreviewCard(
                d,
                caption: reelCaptionReadOnly(d),
                savedLabel: savedDate,
                placeCount: n,
                totalCandidateCount: nil
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)

            readOnlySavedBanner(placeCount: n, dateLabel: savedDate, moreToSaveCount: 0)
                .padding(.horizontal, 20)
                .padding(.top, 14)

            readOnlySavedPlacesSectionHeader(single: n == 1, count: n)
                .padding(.top, 12)

            ForEach(Array(ideasOrdered.enumerated()), id: \.element.id) { idx, idea in
                let cand = promotedCandidateForIdea(d, ideaId: idea.id)
                readOnlyPlaceCard(
                    idea: idea,
                    candidate: cand,
                    rank: idx + 1,
                    showRank: n >= 2,
                    showFromReelTag: n == 1,
                    personalCollectionName: personalName,
                    showCollectionsFooter: true
                )
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }

            if n == 1, let only = ideasOrdered.first {
                singleReadOnlySharedCollectionsBlock(d: d, ideaId: only.id)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            if !skipped.isEmpty {
                readOnlySkippedSection(candidates: skipped)
                    .padding(.top, 16)
            }

            readOnlyDeleteReelRow()
                .padding(.top, 20)
                .padding(.bottom, 24)
        }
    }

    @ViewBuilder
    private func readOnlyReelPreviewCard(
        _ d: APIClient.SavedReelDetailDTO,
        caption: String,
        savedLabel: String,
        placeCount: Int,
        totalCandidateCount: Int? = nil
    ) -> some View {
        let thumbHeight: CGFloat = 180
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let rid = UUID(uuidString: reelId) {
                    ReelThumbnailImageView(reelId: rid, signedUrl: d.thumbnailSignedUrl, contentMode: .fill)
                        .frame(height: thumbHeight)
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
                        .frame(height: thumbHeight)
                }

                LinearGradient(
                    colors: [.black.opacity(0.45), .clear, .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: thumbHeight)

                Button {
                    if let url = URL(string: d.reelUrl) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "play.fill")
                                .font(.system(size: 18))
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
            .frame(height: thumbHeight)
            .clipped()

            VStack(alignment: .leading, spacing: 8) {
                if !caption.isEmpty {
                    Text(caption)
                        .font(Font.system(size: 12))
                        .foregroundStyle(RoamColors.textMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text("Saved \(savedLabel)")
                        .font(Font.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                    Circle()
                        .fill(RoamColors.reviewBorder)
                        .frame(width: 4, height: 4)
                    if let total = totalCandidateCount, total != placeCount {
                        Text("\(placeCount) of \(total) places extracted")
                            .font(Font.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                    } else {
                        Text("\(placeCount) place\(placeCount == 1 ? "" : "s") extracted")
                            .font(Font.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
            }
            .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
    }

    private func readOnlySavedBanner(placeCount: Int, dateLabel: String, moreToSaveCount: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(RoamColors.reviewSuccess)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(placeCount) place\(placeCount == 1 ? "" : "s") saved")
                        .font(Font.system(size: 12, weight: .semibold))
                        .foregroundStyle(RoamColors.text)
                    Text("· \(dateLabel)")
                        .font(Font.system(size: 12, weight: .regular))
                        .foregroundStyle(RoamColors.textMuted)
                }
                if moreToSaveCount > 0 {
                    Text("\(moreToSaveCount) more from this reel — select below to save.")
                        .font(Font.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
        .background(RoamColors.reviewSuccessBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RoamColors.reviewSuccess.opacity(0.22), lineWidth: 1)
        )
    }

    private func readOnlySavedPlacesSectionHeader(single: Bool, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(single ? "Saved Place" : "Saved Places")
                .font(RoamFont.mono(12, weight: .semibold))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            if !single {
                Text("\(count)")
                    .font(RoamFont.mono(11, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func singleReadOnlySharedCollectionsBlock(d: APIClient.SavedReelDetailDTO, ideaId: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            reviewSaveToBar(d)

            if let b = newCollectionBanner {
                newCollectionSuccessBanner(b)
            }

            if let attachSharedError {
                Text(attachSharedError)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.error)
            }

            if !selectedSharedCollectionIds.isEmpty {
                Button {
                    Task { await attachSharedForReadOnlyIdea(ideaId: ideaId) }
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
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
    }

    private func attachSharedForReadOnlyIdea(ideaId: UUID) async {
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

    @ViewBuilder
    private func readOnlyPlaceCard(
        idea: APIClient.SavedReelIdeaSummaryDTO,
        candidate: APIClient.ReelCandidateDetailDTO?,
        rank: Int,
        showRank: Bool,
        showFromReelTag: Bool,
        personalCollectionName: String,
        showCollectionsFooter: Bool = true
    ) -> some View {
        let addr = candidate?.cardAddressLine ?? idea.placeName
        let blurb = (candidate?.cardDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let catLabel = categoryTagLabel(candidate)

        NavigationLink {
            if appConfig.appMode == .alphaHeavyDevelopmentUnsafe {
                IdeaDetailPage(ideaId: idea.id.uuidString.lowercased())
            } else {
                ConsumerIdeaDetailPage(
                    route: ConsumerIdeaDetailRoute(
                        ideaId: idea.id.uuidString.lowercased(),
                        addressHint: addr,
                        addedByDisplayName: nil,
                        addedByColorIndex: nil,
                        categorySnapshot: candidate?.cardCategory
                    )
                )
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    if showRank {
                        Text("#\(rank)")
                            .font(RoamFont.mono(14, weight: .bold))
                            .foregroundStyle(RoamColors.reviewBorder)
                            .frame(width: 28, alignment: .center)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(idea.title)
                            .font(Font.system(size: 15, weight: .semibold))
                            .foregroundStyle(RoamColors.text)
                            .multilineTextAlignment(.leading)
                        if let addr, !addr.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 10))
                                    .foregroundStyle(RoamColors.textMuted)
                                Text(addr)
                                    .font(Font.system(size: 11))
                                    .foregroundStyle(RoamColors.textMuted)
                                    .lineLimit(2)
                            }
                        }
                        if !blurb.isEmpty {
                            Text(blurb)
                                .font(Font.system(size: 12))
                                .foregroundStyle(RoamColors.textMuted)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack(spacing: 4) {
                            Text(catLabel)
                                .font(RoamFont.mono(9, weight: .medium))
                                .foregroundStyle(RoamColors.textMuted)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(RoamColors.reviewSurfaceAlt)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            if showFromReelTag {
                                Text("from reel")
                                    .font(RoamFont.mono(9, weight: .medium))
                                    .foregroundStyle(RoamColors.reviewAccent)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(RoamColors.reviewAccentLight)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewBorder)
                }
                .padding(14)

                if showCollectionsFooter {
                    HStack(alignment: .center, spacing: 6) {
                        Text("In:")
                            .font(Font.system(size: 10))
                            .foregroundStyle(RoamColors.textMuted)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(RoamColors.reviewSuccess)
                                .frame(width: 5, height: 5)
                            Text(personalCollectionName)
                                .font(Font.system(size: 10, weight: .medium))
                                .foregroundStyle(RoamColors.textMuted)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(RoamColors.reviewSurfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.leading, showRank ? 54 : 14)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(RoamColors.reviewBorder.opacity(0.45))
                            .frame(height: 1)
                    }
                }
            }
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RoamColors.reviewBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func readOnlySkippedSection(candidates: [APIClient.ReelCandidateDetailDTO]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Not saved (\(candidates.count))")
                .font(RoamFont.mono(11, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            ForEach(candidates) { c in
                HStack(alignment: .center, spacing: 10) {
                    Text(c.previewTitle.isEmpty ? "—" : c.previewTitle)
                        .font(Font.system(size: 13))
                        .foregroundStyle(RoamColors.textMuted)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(skipReasonLabel(c))
                        .font(RoamFont.mono(10, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                }
                .padding(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                .background(RoamColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(RoamColors.reviewBorder.opacity(0.6), lineWidth: 1)
                )
                .opacity(0.72)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
            }
        }
    }

    private func readOnlyDeleteReelRow() -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RoamColors.reviewBorder.opacity(0.45))
                .frame(height: 1)
                .padding(.horizontal, 20)

            Button {
                showDeleteReelConfirm = true
            } label: {
                Group {
                    if isDeletingReel {
                        ProgressView()
                            .padding(.vertical, 10)
                    } else {
                        Text("Delete this reel")
                            .font(Font.system(size: 13, weight: .medium))
                            .foregroundStyle(RoamColors.reviewPartnerPink)
                            .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(isDeletingReel)
            .buttonStyle(.plain)
        }
    }

    private func deleteSavedReelFromHistory() async {
        isDeletingReel = true
        defer { isDeletingReel = false }
        do {
            try await apiClient.deleteReel(id: reelId)
            ReelDetailPromotionSharedIdsStore.clear(reelId: reelId)
            await stores.reels.refresh()
            dismiss()
        } catch {
            deleteReelError = error.localizedDescription
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
                            IdeaDetailPage(ideaId: idea.id.uuidString.lowercased())
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
            }
        } catch {
            loadError = error.localizedDescription
            return
        }
        do {
            collections = try await apiClient.listCollections()
            stripPersonalFromSharedSelection()
            if let d = detail {
                if isHybridSavedPlusPending(d) {
                    restoreHybridLockedSharedSelections()
                }
                if isReadOnlyPromotedReel(d) {
                    ReelDetailPromotionSharedIdsStore.clear(reelId: reelId)
                }
            }
        } catch {
            /* reel detail still usable; shared chips may be empty */
        }
    }

    private func reloadCollectionsOnly() async {
        do {
            collections = try await apiClient.listCollections()
            stripPersonalFromSharedSelection()
            if let d = detail, isHybridSavedPlusPending(d) {
                restoreHybridLockedSharedSelections()
            }
        } catch { /* ignore */ }
    }

    private func restoreHybridLockedSharedSelections() {
        guard let stored = ReelDetailPromotionSharedIdsStore.load(reelId: reelId) else { return }
        let valid = Set(collections.filter { !$0.isPersonalDefault }.map(\.id))
        selectedSharedCollectionIds = Set(stored).intersection(valid)
    }

    private func syncSelections(for d: APIClient.SavedReelDetailDTO) {
        let pending = pendingCandidates(d).map(\.id)
        if isHybridSavedPlusPending(d) {
            selectedCandidateIds = []
        } else {
            selectedCandidateIds = Set(pending)
        }
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
            let picked = pickedPlaces[c.id]
            let loc = locationQueries[c.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let mapsQ: String? = (loc?.isEmpty == false) ? loc : nil
            return APIClient.ReelPromoteItem(
                candidateId: c.id,
                title: useTitle,
                mapsQuery: picked == nil ? mapsQ : nil,
                placeAddress: nil,
                category: nil,
                placeId: picked?.placeId
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
            ReelDetailPromotionSharedIdsStore.save(reelId: reelId, sharedCollectionIds: sharedIds)
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

// MARK: - New shared collection chip + sheet

private struct PulsingAccentDot: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2 * .pi / 2) + 1) / 2
            Circle()
                .fill(RoamColors.reviewAccent)
                .frame(width: 8, height: 8)
                .scaleEffect(1 + 0.28 * phase)
                .opacity(1 - 0.48 * phase)
        }
    }
}

private struct NewSharedCollectionChipButton: View {
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: compact ? 2 : 3) {
                    Text("+")
                        .font(.system(size: compact ? 13 : 14, weight: .semibold))
                    Text("New")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                }
                .foregroundStyle(RoamColors.reviewAccent)
                .padding(.horizontal, compact ? 9 : 10)
                .padding(.vertical, compact ? 4 : 5)
                .padding(.trailing, compact ? 5 : 7)
                .padding(.top, 2)
                .background(RoamColors.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(RoamColors.reviewAccent, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )

                PulsingAccentDot()
                    .offset(x: compact ? 3 : 4, y: compact ? -3 : -4)
                    .allowsHitTesting(false)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NewSharedCollectionSheet: View {
    let apiClient: APIClient
    var onCreated: (APIClient.CollectionReadDTO, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool
    @State private var name = ""
    @State private var friends: [APIClient.FriendshipRowDTO] = []
    @State private var selectedFriendIds: Set<UUID> = []
    @State private var peopleSearchQuery = ""
    @State private var searchFriendMatches: [RoamUser] = []
    @State private var isSearchingPeople = false
    @State private var searchPeopleTask: Task<Void, Never>?
    @State private var isLoadingFriends = true
    @State private var isSaving = false
    @State private var error: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canCreate: Bool { !trimmedName.isEmpty }

    private var previewTitle: String {
        trimmedName.isEmpty ? "Untitled collection" : trimmedName
    }

    private var previewMemberLine: String {
        let labels = ["You"] + selectedFriendIds.sorted(by: { lhs, rhs in
            labelForFriend(lhs).localizedCaseInsensitiveCompare(labelForFriend(rhs)) == .orderedAscending
        }).map(labelForFriend)
        return labels.joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Button("Cancel") { dismiss() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(RoamColors.textMuted)
                    .frame(width: 64, alignment: .leading)

                Text("New Collection")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(RoamColors.text)
                    .frame(maxWidth: .infinity)

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.9)
                    } else {
                        Text("Create")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .frame(width: 64, alignment: .trailing)
                .disabled(!canCreate || isSaving)
                .opacity(canCreate ? 1 : 0.35)
                .foregroundStyle(RoamColors.reviewAccent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.35)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(RoamFont.mono(11, weight: .semibold))
                            .foregroundStyle(RoamColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        TextField("e.g. Date nights, NYC bars…", text: $name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(RoamColors.text)
                            .padding(14)
                            .background(RoamColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(nameFieldFocused ? RoamColors.reviewAccent : RoamColors.reviewBorder, lineWidth: 1.5)
                            )
                            .focused($nameFieldFocused)

                        Text("Friends you add will see this collection on their map.")
                            .font(.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("People")
                            .font(RoamFont.mono(11, weight: .semibold))
                            .foregroundStyle(RoamColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 96), spacing: 6, alignment: .leading)],
                            alignment: .leading,
                            spacing: 6
                        ) {
                            HStack(spacing: 5) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(RoamColors.reviewSuccess)
                                    .clipShape(Circle())
                                Text("You")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.leading, 4)
                            .padding(.trailing, 10)
                            .padding(.vertical, 4)
                            .background(RoamColors.reviewAccentLight)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(RoamColors.reviewAccent.opacity(0.35), lineWidth: 1))

                            ForEach(Array(selectedFriendIds).sorted(by: { labelForFriend($0) < labelForFriend($1) }), id: \.self) { uid in
                                HStack(spacing: 5) {
                                    Text(initials(from: labelForFriend(uid)))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(avatarColor(for: uid))
                                        .clipShape(Circle())
                                    Text(labelForFriend(uid))
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Button {
                                        selectedFriendIds.remove(uid)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(RoamColors.textMuted)
                                            .padding(.leading, 2)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.leading, 4)
                                .padding(.trailing, 8)
                                .padding(.vertical, 4)
                                .background(RoamColors.reviewAccentLight)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(RoamColors.reviewAccent.opacity(0.35), lineWidth: 1))
                            }
                        }

                        HStack(spacing: 0) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14))
                                .foregroundStyle(RoamColors.textMuted)
                                .frame(width: 38)
                            TextField("Search friends to add…", text: $peopleSearchQuery)
                                .font(.system(size: 14))
                                .textFieldStyle(.plain)
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
                        }
                        .padding(.vertical, 10)
                        .background(RoamColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
                        )

                        if isLoadingFriends {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        } else {
                            let q = peopleSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                            Group {
                                if !q.isEmpty {
                                    if isSearchingPeople {
                                        ProgressView()
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                    } else if searchFriendMatches.isEmpty {
                                        Text("No matching friends.")
                                            .font(.system(size: 12))
                                            .foregroundStyle(RoamColors.textMuted)
                                    } else {
                                        ForEach(searchFriendMatches, id: \.id) { u in
                                            if let uid = UUID(uuidString: u.id) {
                                                personRow(
                                                    userId: uid,
                                                    title: u.displayName,
                                                    subtitle: u.username.map { "@\($0)" },
                                                    selected: selectedFriendIds.contains(uid)
                                                ) {
                                                    if selectedFriendIds.contains(uid) {
                                                        selectedFriendIds.remove(uid)
                                                    } else {
                                                        selectedFriendIds.insert(uid)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                } else if friends.isEmpty {
                                    Text("No friends yet — add friends from your profile first.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(RoamColors.textMuted)
                                } else {
                                    ForEach(friends) { f in
                                        if let fid = f.friendId {
                                            let full = [f.friendFirstName, f.friendLastName]
                                                .compactMap { $0 }
                                                .joined(separator: " ")
                                            personRow(
                                                userId: fid,
                                                title: full.isEmpty ? "Friend" : full,
                                                subtitle: nil,
                                                selected: selectedFriendIds.contains(fid)
                                            ) {
                                                if selectedFriendIds.contains(fid) {
                                                    selectedFriendIds.remove(fid)
                                                } else {
                                                    selectedFriendIds.insert(fid)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(RoamFont.mono(10, weight: .semibold))
                            .foregroundStyle(RoamColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(0.8)

                        HStack(alignment: .center, spacing: 12) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(RoamColors.reviewAccentLight)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "square.stack.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(RoamColors.reviewAccent.opacity(0.85))
                                }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(previewTitle)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(RoamColors.text)
                                Text(previewMemberLine)
                                    .font(.system(size: 11))
                                    .foregroundStyle(RoamColors.textMuted)
                                    .lineLimit(2)

                                HStack(spacing: 3) {
                                    Circle()
                                        .fill(RoamColors.reviewSuccess)
                                        .frame(width: 8, height: 8)
                                    ForEach(Array(selectedFriendIds).sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { uid in
                                        Circle()
                                            .fill(avatarColor(for: uid))
                                            .frame(width: 8, height: 8)
                                    }
                                }
                                .padding(.top, 2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(RoamColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(RoamColors.reviewBorder, lineWidth: 1)
                        )
                    }

                    if let error {
                        Text(error)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.error)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28)
            }
            .background(RoamColors.surface)
        }
        .background(RoamColors.surface)
        .task { await loadFriends() }
    }

    @ViewBuilder
    private func personRow(
        userId _: UUID,
        title: String,
        subtitle: String?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(initials(from: title))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(avatarColor(fromStableKey: title))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RoamColors.text)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle()
                        .stroke(selected ? RoamColors.reviewAccent : RoamColors.reviewBorder, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if selected {
                        Circle()
                            .fill(RoamColors.reviewAccent)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(RoamColors.reviewBorder.opacity(0.35))
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func labelForFriend(_ userId: UUID) -> String {
        if let f = friends.first(where: { $0.friendId == userId }) {
            let s = [f.friendFirstName, f.friendLastName].compactMap { $0 }.joined(separator: " ")
            return s.isEmpty ? "Friend" : s
        }
        if let u = searchFriendMatches.first(where: { UUID(uuidString: $0.id) == userId }) {
            return u.displayName
        }
        return "Friend"
    }

    private func notifyLabel(for userId: UUID) -> String {
        if let f = friends.first(where: { $0.friendId == userId }) {
            if let fn = f.friendFirstName?.trimmingCharacters(in: .whitespacesAndNewlines), !fn.isEmpty {
                return fn
            }
        }
        if let u = searchFriendMatches.first(where: { UUID(uuidString: $0.id) == userId }) {
            let fn = u.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fn.isEmpty { return fn }
            if let un = u.username?.trimmingCharacters(in: .whitespacesAndNewlines), !un.isEmpty {
                return un
            }
        }
        return labelForFriend(userId)
    }

    private func avatarColor(for userId: UUID) -> Color {
        paletteColor(at: userId.hashValue)
    }

    private func avatarColor(fromStableKey key: String) -> Color {
        var h = 0
        for u in key.utf8 { h = h &* 31 &+ Int(u) }
        return paletteColor(at: h)
    }

    private func paletteColor(at hash: Int) -> Color {
        let palette: [Color] = [
            RoamColors.reviewSuccess,
            RoamColors.reviewPartnerPink,
            RoamColors.reviewSquadBlue,
            Color(red: 0.94, green: 0.63, blue: 0.19),
            Color(red: 0.61, green: 0.35, blue: 0.71),
            Color(red: 0.20, green: 0.60, blue: 0.86),
        ]
        let i = abs(hash) % max(palette.count, 1)
        return palette[i]
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let a = String(parts[0].prefix(1))
            let b = String(parts[1].prefix(1))
            return (a + b).uppercased()
        }
        if let f = parts.first {
            return String(f.prefix(2)).uppercased()
        }
        if name.count >= 2 {
            return String(name.prefix(2)).uppercased()
        }
        return String(name.prefix(1)).uppercased()
    }

    private func loadFriends() async {
        isLoadingFriends = true
        defer { isLoadingFriends = false }
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
            var seen = Set<String>()
            var merged: [RoamUser] = []
            for u in r.friends + r.others where seen.insert(u.id).inserted {
                merged.append(u)
            }
            searchFriendMatches = merged
        } catch {
            searchFriendMatches = []
        }
    }

    private func save() async {
        guard canCreate else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        let invited = Array(selectedFriendIds).map(notifyLabel).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        do {
            let created = try await apiClient.createSharedCollection(
                name: trimmedName,
                description: nil,
                memberUserIds: Array(selectedFriendIds)
            )
            onCreated(created, invited)
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
    @State private var notes = ""
    @State private var pickedLocation: PickedLocation?
    @State private var showLocationPicker = false
    @State private var isSaving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Place name
                    fieldSection("PLACE NAME") {
                        TextField("e.g. Joe's Pizza, Central Park…", text: $title)
                            .font(.system(size: 15))
                            .foregroundStyle(RoamColors.text)
                            .padding(14)
                            .background(RoamColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
                            )
                    }

                    // Location
                    fieldSection("LOCATION") {
                        Button { showLocationPicker = true } label: {
                            locationTriggerRow
                        }
                        .buttonStyle(.plain)
                    }

                    // Notes
                    fieldSection("NOTES (OPTIONAL)") {
                        TextField("Why do you want to go here?", text: $notes, axis: .vertical)
                            .font(.system(size: 14))
                            .foregroundStyle(RoamColors.text)
                            .lineLimit(3...6)
                            .padding(14)
                            .background(RoamColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
                            )
                    }

                    if let error {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(RoamColors.error)
                    }

                    // Save button
                    Button { Task { await save() } } label: {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save idea")
                                    .font(.system(size: 16, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? RoamColors.reviewAccent : RoamColors.reviewBorder)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: canSave ? RoamColors.reviewAccent.opacity(0.3) : .clear, radius: 8, y: 2)
                    }
                    .disabled(!canSave || isSaving)
                }
                .padding(20)
            }
            .background(RoamColors.background)
            .navigationTitle("add idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
            }
            .sheet(isPresented: $showLocationPicker) {
                LocationPickerSheet(
                    initialQuery: title,
                    initialCoordinate: nil,
                    onConfirm: { picked in
                        pickedLocation = picked
                    }
                )
                .presentationDetents([.fraction(0.85), .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var locationTriggerRow: some View {
        if let loc = pickedLocation {
            // Location set
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(RoamColors.reviewSuccess.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14))
                        .foregroundStyle(RoamColors.reviewSuccess)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(loc.address.isEmpty ? loc.name : loc.address)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(RoamColors.text)
                        .lineLimit(1)
                    if !loc.address.isEmpty {
                        Text(loc.name)
                            .font(.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
                Spacer()
                Text("Change")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewAccent)
            }
            .padding(14)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(RoamColors.reviewSuccess, lineWidth: 1.5)
            )
        } else {
            // No location yet
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(RoamColors.reviewAccent.opacity(0.08))
                        .frame(width: 36, height: 36)
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 14))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Search or drop a pin")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                    Text("Find the address or place on the map")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMuted.opacity(0.7))
                }
                Spacer()
                Text("Add →")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewAccent)
            }
            .padding(14)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(RoamColors.reviewBorder)
            )
        }
    }

    @ViewBuilder
    private func fieldSection<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(RoamFont.mono(10, weight: .semibold))
                .foregroundStyle(RoamColors.textMuted)
                .tracking(0.8)
            content()
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
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                placeId: pickedLocation?.placeId
            )
            dismiss()
            onDone()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
