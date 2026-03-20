import SwiftUI

struct ReelDetailPage: View {
    let reelId: String

    private static let maxIngestRetries = 5

    @Environment(\.apiClient) private var apiClient
    @Environment(\.roamStores) private var stores
    @State private var detail: APIClient.SavedReelDetailDTO?
    @State private var loadError: String?
    @State private var titleEdits: [UUID: String] = [:]
    @State private var locationQueries: [UUID: String] = [:]
    @State private var isPromoting = false
    @State private var promoteError: String?
    @State private var showOriginalSuggestions = false
    @State private var showAddIdea = false
    @State private var isRetryingIngest = false
    @State private var retryIngestError: String?

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
        .navigationTitle("reel")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("add idea") { showAddIdea = true }
                    .font(RoamFont.mono(10, weight: .medium))
                    .disabled(detail == nil || detail?.status == "processing")
            }
        }
        .sheet(isPresented: $showAddIdea) {
            if let d = detail {
                AddReelIdeaSheet(reelId: reelId) {
                    showAddIdea = false
                    Task {
                        await stores.ideas.refresh()
                        await load()
                    }
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func content(_ d: APIClient.SavedReelDetailDTO) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if d.jobStatus == "failed" || d.status == "failed" {
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
                                    ProgressView()
                                        .scaleEffect(0.85)
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

                if let rid = UUID(uuidString: reelId) {
                    ReelThumbnailImageView(reelId: rid, signedUrl: d.thumbnailSignedUrl, contentMode: .fit)
                        .frame(maxHeight: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                Text(d.title.isEmpty ? d.reelUrl : d.title)
                    .font(RoamFont.mono(12, weight: .medium))
                    .foregroundStyle(RoamColors.loganDark)

                if d.status == "needs_review", d.ideasNonEmpty.isEmpty {
                    Text("Nothing matched—tap add idea to create one yourself.")
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.textMuted)
                }

                ideasSection(d)

                if !d.candidates.isEmpty {
                    DisclosureGroup(isExpanded: $showOriginalSuggestions) {
                        candidatesSection(d, readOnly: pendingCandidates(d).isEmpty)
                    } label: {
                        Text("original model suggestions")
                            .font(RoamFont.mono(10, weight: .medium))
                            .foregroundStyle(RoamColors.textMuted)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                }

                if canPromotePending(d) {
                    if let promoteError {
                        Text(promoteError)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.error)
                    }
                    Button {
                        Task { await promote(d) }
                    } label: {
                        if isPromoting {
                            ProgressView()
                        } else {
                            Text("promote suggestions to ideas")
                                .font(RoamFont.mono(11, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RoamColors.loganDeep)
                    .disabled(isPromoting || pendingCandidates(d).isEmpty)
                }
            }
            .padding(16)
        }
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
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func promote(_ d: APIClient.SavedReelDetailDTO) async {
        promoteError = nil
        isPromoting = true
        defer { isPromoting = false }
        let pending = pendingCandidates(d)
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
        do {
            _ = try await apiClient.promoteReel(reelId: reelId, promotions: items)
            await stores.ideas.refresh()
            await stores.reels.refresh()
            await load()
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
            _ = try await apiClient.retryFailedReelIngest(
                reelId: reelId,
                shareText: nil,
                reelTitle: pack.ingestReelTitle,
                ogDescription: pack.ingestOgDescription,
                ogKeywords: pack.ingestOgKeywords,
                thumbnailJPEG: pack.thumbnailJPEG,
                frameJPEGs: pack.frameJPEGs
            )
            await load()
            await stores.reels.refresh()
        } catch {
            retryIngestError = error.localizedDescription
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
