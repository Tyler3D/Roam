import SwiftUI
import UIKit

struct IdeasPage: View {
    @Environment(\.roamStores) private var stores
    @State private var input = ""
    @State private var enrichingIds: Set<String> = []
    @State private var submitError: String?
    @FocusState private var inputFocused: Bool

    /// When set, shows a banner to jump to the Reels tab when reels need review.
    var onSwitchToReels: (() -> Void)?

    init(onSwitchToReels: (() -> Void)? = nil) {
        self.onSwitchToReels = onSwitchToReels
    }

    var body: some View {
        content(stores: stores)
    }

    @ViewBuilder
    private func content(stores: RoamStores) -> some View {
        let nextUp = stores.plans.upcomingConfirmed().first

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if stores.ideas.isLoading && stores.ideas.ideas.isEmpty {
                    ProgressView("loading ideas…")
                        .font(RoamFont.mono(11))
                        .tint(RoamColors.loganDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else if let err = stores.ideas.lastError, stores.ideas.ideas.isEmpty {
                    Text(err)
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.error)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    Button("Retry") {
                        Task { await stores.ideas.refresh() }
                    }
                    .font(RoamFont.mono(11))
                }

                if let plan = nextUp {
                    nextUpCard(plan: plan)
                }

                if stores.reels.needsReviewCount > 0, let go = onSwitchToReels {
                    Button {
                        go()
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Text("▦")
                                .font(.system(size: 18))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(stores.reels.needsReviewCount) reel(s) to review")
                                    .font(RoamFont.mono(11, weight: .medium))
                                Text("open reels to turn suggestions into ideas")
                                    .font(RoamFont.mono(9))
                                    .foregroundStyle(RoamColors.textMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(RoamColors.loganDeep)
                        }
                        .foregroundStyle(RoamColors.loganDark)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoamColors.lavender.opacity(0.9))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(RoamColors.logan.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                if stores.ideas.ideas.isEmpty && !stores.ideas.isLoading && stores.ideas.lastError == nil {
                    IdeasReelOnboardingEmptyState()
                }

                if let submitError {
                    Text(submitError)
                        .font(RoamFont.mono(10))
                        .foregroundStyle(RoamColors.error)
                }

                ForEach(Array(stores.ideas.ideas.enumerated()), id: \.element.id) { index, idea in
                    NavigationLink(value: idea.id) {
                        ZStack {
                            IdeaCardView(idea: idea)
                            if enrichingIds.contains(idea.id) {
                                Color.white.opacity(0.35)
                                ProgressView()
                                    .scaleEffect(0.9)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(enrichingIds.contains(idea.id))
                    .onAppear {
                        if index == stores.ideas.ideas.count - 1 {
                            Task { await stores.ideas.loadMore() }
                        }
                    }
                }
                if stores.ideas.isLoadingMore {
                    ProgressView()
                        .tint(RoamColors.loganDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .refreshable {
            await stores.ideas.refresh()
            await stores.plans.refresh()
            await stores.reels.refreshSummaryOnly()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            commandBar(stores: stores)
        }
        .task {
            await stores.ideas.loadIfStale()
            await stores.plans.loadIfStale()
            await stores.reels.refreshSummaryOnly()
        }
    }

    private func nextUpCard(plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("next up · tap in plans")
                .font(RoamFont.mono(8, weight: .medium))
                .foregroundStyle(RoamColors.loganDeep)
                .textCase(.uppercase)
                .tracking(2)
            Text(plan.title)
                .font(RoamFont.display(20, italic: true))
                .foregroundStyle(RoamColors.text)
            Text(PlanFormatting.nextUpSubtitle(plan: plan))
                .font(RoamFont.mono(10))
                .foregroundStyle(RoamColors.loganDark)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [RoamColors.lavender, RoamColors.notifDot.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(RoamColors.logan.opacity(0.28), lineWidth: 1)
        )
        .overlay {
            DotGridBackground(dotOpacity: 0.12)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(false)
        }
    }

    private func commandBar(stores: RoamStores) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("◌ plan something")
                .font(RoamFont.mono(8, weight: .medium))
                .foregroundStyle(RoamColors.textMuted)
                .textCase(.uppercase)
                .tracking(2)
            HStack(spacing: 10) {
                TextField("what are we doing…", text: $input, axis: .vertical)
                    .font(RoamFont.notes(14, italic: true))
                    .foregroundStyle(RoamColors.textMid)
                    .lineLimit(1...3)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit { Task { await submit(stores: stores) } }
                Button {
                    Task { await submit(stores: stores) }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            LinearGradient(
                                colors: [RoamColors.loganDeep, RoamColors.loganDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())
                        .shadow(color: RoamColors.loganDark.opacity(0.28), radius: 6, y: 3)
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoamColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(RoamColors.logan.opacity(0.28), lineWidth: 1)
            )
            .shadow(color: RoamColors.loganDark.opacity(0.07), radius: 8, y: 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background {
            GlassBarBackground()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RoamColors.logan.opacity(0.15))
                .frame(height: 1 / UIScreen.main.scale)
        }
    }

    private func submit(stores: RoamStores) async {
        let title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        input = ""
        inputFocused = false
        submitError = nil
        do {
            let created = try await stores.ideas.createIdea(title: title)
            enrichingIds.insert(created.id)
            defer { enrichingIds.remove(created.id) }
            try await stores.ideas.interpretIdea(id: created.id)
            await stores.plans.refresh()
        } catch {
            submitError = error.localizedDescription
        }
    }
}
