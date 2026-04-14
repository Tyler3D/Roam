import SafariServices
import SwiftUI

struct ProfilePage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(AppConfig.self) private var appConfig
    @Environment(PushNotificationManager.self) private var pushManager
    @Environment(\.apiClient) private var api
    @Environment(\.roamStores) private var stores
    var onDismiss: (() -> Void)?

    private var showAlphaProfileSettings: Bool {
        appConfig.appMode == .alphaHeavyDevelopmentUnsafe
    }

    @State private var path = NavigationPath()
    @State private var friends: [APIClient.FriendshipReadDTO] = []
    @State private var incomingRequests: [APIClient.FriendshipReadDTO] = []
    @State private var ideaCounts: [UUID: Int] = [:]
    @State private var showEditStub = false
    @State private var showCalendarStub = false
    @State private var showDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String? = nil
    @State private var showPrivacyPolicy = false

    private var sortedCollections: [APIClient.CollectionReadDTO] {
        stores.mapCollections.collections.sorted { lhs, rhs in
            if lhs.isPersonalDefault != rhs.isPersonalDefault { return lhs.isPersonalDefault && !rhs.isPersonalDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var previewCollections: [APIClient.CollectionReadDTO] {
        Array(sortedCollections.prefix(4))
    }

    private var previewFriends: [APIClient.FriendshipReadDTO] {
        Array(friends.prefix(3))
    }

    private var myUserId: UUID? { uuidFromUser(stores.user.me) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 0) {
                    profileHeader
                    statsRow
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    collectionsSection
                    friendsSection
                    settingsGroups
                }
                .padding(.bottom, 28)
            }
            .background(RoamColors.background)
            .navigationTitle("profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss?() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("edit") { showEditStub = true }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
            }
            .navigationDestination(for: ProfileNav.self) { dest in
                switch dest {
                case .friends(let tab):
                    FriendsPage(initialTab: tab)
                case .collections:
                    AllProfileCollectionsPage()
                case .collection(let id):
                    ProfileCollectionDetailPage(collectionId: id)
                case .collectionAllIdeas(let id):
                    CollectionAllIdeasPage(collectionId: id)
                case .accountSettings:
                    AccountSettingsPlaceholderPage()
                }
            }
            .alert("Edit profile", isPresented: $showEditStub) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Profile editing isn’t available yet.")
            }
            .alert("Google Calendar", isPresented: $showCalendarStub) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Calendar connection isn’t available yet.")
            }
            .alert("Delete account?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account, all your ideas, collections, and saved reels. This cannot be undone.")
            }
            .alert("Couldn’t delete account", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "An error occurred. Please try again.")
            }
            .sheet(isPresented: $showPrivacyPolicy) {
                SafariView(url: URL(string: "https://roam-alpha.web.app/privacy")!)
                    .ignoresSafeArea()
            }
            .task {
                await stores.user.refresh()
                await stores.ideas.loadIfStale()
                await stores.mapCollections.refreshCollections()
                await loadSocial()
                await loadIdeaCounts(for: sortedCollections)
            }
            .onChange(of: stores.mapCollections.collections.count) { _, _ in
                Task { await loadIdeaCounts(for: sortedCollections) }
            }
            .onAppear {
                Task {
                    await loadSocial()
                    await loadIdeaCounts(for: sortedCollections)
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var profileHeader: some View {
        if let user = stores.user.me {
            VStack(spacing: 12) {
                RoamAvatar(initials: initials(user), photoUrl: user.photoUrl, size: 80)
                Text(user.displayName)
                    .font(RoamFont.display(22, italic: true))
                    .foregroundStyle(RoamColors.text)
                if let u = user.username, !u.isEmpty {
                    Text("@\(u)")
                        .font(RoamFont.mono(13))
                        .foregroundStyle(RoamColors.textMid)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 20)
        } else {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading profile…")
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            Button {
                onDismiss?()
            } label: {
                statCell(value: stores.ideas.totalIdeasCount ?? stores.ideas.ideas.count, label: "Ideas")
            }
            .buttonStyle(.plain)
            statDivider
            NavigationLink(value: ProfileNav.collections) {
                statCell(value: stores.mapCollections.collections.count, label: "Collections")
            }
            .buttonStyle(.plain)
            statDivider
            NavigationLink(value: ProfileNav.friends(initialTab: .myFriends)) {
                statCell(value: friends.count, label: "Friends")
            }
            .buttonStyle(.plain)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(RoamColors.lavDeep.opacity(0.45))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(RoamFont.mono(20, weight: .bold))
                .foregroundStyle(RoamColors.text)
            Text(label)
                .font(RoamFont.mono(10, weight: .medium))
                .foregroundStyle(RoamColors.textMid)
                .textCase(.uppercase)
                .tracking(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("My Collections")
                Spacer()
                NavigationLink(value: ProfileNav.collections) {
                    Text("See all")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if stores.mapCollections.isLoadingCollections && sortedCollections.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(previewCollections) { c in
                    NavigationLink(value: ProfileNav.collection(c.id)) {
                        ProfileCollectionRow(
                            collection: c,
                            myUserId: myUserId,
                            ideaCount: ideaCounts[c.id]
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    sectionTitle("Friends")
                    if incomingRequests.count > 0 {
                        Text("\(incomingRequests.count)")
                            .font(RoamFont.mono(10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(RoamColors.reviewAccent)
                            .clipShape(Circle())
                    }
                }
                Spacer()
                NavigationLink(value: ProfileNav.friends(initialTab: .myFriends)) {
                    Text("Manage")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                ForEach(Array(previewFriends.enumerated()), id: \.element.id) { index, row in
                    if row.friendId != nil {
                        NavigationLink(value: ProfileNav.friends(initialTab: .myFriends)) {
                            friendPreviewRow(row: row, showDividerBelow: index < previewFriends.count - 1 || incomingRequests.count > 0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if incomingRequests.count > 0 {
                    Button {
                        path.append(ProfileNav.friends(initialTab: .requests))
                    } label: {
                        friendRequestsPreviewRow
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RoamColors.reviewBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            .padding(.horizontal, 20)
        }
        .padding(.top, 16)
    }

    private func friendPreviewRow(row: APIClient.FriendshipReadDTO, showDividerBelow: Bool) -> some View {
        HStack(spacing: 12) {
            RoamAvatar(
                initials: initialsForFriend(row),
                photoUrl: row.friendPhotoUrl,
                size: 40
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(first: row.friendFirstName, last: row.friendLastName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RoamColors.reviewBorder)
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if showDividerBelow {
                Rectangle()
                    .fill(RoamColors.lavDeep.opacity(0.35))
                    .frame(height: 1)
                    .padding(.leading, 52)
            }
        }
    }

    private var friendRequestsPreviewRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(RoamColors.reviewAccentLight)
                    .frame(width: 40, height: 40)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewAccent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(incomingRequests.count) friend request\(incomingRequests.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewAccent)
                Text(requestPreviewSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.textMid)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RoamColors.reviewAccent)
        }
        .padding(.vertical, 12)
    }

    private var requestPreviewSubtitle: String {
        let names = incomingRequests.prefix(2).map { displayName(first: $0.friendFirstName, last: $0.friendLastName) }
        let joined = names.joined(separator: ", ")
        if incomingRequests.count <= 2 {
            return "\(joined) want\(incomingRequests.count == 1 ? "s" : "") to connect"
        }
        return "\(joined) and others want to connect"
    }

    // MARK: - Settings

    private var settingsGroups: some View {
        VStack(spacing: 16) {
            if showAlphaProfileSettings {
                VStack(spacing: 0) {
                    NavigationLink(value: ProfileNav.accountSettings) {
                        menuRow(
                            icon: "gearshape",
                            title: "Account settings",
                            subtitle: "Email, password, notifications",
                            trailing: .chevron
                        )
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(RoamColors.lavDeep.opacity(0.35))
                        .frame(height: 1)
                        .padding(.leading, 60)

                    Button {
                        showCalendarStub = true
                    } label: {
                        menuRow(
                            icon: "calendar",
                            title: "Google Calendar",
                            subtitle: "Not connected",
                            trailing: .text("Connect")
                        )
                    }
                    .buttonStyle(.plain)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(RoamColors.reviewBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
            }

            VStack(spacing: 0) {
                Button {
                    showPrivacyPolicy = true
                } label: {
                    menuRow(
                        icon: "hand.raised",
                        title: "Privacy Policy",
                        subtitle: nil,
                        trailing: .chevron
                    )
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(RoamColors.lavDeep.opacity(0.35))
                    .frame(height: 1)
                    .padding(.leading, 60)

                Button {
                    pushManager.unregisterTokenFromBackend()
                    authManager.signOut()
                    onDismiss?()
                } label: {
                    menuRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Sign out",
                        subtitle: nil,
                        trailing: .none,
                        danger: true
                    )
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(RoamColors.lavDeep.opacity(0.35))
                    .frame(height: 1)
                    .padding(.leading, 60)

                Button {
                    showDeleteConfirm = true
                } label: {
                    menuRow(
                        icon: "trash",
                        title: isDeletingAccount ? "Deleting…" : "Delete account",
                        subtitle: "Permanently removes your account and all data",
                        trailing: .none,
                        danger: true
                    )
                }
                .buttonStyle(.plain)
                .disabled(isDeletingAccount)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(RoamColors.reviewBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private enum MenuTrailing {
        case chevron
        case text(String)
        case none
    }

    private func menuRow(
        icon: String,
        title: String,
        subtitle: String?,
        trailing: MenuTrailing,
        danger: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(danger ? RoamColors.error.opacity(0.08) : RoamColors.reviewSurfaceAlt)
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(danger ? RoamColors.error : RoamColors.textMid)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(danger ? RoamColors.error : RoamColors.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMid)
                }
            }
            Spacer(minLength: 0)
            switch trailing {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewBorder)
            case .text(let t):
                Text(t)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.reviewAccent)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(RoamFont.mono(12, weight: .semibold))
            .foregroundStyle(RoamColors.textMid)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    // MARK: - Data

    private func performDeleteAccount() async {
        isDeletingAccount = true
        do {
            try await authManager.deleteAccount(api: api)
            onDismiss?()
            return
        } catch {
            deleteError = error.localizedDescription
        }
        isDeletingAccount = false
    }

    private func loadSocial() async {
        do {
            async let f = api.listFriends()
            async let inc = api.listFriendRequests()
            friends = try await f
            incomingRequests = try await inc
        } catch {
            friends = []
            incomingRequests = []
        }
    }

    private func loadIdeaCounts(for cols: [APIClient.CollectionReadDTO]) async {
        await withTaskGroup(of: (UUID, Int).self) { group in
            for c in cols {
                group.addTask {
                    let n = (try? await api.listCollectionMapPins(collectionId: c.id))?.count ?? 0
                    return (c.id, n)
                }
            }
            for await (id, n) in group {
                ideaCounts[id] = n
            }
        }
    }

    private func initials(_ user: RoamUser) -> String {
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "?" : s
    }

    private func initialsForFriend(_ row: APIClient.FriendshipReadDTO) -> String {
        let f = row.friendFirstName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let l = row.friendLastName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "?" : s
    }

    private func displayName(first: String?, last: String?) -> String {
        let s = [first, last].compactMap { $0 }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return s.isEmpty ? "Friend" : s
    }
}

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

struct AccountSettingsPlaceholderPage: View {
    @Environment(\.apiClient) private var apiClient

    @State private var autoPromoteEnabled: Bool = true
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $autoPromoteEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto-promote single-place reels")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RoamColors.text)
                        Text("Skip review when a reel has exactly one high-confidence place")
                            .font(.system(size: 11))
                            .foregroundStyle(RoamColors.textMuted)
                    }
                }
                .tint(RoamColors.reviewAccent)
                .disabled(isLoading)
                .onChange(of: autoPromoteEnabled) { _, newVal in
                    Task {
                        _ = try? await apiClient.upsertFeatureFlag(
                            flagName: "auto_promote_single_candidate",
                            enabled: newVal
                        )
                    }
                }
            } header: {
                Text("Reel processing")
                    .font(RoamFont.mono(11))
            }
        }
        .navigationTitle("settings")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let flags = try await apiClient.listFeatureFlags()
                if let flag = flags.first(where: { $0.flagName == "auto_promote_single_candidate" }) {
                    autoPromoteEnabled = flag.enabled
                }
            } catch {}
            isLoading = false
        }
    }
}
