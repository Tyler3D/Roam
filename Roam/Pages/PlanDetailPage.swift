import SwiftUI

struct PlanDetailPage: View {
    let planId: String
    @Environment(\.apiClient) private var apiClient
    @State private var plan: Plan?
    @State private var isLoading = true
    @State private var errorText: String?

    var body: some View {
        Group {
            if let plan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(plan.title)
                            .font(RoamFont.display(22, italic: true))
                            .foregroundStyle(RoamColors.text)
                        Text(plan.status.rawValue)
                            .font(RoamFont.mono(9, weight: .medium))
                            .foregroundStyle(RoamColors.loganDeep)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        if let at = plan.scheduledAt {
                            Text(at.formatted(date: .long, time: .shortened))
                                .font(RoamFont.mono(11))
                                .foregroundStyle(RoamColors.textMid)
                        }
                        if let place = plan.placeName, !place.isEmpty {
                            Text(place)
                                .font(RoamFont.notes(14, italic: true))
                                .foregroundStyle(RoamColors.loganDark)
                        }
                        if !plan.taskNotes.isEmpty {
                            Text(plan.taskNotes)
                                .font(RoamFont.mono(11))
                                .foregroundStyle(RoamColors.textMid)
                        }
                        Text("Share code: \(plan.shareCode)")
                            .font(RoamFont.mono(9))
                            .foregroundStyle(RoamColors.textMuted)
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
        .navigationTitle("plan")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            plan = try await apiClient.getPlan(id: planId)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
