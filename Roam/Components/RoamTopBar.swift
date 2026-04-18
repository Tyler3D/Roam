import SwiftUI
import UIKit

/// Same list content as the profile "collections" destination; exposed here for the home top bar sheet.
private typealias CollectionsListView = AllProfileCollectionsPage

/// Compact header aligned with [frontend/src/components/TopBar.tsx](frontend/src/components/TopBar.tsx).
struct RoamTopBar: View {
    @Environment(AppConfig.self) private var appConfig
    @Environment(\.apiClient) private var api
    @Environment(\.roamStores) private var stores

    let user: RoamUser?
    let unreadNotifications: Int
    var onNotifications: () -> Void
    /// Left cluster (avatar + branding). Reserved for a future profile experience; may still open profile today.
    var onProfile: () -> Void
    /// Centered control (e.g. DEBUG app config). Omit in release builds.
    var onAppConfig: (() -> Void)? = nil

    @State private var showCollectionsSheet = false
    @State private var showFriendsSheet = false
    @State private var friendsCountForBadge = 0

    private let circleButtonSize: CGFloat = 36
    private let accentBorder = Color(red: 127 / 255, green: 119 / 255, blue: 221 / 255)
    private let collectionBadgeFill = Color(red: 245 / 255, green: 158 / 255, blue: 66 / 255)

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onProfile) {
                    HStack(spacing: 10) {
                        RoamAvatar(initials: initials(for: user), photoUrl: user?.photoUrl, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("roam")
                                .font(RoamFont.display(22, italic: true))
                                .foregroundStyle(RoamColors.text)
                            if let line = subtitleLine(for: user) {
                                Text(line)
                                    .font(RoamFont.mono(9, weight: .regular))
                                    .foregroundStyle(RoamColors.textMuted)
                                    .textCase(.uppercase)
                                    .tracking(1)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    topBarCircleButton(
                        systemImage: "square.grid.2x2",
                        badgeCount: collectionsWithUnseenUpdatesCount,
                        badgeStyle: .amber
                    ) {
                        showCollectionsSheet = true
                    }
                    .accessibilityLabel("Collections")

                    topBarCircleButton(
                        systemImage: "person.2.fill",
                        badgeCount: friendsCountForBadge,
                        badgeStyle: .purpleAccent
                    ) {
                        showFriendsSheet = true
                    }
                    .accessibilityLabel("Friends")
                }

                if appConfig.appMode == .alphaHeavyDevelopmentUnsafe {
                    Button(action: onNotifications) {
                        ZStack(alignment: .topTrailing) {
                            Text("◎")
                                .font(.system(size: 22))
                                .foregroundStyle(RoamColors.loganDeep)
                            if unreadNotifications > 0 {
                                Circle()
                                    .fill(RoamColors.notifDot)
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                                    .offset(x: 4, y: -2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Notifications")
                }
            }

            if let onAppConfig {
                Button(action: onAppConfig) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(RoamColors.loganDeep)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("App configuration")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                RoamColors.background.opacity(0.85)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(RoamColors.logan.opacity(0.15))
                .frame(height: 1 / UIScreen.main.scale)
        }
        .sheet(isPresented: $showCollectionsSheet) {
            NavigationStack {
                CollectionsListView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showCollectionsSheet = false }
                        }
                    }
                    .navigationDestination(for: ProfileNav.self) { dest in
                        profileNavDestination(dest)
                    }
            }
            .environment(\.roamStores, stores)
            .environment(\.apiClient, api)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFriendsSheet) {
            NavigationStack {
                FriendsPage(initialTab: .myFriends, prefilledUsername: nil)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showFriendsSheet = false }
                        }
                    }
            }
            .environment(\.roamStores, stores)
            .environment(\.apiClient, api)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await stores.notifications.loadIfStale()
            await refreshFriendsCountForBadge()
        }
        .onChange(of: showFriendsSheet) { _, isOpen in
            if !isOpen {
                Task { await refreshFriendsCountForBadge() }
            }
        }
        .onChange(of: showCollectionsSheet) { _, isOpen in
            if !isOpen {
                Task { await stores.notifications.loadIfStale() }
            }
        }
    }

    /// Unread notifications that reference a collection (distinct collections with unseen activity).
    private var collectionsWithUnseenUpdatesCount: Int {
        let unread = stores.notifications.notifications.filter { !$0.isRead }
        var ids = Set<String>()
        for n in unread {
            if let id = notificationCollectionIdString(n) {
                ids.insert(id)
            }
        }
        return ids.count
    }

    private func notificationCollectionIdString(_ n: RoamNotification) -> String? {
        guard let raw = n.collectionId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return raw.lowercased()
    }

    @ViewBuilder
    private func profileNavDestination(_ dest: ProfileNav) -> some View {
        switch dest {
        case .friends(let tab):
            FriendsPage(initialTab: tab, prefilledUsername: nil)
        case .collections:
            CollectionsListView()
        case .collection(let id):
            ProfileCollectionDetailPage(collectionId: id)
        case .collectionAllIdeas(let id):
            CollectionAllIdeasPage(collectionId: id)
        case .accountSettings:
            AccountSettingsPlaceholderPage()
        }
    }

    private func refreshFriendsCountForBadge() async {
        do {
            let list = try await api.listFriends()
            friendsCountForBadge = list.count
        } catch {
            friendsCountForBadge = 0
        }
    }

    private enum BadgeStyle {
        case amber
        case purpleAccent
    }

    private func topBarCircleButton(
        systemImage: String,
        badgeCount: Int,
        badgeStyle: BadgeStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentBorder)
                    .frame(width: circleButtonSize, height: circleButtonSize)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().stroke(accentBorder, lineWidth: 1))

                if badgeCount > 0 {
                    let text = badgeCount > 99 ? "99+" : "\(badgeCount)"
                    Text(text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, text.count > 2 ? 3 : 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(
                            Capsule().fill(badgeStyle == .amber ? collectionBadgeFill : RoamColors.reviewAccent)
                        )
                        .offset(x: 7, y: -5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func initials(for user: RoamUser?) -> String {
        guard let user else { return "?" }
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "?" : s
    }

    private func subtitleLine(for user: RoamUser?) -> String? {
        guard let user else { return nil }
        let df = DateFormatter()
        df.dateFormat = "EEE · MMM d"
        let date = df.string(from: Date()).lowercased()
        if let city = user.city?.trimmingCharacters(in: .whitespaces), !city.isEmpty {
            return "\(date) · \(city.lowercased())"
        }
        return date
    }
}
