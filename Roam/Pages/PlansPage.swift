import SwiftUI

private enum PlansSegment: String, CaseIterable {
    case upcoming = "Upcoming"
    case past = "Past"
    case calendar = "Calendar"
}

struct PlansPage: View {
    @Environment(\.roamStores) private var stores
    @State private var segment: PlansSegment = .upcoming

    var body: some View {
        content(stores: stores)
            .navigationTitle("plans")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func content(stores: RoamStores) -> some View {
        let upcoming = stores.plans.upcomingConfirmed()
        let past = stores.plans.pastConfirmed()
        let list: [Plan] = segment == .upcoming ? upcoming : (segment == .past ? past : [])

        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PlansSegment.allCases, id: \.self) { tab in
                        Button {
                            segment = tab
                        } label: {
                            HStack(spacing: 4) {
                                Text(tab.rawValue.uppercased())
                                    .font(RoamFont.mono(10, weight: .medium))
                                    .tracking(1.5)
                                if tab == .upcoming, upcoming.count > 0 {
                                    Text("\(upcoming.count)")
                                        .font(RoamFont.mono(9))
                                } else if tab == .past, past.count > 0 {
                                    Text("\(past.count)")
                                        .font(RoamFont.mono(9))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                segment == tab
                                    ? RoamColors.lavender
                                    : Color.clear
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(
                                        segment == tab ? RoamColors.loganDeep.opacity(0.5) : RoamColors.logan.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(segment == tab ? RoamColors.loganDeep : RoamColors.textMid)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            if stores.plans.isLoading && stores.plans.plans.isEmpty {
                ProgressView("loading plans…")
                    .font(RoamFont.mono(11))
                    .tint(RoamColors.loganDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
            } else if stores.plans.plans.isEmpty {
                RoamEmptyState(
                    icon: "📋",
                    title: "no plans yet",
                    subtitle: "promote an idea to create your first plan"
                )
            } else if segment == .calendar {
                RoamEmptyState(
                    icon: "📅",
                    title: "calendar",
                    subtitle: "coming soon — use the web app for calendar view"
                )
            } else if list.isEmpty {
                RoamEmptyState(
                    icon: "◎",
                    title: segment == .upcoming ? "nothing upcoming" : "no past plans",
                    subtitle: "plans you confirm with a date appear here"
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(list) { plan in
                            NavigationLink(value: plan.id) {
                                PlanCardView(plan: plan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            PlanDetailPage(planId: id)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .refreshable { await stores.plans.refresh() }
        .task { await stores.plans.loadIfStale() }
    }
}
