import SwiftUI
import UIKit

private enum MainTab: Int, CaseIterable {
    case ideas = 0
    case drafts = 1
    case plans = 2
    case map = 3
    case reels = 4

    var symbol: String {
        switch self {
        case .ideas: return "◌"
        case .drafts: return "⊟"
        case .plans: return "⊕"
        case .map: return "◎"
        case .reels: return "▦"
        }
    }

    var label: String {
        switch self {
        case .ideas: return "ideas"
        case .drafts: return "drafts"
        case .plans: return "plans"
        case .map: return "map"
        case .reels: return "reels"
        }
    }
}

struct MainTabShell: View {
    let apiClient: APIClient
    @Binding var showDebugMenu: Bool
    @EnvironmentObject private var shareIngress: ShareIngressCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var stores: RoamStores
    @State private var bootstrapped = false
    @State private var tab: MainTab = .ideas
    @State private var showInbox = false
    @State private var showProfile = false
    @State private var navigationPathIdeas = NavigationPath()

    init(apiClient: APIClient, showDebugMenu: Binding<Bool>) {
        self.apiClient = apiClient
        _showDebugMenu = showDebugMenu
        _stores = State(initialValue: RoamStores(api: apiClient))
    }

    var body: some View {
        Group {
            if bootstrapped {
                shell(stores: stores)
                    .environment(\.roamStores, stores)
            } else {
                ProgressView("Loading…")
                    .task {
                        await stores.refreshAll()
                        bootstrapped = true
                    }
            }
        }
    }

    @ViewBuilder
    private func shell(stores: RoamStores) -> some View {
        VStack(spacing: 0) {
            RoamTopBar(
                user: stores.user.me,
                unreadNotifications: stores.notifications.unreadCount,
                onNotifications: { showInbox = true },
                onProfile: { showProfile = true },
                onAppConfig: debugAppConfigAction
            )

            ZStack {
                RoamColors.background.ignoresSafeArea()
                DotGridBackground(dotOpacity: 0.28)
                    .ignoresSafeArea()

                if let err = shareIngress.lastError, !err.isEmpty {
                    VStack {
                        HStack(alignment: .top, spacing: 8) {
                            Text(err)
                                .font(RoamFont.mono(10))
                                .foregroundStyle(RoamColors.error)
                                .multilineTextAlignment(.leading)
                            Button("OK") {
                                shareIngress.dismissError()
                            }
                            .font(RoamFont.mono(10, weight: .medium))
                            .foregroundStyle(RoamColors.loganDeep)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoamColors.background.opacity(0.92))
                        Spacer()
                    }
                    .zIndex(2)
                }

                Group {
                    switch tab {
                    case .ideas:
                        NavigationStack(path: $navigationPathIdeas) {
                            IdeasPage {
                                tab = .reels
                            }
                            .navigationDestination(for: String.self) { id in
                                IdeaDetailPage(ideaId: id)
                            }
                        }
                    case .drafts:
                        NavigationStack {
                            DraftsPage()
                        }
                    case .plans:
                        NavigationStack {
                            PlansPage()
                        }
                    case .map:
                        NavigationStack {
                            MapPage()
                        }
                    case .reels:
                        ReelsPage()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            glassTabBar(stores: stores)
        }
        .preferredColorScheme(.light)
        .onAppear {
            if shareIngress.pendingSwitchToReels {
                tab = .reels
                shareIngress.clearPendingSwitchToReels()
            }
        }
        .sheet(isPresented: $showInbox) {
            NavigationStack {
                InboxPage()
                    .environment(\.roamStores, stores)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showInbox = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showProfile) {
            ProfilePage(onDismiss: { showProfile = false })
                .environment(\.roamStores, stores)
        }
        .onChange(of: tab) { oldTab, newTab in
            if oldTab == .ideas && newTab != .ideas {
                navigationPathIdeas = NavigationPath()
            }
        }
        .onChange(of: bootstrapped) { _, ok in
            if ok {
                Task {
                    await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
                    await shareIngress.runIfNeeded(apiClient: apiClient, stores: stores)
                    shareIngress.ensurePollingForProcessingReels(apiClient: apiClient, stores: stores)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, bootstrapped {
                Task {
                    await shareIngress.flushShareQueue(apiClient: apiClient, stores: stores)
                    await shareIngress.runIfNeeded(apiClient: apiClient, stores: stores)
                    shareIngress.ensurePollingForProcessingReels(apiClient: apiClient, stores: stores)
                }
            }
        }
        .onChange(of: shareIngress.pendingSwitchToReels) { _, go in
            if go {
                tab = .reels
                shareIngress.clearPendingSwitchToReels()
            }
        }
    }

    /// DEBUG-only: opens bundled `AppConfig` / API environment sheet (centered in `RoamTopBar`).
    private var debugAppConfigAction: (() -> Void)? {
        #if DEBUG
        { showDebugMenu = true }
        #else
        nil
        #endif
    }

    private func glassTabBar(stores: RoamStores) -> some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases, id: \.rawValue) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        if tab == item {
                            Circle()
                                .fill(RoamColors.loganDark)
                                .frame(width: 4, height: 4)
                        } else {
                            Spacer().frame(height: 4)
                        }
                        Text(item.symbol)
                            .font(.system(size: 22))
                            .foregroundStyle(tab == item ? RoamColors.loganDark : RoamColors.logan)
                        Text(item.label)
                            .font(RoamFont.mono(11, weight: .medium))
                            .foregroundStyle(tab == item ? RoamColors.loganDark : RoamColors.lavDeep)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .overlay(alignment: .topTrailing) {
                        if item == .drafts, stores.plans.drafts.count > 0 {
                            Text(stores.plans.drafts.count > 99 ? "99+" : "\(stores.plans.drafts.count)")
                                .font(RoamFont.mono(9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, stores.plans.drafts.count > 9 ? 4 : 0)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(RoamColors.loganDark)
                                .clipShape(Capsule())
                                .offset(x: -8, y: 4)
                        }
                        if item == .reels, stores.reels.needsReviewCount > 0 {
                            Text(stores.reels.needsReviewCount > 99 ? "99+" : "\(stores.reels.needsReviewCount)")
                                .font(RoamFont.mono(9, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, stores.reels.needsReviewCount > 9 ? 4 : 0)
                                .frame(minWidth: 14, minHeight: 14)
                                .background(RoamColors.loganDeep)
                                .clipShape(Capsule())
                                .offset(x: -8, y: 4)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 56)
        .background {
            GlassBarBackground()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RoamColors.logan.opacity(0.15))
                .frame(height: 1 / UIScreen.main.scale)
        }
    }
}
