import SwiftUI

struct DraftsPage: View {
    @Environment(\.roamStores) private var stores

    var body: some View {
        content(stores: stores)
            .navigationTitle("drafts")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(stores: RoamStores) -> some View {
        ScrollView {
            if stores.plans.isLoading && stores.plans.drafts.isEmpty {
                ProgressView("loading drafts…")
                    .font(RoamFont.mono(11))
                    .tint(RoamColors.loganDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else if stores.plans.drafts.isEmpty {
                RoamEmptyState(
                    icon: "◈",
                    title: "no drafts",
                    subtitle: "tap an idea to start planning"
                )
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(stores.plans.drafts) { plan in
                        NavigationLink(value: plan.id) {
                            PlanCardView(plan: plan)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationDestination(for: String.self) { id in
            PlanDetailPage(planId: id)
        }
        .refreshable { await stores.plans.refresh() }
        .task { await stores.plans.loadIfStale() }
    }
}
