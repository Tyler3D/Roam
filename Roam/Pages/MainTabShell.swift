import SwiftUI
import UIKit

private enum MainTab: Int, CaseIterable {
    case ideas = 0
    case drafts = 1
    case plans = 2
    case map = 3
    case reels = 4

    /// SF Symbols matching product tab bar (outline / line style).
    var sfSymbol: String {
        switch self {
        case .ideas: return "sun.max"
        case .drafts: return "square.grid.2x2"
        case .plans: return "clock"
        case .map: return "mappin.circle"
        case .reels: return "film.stack"
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
    @Environment(AppConfig.self) private var appConfig
    @Environment(DeepLinkRouter.self) private var deepLinkRouter
    @EnvironmentObject private var shareIngress: ShareIngressCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var stores: RoamStores
    @State private var bootstrapped = false
    @State private var tab: MainTab = .ideas
    @State private var showInbox = false
    @State private var showProfile = false
    @State private var showFriendsFromInvite = false
    @State private var invitePrefilledUsername: String?
    @State private var navigationPathIdeas = NavigationPath()
    @State private var navigationPathConsumerIdeas = NavigationPath()

    init(apiClient: APIClient, showDebugMenu: Binding<Bool>) {
        self.apiClient = apiClient
        _showDebugMenu = showDebugMenu
        _stores = State(initialValue: RoamStores(api: apiClient))
    }

    /// Drafts + Plans tabs only in alpha; regular `mainRoam` shows Ideas, Map, Reels.
    private var showsDraftsAndPlansTabs: Bool {
        appConfig.appMode == .alphaHeavyDevelopmentUnsafe
    }

    private var visibleTabs: [MainTab] {
        if showsDraftsAndPlansTabs {
            return Array(MainTab.allCases)
        }
        return [.ideas, .map, .reels]
    }

    var body: some View {
        Group {
            if bootstrapped {
                shell(stores: stores)
                    .environment(\.roamStores, stores)
            } else {
                SplashScreen(status: "Loading…")
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
                        if showsDraftsAndPlansTabs {
                            NavigationStack(path: $navigationPathIdeas) {
                                IdeasPage {
                                    tab = .reels
                                }
                                .navigationDestination(for: String.self) { id in
                                    IdeaDetailPage(ideaId: id)
                                }
                            }
                        } else {
                            NavigationStack(path: $navigationPathConsumerIdeas) {
                                ConsumerIdeasHomePage {
                                    tab = .reels
                                }
                                .navigationDestination(for: ConsumerIdeaDetailRoute.self) { route in
                                    ConsumerIdeaDetailPage(route: route)
                                }
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

            mainTabBar(stores: stores)
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
        .sheet(isPresented: $showFriendsFromInvite) {
            NavigationStack {
                FriendsPage(initialTab: .myFriends, prefilledUsername: invitePrefilledUsername)
                    .environment(\.roamStores, stores)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showFriendsFromInvite = false }
                        }
                    }
            }
        }
        .onChange(of: tab) { oldTab, newTab in
            if oldTab == .ideas && newTab != .ideas {
                navigationPathIdeas = NavigationPath()
                navigationPathConsumerIdeas = NavigationPath()
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
        .onChange(of: appConfig.appMode) { _, newMode in
            navigationPathIdeas = NavigationPath()
            navigationPathConsumerIdeas = NavigationPath()
            if newMode != .alphaHeavyDevelopmentUnsafe, tab == .drafts || tab == .plans {
                tab = .ideas
            }
        }
        .onChange(of: deepLinkRouter.pending) { _, destination in
            guard let destination else { return }
            handleDeepLink(destination)
            deepLinkRouter.pending = nil
        }
    }

    private func handleDeepLink(_ destination: DeepLinkDestination) {
        switch destination {
        case .reels:
            tab = .reels
        case .ideaDetail(let ideaId):
            navigationPathConsumerIdeas = NavigationPath()
            navigationPathIdeas = NavigationPath()
            tab = .ideas
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if showsDraftsAndPlansTabs {
                    navigationPathIdeas.append(ideaId)
                } else {
                    navigationPathConsumerIdeas.append(ConsumerIdeaDetailRoute(ideaId: ideaId))
                }
            }
        case .map:
            tab = .map
        case .profile:
            showProfile = true
        case .ideas:
            tab = .ideas
        case .friends(let username):
            invitePrefilledUsername = username
            showFriendsFromInvite = true
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

    private func mainTabBar(stores: RoamStores) -> some View {
        let accent = RoamColors.reviewAccent
        let inactive = Color(red: 118 / 255, green: 124 / 255, blue: 140 / 255)

        return VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1 / max(UIScreen.main.scale, 1))

            HStack(spacing: 0) {
                ForEach(visibleTabs, id: \.rawValue) { item in
                    let selected = tab == item
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: item.sfSymbol)
                                    .font(.system(size: 23, weight: .regular))
                                    .symbolRenderingMode(.monochrome)
                                    .foregroundStyle(selected ? accent : inactive)
                                    .frame(width: 28, height: 24)

                                if item == .drafts, stores.plans.drafts.count > 0 {
                                    tabBadge(
                                        count: stores.plans.drafts.count,
                                        accent: accent
                                    )
                                    .offset(x: 10, y: -8)
                                }
                                if item == .reels, stores.reels.needsReviewCount > 0 {
                                    tabBadge(
                                        count: stores.reels.needsReviewCount,
                                        accent: accent
                                    )
                                    .offset(x: 10, y: -8)
                                }
                            }

                            Text(item.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(selected ? accent : inactive)
                                .textCase(.uppercase)
                                .tracking(0.6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)
                        .padding(.bottom, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background {
            Color.white
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabBadge(count: Int, accent: Color) -> some View {
        let text = count > 99 ? "99+" : "\(count)"
        return Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(accent))
    }
}
