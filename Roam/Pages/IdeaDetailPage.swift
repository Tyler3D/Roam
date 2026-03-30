import SwiftUI

struct IdeaDetailPage: View {
    let ideaId: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roamStores) private var stores
    @Environment(\.apiClient) private var apiClient
    @Environment(AppConfig.self) private var appConfig
    @State private var idea: Idea?
    @State private var isLoading = true
    @State private var errorText: String?
    @State private var isWorking = false

    var body: some View {
        Group {
            if let idea {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection(idea)
                        if let pr = idea.pipelineResult {
                            enrichedSection(pr, idea: idea)
                        }
                        if let errorText {
                            Text(errorText)
                                .font(RoamFont.mono(10))
                                .foregroundStyle(RoamColors.error)
                        }
                        actionButtons(idea)
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

    // MARK: - Sections

    @ViewBuilder
    private func headerSection(_ idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline(for: idea))
                .font(RoamFont.display(24, italic: true))
                .foregroundStyle(RoamColors.text)

            if idea.status == .suggesting {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(RoamColors.loganDeep)
                    Text("enriching…")
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.loganDeep)
                }
            }

            if !idea.notes.isEmpty {
                Text(idea.notes)
                    .font(RoamFont.mono(12))
                    .foregroundStyle(RoamColors.textMid)
            }
        }
    }

    @ViewBuilder
    private func enrichedSection(_ pr: PipelineResult, idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category + estimated time row
            HStack(spacing: 10) {
                if let cat = pr.category, !cat.isEmpty {
                    categoryChip(cat)
                }
                if let mins = pr.estimatedMinutes, mins > 0 {
                    Text("~\(formattedDuration(mins))")
                        .font(RoamFont.mono(9, weight: .medium))
                        .foregroundStyle(RoamColors.loganDark)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoamColors.lavender.opacity(0.5))
                        .clipShape(Capsule())
                }
                if let pref = preferenceLabel(pr) {
                    Text(pref)
                        .font(RoamFont.mono(9))
                        .foregroundStyle(RoamColors.textMuted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoamColors.surface)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(RoamColors.logan.opacity(0.2), lineWidth: 1)
                        )
                }
                Spacer(minLength: 0)
            }

            // Place name + address
            if let place = idea.placeName, !place.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Label(place, systemImage: "mappin.circle.fill")
                        .font(RoamFont.notes(14, italic: true))
                        .foregroundStyle(RoamColors.loganDeep)
                    if let addr = ideaAddress(idea), !addr.isEmpty {
                        Text(addr)
                            .font(RoamFont.mono(10))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoamColors.lavender.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // Suggested datetime
            if let dt = suggestedDatetime(pr) {
                Label(dt, systemImage: "calendar")
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.loganDark)
            }

            // Invitees
            let invitees = resolvedInvitees(pr)
            if !invitees.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("with")
                        .font(RoamFont.mono(8, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(invitees.joined(separator: ", "))
                        .font(RoamFont.notes(13, italic: true))
                        .foregroundStyle(RoamColors.text)
                }
            }

            // Task assignments
            if let raw = pr.rawOutput as? [String: Any],
               let tasks = raw["taskAssignments"] as? String, !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("tasks")
                        .font(RoamFont.mono(8, weight: .medium))
                        .foregroundStyle(RoamColors.textMuted)
                        .textCase(.uppercase)
                        .tracking(1)
                    Text(tasks)
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMid)
                }
            }
        }
        .padding(14)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.logan.opacity(0.18), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func actionButtons(_ idea: Idea) -> some View {
        let alreadyEnriched = idea.pipelineResult != nil && idea.status == .ready

        VStack(spacing: 10) {
            Button {
                Task { await enrich() }
            } label: {
                Label(alreadyEnriched ? "Re-enrich" : "Enrich", systemImage: "sparkles")
                    .font(RoamFont.mono(11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(alreadyEnriched ? RoamColors.loganDark : RoamColors.loganDeep)
            .disabled(isWorking)

            if appConfig.appMode == .alphaHeavyDevelopmentUnsafe {
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
            }

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
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private func headline(for idea: Idea) -> String {
        if let d = idea.displayName, !d.isEmpty { return d }
        return idea.title
    }

    private func ideaAddress(_ idea: Idea) -> String? {
        // Address is not on the Idea model directly; placeName is the venue,
        // so we leave this for future when placeAddress is surfaced on IdeaRead.
        nil
    }

    private func categoryChip(_ category: String) -> some View {
        let label = category.replacingOccurrences(of: "-", with: " ")
        return Text(label)
            .font(RoamFont.mono(8, weight: .medium))
            .foregroundStyle(RoamColors.loganDark)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoamColors.lavender.opacity(0.65))
            .clipShape(Capsule())
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func preferenceLabel(_ pr: PipelineResult) -> String? {
        guard let raw = pr.rawOutput as? [String: Any],
              let pref = raw["preference"] as? String,
              pref != "any", !pref.isEmpty else { return nil }
        let labels: [String: String] = [
            "morning": "Best in the morning",
            "afternoon": "Best in the afternoon",
            "evening": "Best in the evening",
            "weekend": "Best on a weekend",
        ]
        return labels[pref]
    }

    private func suggestedDatetime(_ pr: PipelineResult) -> String? {
        guard let raw = pr.rawOutput as? [String: Any],
              let iso = raw["specificDatetime"] as? String,
              !iso.isEmpty else { return nil }
        let df = ISO8601DateFormatter()
        guard let date = df.date(from: iso) else { return iso }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func resolvedInvitees(_ pr: PipelineResult) -> [String] {
        guard let raw = pr.rawOutput as? [String: Any],
              let resolved = raw["resolvedInvitees"] as? [[String: Any]] else { return [] }
        return resolved.compactMap { dict -> String? in
            if let firstName = dict["firstName"] as? String {
                let last = dict["lastName"] as? String ?? ""
                return last.isEmpty ? firstName : "\(firstName) \(last)"
            }
            return dict["name"] as? String
        }
    }

    // MARK: - Actions

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

    /// Reel ingest creates the idea in `suggesting` before the vision job finishes; poll with backoff until pipeline data arrives.
    private func pollWhileReelSuggesting() async {
        guard let start = idea, start.status == .suggesting, start.pipelineResult == nil else { return }
        var interval: UInt64 = 1_000_000_000  // start at 1s
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: interval)
            interval = min(interval * 2, 5_000_000_000)  // cap at 5s
            guard let reloaded = try? await apiClient.getIdea(id: ideaId) else { continue }
            idea = reloaded
            stores.ideas.replaceLocal(reloaded)
            if reloaded.pipelineResult != nil || reloaded.status != .suggesting { break }
        }
    }

    private func enrich() async {
        isWorking = true
        errorText = nil
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
