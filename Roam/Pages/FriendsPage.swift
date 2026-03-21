import SwiftUI
import UIKit

enum FriendsNavTab: Hashable {
    case myFriends
    case requests
}

struct FriendsPage: View {
    @Environment(\.apiClient) private var api
    @Environment(\.roamStores) private var stores

    let initialTab: FriendsNavTab

    @State private var tab: FriendsNavTab
    @State private var friends: [APIClient.FriendshipReadDTO] = []
    @State private var incoming: [APIClient.FriendshipReadDTO] = []
    @State private var outgoing: [APIClient.FriendshipReadDTO] = []
    @State private var collections: [APIClient.CollectionReadDTO] = []
    @State private var friendSearch = ""
    @State private var usernameQuery = ""
    @State private var usernameMatches: [RoamUser] = []
    @State private var usernameSearchTask: Task<Void, Never>?
    @State private var isLoading = true
    @State private var actionError: String?
    @State private var inviteCopied = false

    init(initialTab: FriendsNavTab = .myFriends) {
        self.initialTab = initialTab
        _tab = State(initialValue: initialTab)
    }

    private var myUserId: UUID? {
        guard let me = stores.user.me else { return nil }
        return UUID(uuidString: me.id)
    }

    private var filteredFriends: [APIClient.FriendshipReadDTO] {
        let q = friendSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return friends }
        return friends.filter { row in
            let name = displayName(first: row.friendFirstName, last: row.friendLastName).lowercased()
            return name.contains(q)
        }
    }

    private var incomingBadgeCount: Int { incoming.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                tabSwitcher
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                if tab == .myFriends {
                    myFriendsContent
                } else {
                    requestsContent
                }
            }
            .padding(.bottom, 24)
        }
        .background(RoamColors.background)
        .navigationTitle("friends")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Couldn’t update friends",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .alert("Invite link copied", isPresented: $inviteCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Share it anywhere you chat with friends.")
        }
        .task {
            await reload()
        }
    }

    private var tabSwitcher: some View {
        HStack(spacing: 0) {
            tabPill(title: "My Friends", selected: tab == .myFriends) {
                tab = .myFriends
            }
            tabPill(title: "Requests", selected: tab == .requests, badge: incomingBadgeCount) {
                tab = .requests
            }
        }
        .padding(3)
        .background(RoamColors.reviewSurfaceAlt)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tabPill(title: String, selected: Bool, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? RoamColors.text : RoamColors.textMid)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Group {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                            }
                        }
                    )
                if badge > 0 {
                    Text(badge > 99 ? "99+" : "\(badge)")
                        .font(RoamFont.mono(9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(RoamColors.reviewAccent)
                        .clipShape(Circle())
                        .offset(x: -10, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var myFriendsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField(text: $friendSearch, placeholder: "Search by name or username…", icon: "magnifyingglass")
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            inviteBanner
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

            sectionTitle("Friends (\(friends.count))")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if filteredFriends.isEmpty {
                emptyBlock(
                    icon: "person.2",
                    text: friendSearch.isEmpty
                        ? "No friends yet. Add someone by username or share your invite link."
                        : "No matches for that search."
                )
                .padding(.horizontal, 20)
            } else {
                ForEach(filteredFriends) { row in
                    if let fid = row.friendId {
                        friendCard(row: row, friendId: fid, shared: sharedCollectionsCount(friendId: fid))
                    }
                }
            }

            sectionTitle("Add by username")
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)

            searchField(text: $usernameQuery, placeholder: "Enter a username to add…", icon: "person.badge.plus")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
                .onChange(of: usernameQuery) { _, newVal in
                    usernameSearchTask?.cancel()
                    let q = newVal.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !q.isEmpty else {
                        usernameMatches = []
                        return
                    }
                    usernameSearchTask = Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        guard !Task.isCancelled else { return }
                        await runUsernameSearch(q)
                    }
                }

            if !usernameMatches.isEmpty {
                ForEach(usernameMatches, id: \.id) { user in
                    usernameResultRow(user: user)
                }
            }
        }
    }

    private var requestsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Incoming (\(incoming.count))")
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if incoming.isEmpty {
                emptyBlock(icon: "tray", text: "No incoming requests.")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            } else {
                ForEach(incoming) { req in
                    incomingCard(req)
                }
            }

            sectionTitle("Sent (\(outgoing.count))")
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)

            if outgoing.isEmpty {
                emptyBlock(icon: "paperplane", text: "No outgoing requests.")
                    .padding(.horizontal, 20)
            } else {
                ForEach(outgoing) { req in
                    outgoingCard(req)
                }
            }

            VStack(spacing: 12) {
                Text("Looking for someone?")
                    .font(.system(size: 13))
                    .foregroundStyle(RoamColors.textMid)
                Button {
                    tab = .myFriends
                } label: {
                    Text("Search by username →")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(RoamColors.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 3, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.horizontal, 20)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(RoamColors.reviewBorder.opacity(0.5))
                    .frame(height: 1)
                    .padding(.top, 8)
            }
        }
    }

    private var inviteBanner: some View {
        VStack(spacing: 0) {
            Text("Invite friends to Roam")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RoamColors.text)
            Text("Share your link so friends can join and start saving places together.")
                .font(.system(size: 12))
                .foregroundStyle(RoamColors.textMid)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .padding(.bottom, 12)
            Button {
                copyInviteLink()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Share invite link")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(RoamColors.reviewAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: RoamColors.reviewAccent.opacity(0.25), radius: 8, x: 0, y: 2)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoamColors.reviewAccentLight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RoamColors.reviewAccent.opacity(0.2), lineWidth: 1.5)
        )
    }

    private func searchField(text: Binding<String>, placeholder: String, icon: String) -> some View {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(RoamColors.textMid)
                .frame(width: 38)
            TextField(placeholder, text: text)
                .font(.system(size: 14))
                .textFieldStyle(.plain)
        }
        .padding(.vertical, 10)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(RoamFont.mono(12, weight: .semibold))
            .foregroundStyle(RoamColors.textMid)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func emptyBlock(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(RoamColors.textMuted.opacity(0.45))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(RoamColors.textMid)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func friendCard(row: APIClient.FriendshipReadDTO, friendId: UUID, shared: Int) -> some View {
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
                if let h = handleSubtitle(for: friendId), !h.isEmpty {
                    Text(h)
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMid)
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(shared > 0 ? RoamColors.reviewAccent : RoamColors.textMuted.opacity(0.35))
                        .frame(width: 5, height: 5)
                    Text(shared == 1 ? "1 shared collection" : "\(shared) shared collections")
                        .font(.system(size: 10))
                        .foregroundStyle(RoamColors.textMid)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Text("Friends")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(RoamColors.textMid)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(RoamColors.reviewSurfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(RoamColors.reviewBorder, lineWidth: 1)
                )
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func incomingCard(_ req: APIClient.FriendshipReadDTO) -> some View {
        HStack(spacing: 12) {
            RoamAvatar(initials: initialsForFriend(req), photoUrl: req.friendPhotoUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(first: req.friendFirstName, last: req.friendLastName))
                    .font(.system(size: 14, weight: .semibold))
                if let h = handleSubtitle(for: req.friendId), !h.isEmpty {
                    Text(h)
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMid)
                }
                Text(requestSentLabel(req.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(RoamColors.textMid)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button {
                    Task { await accept(req) }
                } label: {
                    Text("Accept")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(RoamColors.reviewAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    Task { await decline(req) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(RoamColors.textMid)
                        .frame(width: 32, height: 32)
                        .background(RoamColors.reviewSurfaceAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(RoamColors.reviewBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func outgoingCard(_ req: APIClient.FriendshipReadDTO) -> some View {
        HStack(spacing: 12) {
            RoamAvatar(initials: initialsForFriend(req), photoUrl: req.friendPhotoUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(first: req.friendFirstName, last: req.friendLastName))
                    .font(.system(size: 14, weight: .semibold))
                if let h = handleSubtitle(for: req.friendId), !h.isEmpty {
                    Text(h)
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMid)
                }
                Text(requestSentLabel(req.createdAt))
                    .font(.system(size: 10))
                    .foregroundStyle(RoamColors.textMid)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.55, blue: 0.2))
                        .frame(width: 6, height: 6)
                    Text("Pending")
                        .font(.system(size: 11))
                        .foregroundStyle(RoamColors.textMid)
                }
                Button {
                    Task { await cancelOutgoing(req) }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(RoamColors.textMid)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(RoamColors.reviewBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .padding(.vertical, 2)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func usernameResultRow(user: RoamUser) -> some View {
        let uid = UUID(uuidString: user.id)
        let isFriend = uid.map { id in friends.contains { $0.friendId == id } } ?? false
        let pendingOut = uid.map { id in outgoing.contains { $0.friendId == id } } ?? false

        return HStack(spacing: 12) {
            RoamAvatar(initials: initialsForUser(user), photoUrl: user.photoUrl, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.system(size: 14, weight: .semibold))
                if let u = user.username, !u.isEmpty {
                    Text("@\(u)")
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMid)
                }
            }
            Spacer(minLength: 0)
            if isFriend {
                Text("Friends")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.textMid)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoamColors.reviewSurfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(RoamColors.reviewBorder, lineWidth: 1)
                    )
            } else if pendingOut {
                Text("Pending")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RoamColors.textMid)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoamColors.reviewSurfaceAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(RoamColors.reviewBorder, lineWidth: 1)
                    )
            } else if let uid {
                Button {
                    Task { await sendRequest(to: uid) }
                } label: {
                    Text("Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(RoamColors.reviewAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Data

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let f = api.listFriends()
            async let inc = api.listFriendRequests()
            async let out = api.listSentFriendRequests()
            async let col = api.listCollections()
            friends = try await f
            incoming = try await inc
            outgoing = try await out
            collections = try await col
        } catch {
            friends = []
            incoming = []
            outgoing = []
            collections = []
            actionError = error.localizedDescription
        }
    }

    private func runUsernameSearch(_ q: String) async {
        do {
            let r = try await api.searchFriends(query: q)
            let merged = r.friends + r.others
            var seen = Set<String>()
            var out: [RoamUser] = []
            for u in merged where u.id != stores.user.me?.id {
                if seen.insert(u.id).inserted { out.append(u) }
            }
            usernameMatches = Array(out.prefix(6))
        } catch {
            usernameMatches = []
        }
    }

    private func sharedCollectionsCount(friendId: UUID) -> Int {
        guard let myId = myUserId else { return 0 }
        return collections.filter { c in
            guard !c.isPersonalDefault else { return false }
            let ids = Set((c.memberPreview ?? []).map(\.userId))
            return ids.contains(myId) && ids.contains(friendId)
        }.count
    }

    private func accept(_ req: APIClient.FriendshipReadDTO) async {
        do {
            _ = try await api.acceptFriendRequest(friendshipId: req.id)
            await reload()
            await stores.user.refresh()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func decline(_ req: APIClient.FriendshipReadDTO) async {
        do {
            try await api.removeFriendship(friendshipId: req.id)
            await reload()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func cancelOutgoing(_ req: APIClient.FriendshipReadDTO) async {
        do {
            try await api.removeFriendship(friendshipId: req.id)
            await reload()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func sendRequest(to userId: UUID) async {
        do {
            _ = try await api.sendFriendRequest(targetUserId: userId)
            await reload()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func copyInviteLink() {
        let raw = stores.user.me?.username ?? "friend"
        let enc = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
        UIPasteboard.general.string = "roam://invite?user=\(enc)"
        inviteCopied = true
    }

    private func displayName(first: String?, last: String?) -> String {
        let s = [first, last].compactMap { $0 }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: " ")
        return s.isEmpty ? "Friend" : s
    }

    private func initialsForFriend(_ row: APIClient.FriendshipReadDTO) -> String {
        initialsFromParts(row.friendFirstName, row.friendLastName)
    }

    private func initialsForUser(_ u: RoamUser) -> String {
        initialsFromParts(u.firstName, u.lastName)
    }

    private func initialsFromParts(_ first: String?, _ last: String?) -> String {
        let f = first?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let l = last?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        if !s.isEmpty { return s }
        if let u = first?.trimmingCharacters(in: .whitespaces), u.count >= 2 {
            return String(u.prefix(2)).uppercased()
        }
        return "?"
    }

    private func handleSubtitle(for friendId: UUID?) -> String? {
        guard let friendId else { return nil }
        if let user = usernameMatches.first(where: { UUID(uuidString: $0.id) == friendId }),
           let un = user.username, !un.isEmpty {
            return "@\(un)"
        }
        return nil
    }

    private func requestSentLabel(_ date: Date?) -> String {
        guard let date else { return "Sent recently" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Sent " + f.localizedString(for: date, relativeTo: Date())
    }
}
