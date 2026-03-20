import SwiftUI

struct IdeaDetailPage: View {
    let ideaId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roamStores) private var stores
    @Environment(\.apiClient) private var apiClient
    @State private var idea: Idea?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        Group {
            if let idea {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(headline(for: idea))
                            .font(RoamFont.display(24, italic: true))
                            .foregroundStyle(RoamColors.text)
                        Text(idea.status.rawValue)
                            .font(RoamFont.mono(9, weight: .medium))
                            .foregroundStyle(RoamColors.loganDeep)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        if !idea.notes.isEmpty {
                            Text(idea.notes)
                                .font(RoamFont.mono(12))
                                .foregroundStyle(RoamColors.textMid)
                        }
                        if let pr = idea.pipelineResult {
                            if let t = pr.refinedTitle {
                                Text("Refined: \(t)")
                                    .font(RoamFont.mono(11))
                                    .foregroundStyle(RoamColors.loganDark)
                            }
                            if let c = pr.category {
                                Text("Category: \(c)")
                                    .font(RoamFont.mono(10))
                                    .foregroundStyle(RoamColors.textMuted)
                            }
                        }
                        if let place = idea.placeName {
                            Text(place)
                                .font(RoamFont.notes(14, italic: true))
                                .foregroundStyle(RoamColors.loganDeep)
                        }

                        VStack(spacing: 10) {
                            Button {
                                Task { await enrich() }
                            } label: {
                                Label("Enrich", systemImage: "sparkles")
                                    .font(RoamFont.mono(11, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(RoamColors.loganDeep)
                            .disabled(isWorking)

                            Button {
                                Task { await promote() }
                            } label: {
                                Label("Promote to plan", systemImage: "calendar.badge.plus")
                                    .font(RoamFont.mono(11, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.bordered)
                            .tint(RoamColors.loganDark)
                            .disabled(isWorking)

                            Button(role: .destructive) {
                                Task { await deleteIdea() }
                            } label: {
                                Label("Delete idea", systemImage: "trash")
                                    .font(RoamFont.mono(11, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .disabled(isWorking)
                        }
                        .padding(.top, 8)
                    }
                    .padding(20)
                }
            } else if isLoading {
                ProgressView("Loading…")
                    .tint(RoamColors.loganDeep)
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
        .task {
            await load()
            await pollWhileReelSuggesting()
        }
    }

    private func headline(for idea: Idea) -> String {
        if let d = idea.displayName, !d.isEmpty { return d }
        return idea.title
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let loaded = try await apiClient.getIdea(id: ideaId)
            idea = loaded
            stores.ideas.replaceLocal(loaded)
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// Reel ingest creates the idea in `suggesting` before the vision job finishes; refresh until pipeline data arrives.
    private func pollWhileReelSuggesting() async {
        guard let start = idea, start.status == .suggesting, start.pipelineResult == nil else { return }
        for _ in 0..<120 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard let reloaded = try? await apiClient.getIdea(id: ideaId) else { continue }
            idea = reloaded
            stores.ideas.replaceLocal(reloaded)
            if reloaded.pipelineResult != nil || reloaded.status != .suggesting {
                break
            }
        }
    }

    private func enrich() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await stores.ideas.interpretIdea(id: ideaId)
            idea = stores.ideas.ideas.first { $0.id == ideaId }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func promote() async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await stores.ideas.promoteIdea(id: ideaId)
            await stores.plans.refresh()
            idea = stores.ideas.ideas.first { $0.id == ideaId }
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteIdea() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await stores.ideas.deleteIdea(id: ideaId)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
