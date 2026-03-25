import SwiftUI

struct AllProfileCollectionsPage: View {
    @Environment(\.apiClient) private var api
    @Environment(\.roamStores) private var stores

    @State private var ideaCounts: [UUID: Int] = [:]

    private var collections: [APIClient.CollectionReadDTO] {
        stores.mapCollections.collections.sorted { lhs, rhs in
            if lhs.isPersonalDefault != rhs.isPersonalDefault { return lhs.isPersonalDefault && !rhs.isPersonalDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(collections) { c in
                    NavigationLink(value: ProfileNav.collection(c.id)) {
                        ProfileCollectionRow(
                            collection: c,
                            myUserId: uuidFromUser(stores.user.me),
                            ideaCount: ideaCounts[c.id]
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .padding(.vertical, 12)
        }
        .background(RoamColors.background)
        .navigationTitle("collections")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadCounts(for: collections)
        }
    }

    private func loadCounts(for cols: [APIClient.CollectionReadDTO]) async {
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
}

struct ProfileCollectionDetailPage: View {
    @Environment(\.apiClient) private var api
    @Environment(\.roamStores) private var stores
    @Environment(\.dismiss) private var dismiss

    let collectionId: UUID

    @State private var pins: [APIClient.CollectionMapPinDTO] = []
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var showAddFriendSheet = false

    private var collection: APIClient.CollectionReadDTO? {
        stores.mapCollections.collections.first { $0.id == collectionId }
    }

    private var myId: UUID? { uuidFromUser(stores.user.me) }

    private var ideaCount: Int { pins.count }

    private var ideasThisWeekCount: Int {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else {
            return 0
        }
        return pins.filter { $0.createdAt >= start }.count
    }

    private func ideasAddedByMember(_ userId: UUID) -> Int {
        pins.filter { $0.addedByUserId == userId }.count
    }

    private var recentPins: [APIClient.CollectionMapPinDTO] {
        pins.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if let c = collection {
                content(for: c)
            } else {
                Text("Collection not found.")
                    .font(RoamFont.mono(12))
                    .foregroundStyle(RoamColors.textMid)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(RoamColors.background)
        .navigationTitle("collection")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPins()
        }
        .sheet(isPresented: $showAddFriendSheet) {
            AddFriendToCollectionSheet(
                collectionId: collectionId,
                memberUserIds: Set((collection?.memberPreview ?? []).map(\.userId))
            )
            .environment(\.apiClient, api)
            .environment(\.roamStores, stores)
        }
        .onChange(of: showAddFriendSheet) { _, isPresented in
            if !isPresented {
                Task {
                    await stores.mapCollections.refreshCollections()
                    await loadPins()
                }
            }
        }
        .alert(
            "Leave this collection?",
            isPresented: $confirmLeave
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task { await leaveCollection() }
            }
        } message: {
            Text("You won’t see its pins on your map until someone adds you again.")
        }
        .alert(
            "Delete this collection?",
            isPresented: $confirmDelete
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteCollection() }
            }
        } message: {
            Text("This removes the collection for everyone. This can’t be undone.")
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(for c: APIClient.CollectionReadDTO) -> some View {
        let previews = c.memberPreview ?? []
        let memberCount = max(previews.count, 1)
        ScrollView {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    memberIconCluster(for: c)
                    Text(c.name)
                        .font(.system(size: 20, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text("\(memberCount) members · \(ideaCount) ideas · Created \(shortDate(c.createdAt))")
                        .font(.system(size: 12))
                        .foregroundStyle(RoamColors.textMid)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 20)

                statsRow(ideas: ideaCount, members: memberCount, thisWeek: ideasThisWeekCount)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)

                sectionTitle("Members")
                    .padding(.horizontal, 20)
                    .padding(.bottom, 10)

                ForEach(previews, id: \.userId) { m in
                    memberRow(
                        collection: c,
                        member: m,
                        ideasAdded: ideasAddedByMember(m.userId)
                    )
                }

                if !c.isPersonalDefault {
                    addFriendButton
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                }

                recentIdeasSection(for: c)
                    .padding(.top, 8)

                if !c.isPersonalDefault {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("Danger zone", color: RoamColors.error)
                        Button {
                            confirmLeave = true
                        } label: {
                            Text("Leave collection")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(RoamColors.error)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(RoamColors.error.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(RoamColors.error.opacity(0.3), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)

                        if let mid = myId, c.creatorId == mid {
                            Button {
                                confirmDelete = true
                            } label: {
                                Text("Delete collection")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(RoamColors.error)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(RoamColors.error.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(RoamColors.error.opacity(0.3), lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(RoamColors.reviewBorder.opacity(0.6))
                            .frame(height: 1)
                            .padding(.top, 8)
                    }
                }

                Spacer(minLength: 24)
            }
        }
    }

    private func memberIconCluster(for c: APIClient.CollectionReadDTO) -> some View {
        let previews = Array((c.memberPreview ?? []).prefix(3))
        return HStack(spacing: 3) {
            ForEach(Array(previews.enumerated()), id: \.offset) { _, m in
                Circle()
                    .fill(MapPinPalette.color(forIndex: abs(m.userId.hashValue % 8)))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(14)
        .background(RoamColors.reviewAccentLight)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var addFriendButton: some View {
        Button {
            showAddFriendSheet = true
        } label: {
            HStack(spacing: 6) {
                Text("+")
                    .font(.system(size: 16, weight: .semibold))
                Text("Add a friend")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(RoamColors.reviewAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(RoamColors.reviewAccent.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func recentIdeasSection(for c: APIClient.CollectionReadDTO) -> some View {
        let preview = Array(recentPins.prefix(6))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                sectionTitle("Recent ideas")
                Spacer()
                if !recentPins.isEmpty {
                    NavigationLink(value: ProfileNav.collectionAllIdeas(c.id)) {
                        Text("View all")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(RoamColors.reviewAccent)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)

            if preview.isEmpty {
                Text("No ideas in this collection yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(RoamColors.textMid)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
            } else {
                ForEach(preview) { pin in
                    NavigationLink {
                        ProfileCollectionIdeaDetailDestination(pin: pin)
                    } label: {
                        recentIdeaRow(pin: pin)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func recentIdeaRow(pin: APIClient.CollectionMapPinDTO) -> some View {
        let initials = initialsFromContributor(pin)
        let color = MapPinPalette.color(forIndex: pin.colorIndex)
        return HStack(spacing: 12) {
            Text(initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.pinTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                    .multilineTextAlignment(.leading)
                Text(recentIdeaSubtitle(pin: pin))
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.textMid)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RoamColors.reviewBorder)
        }
        .padding(12)
        .padding(.trailing, 4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func recentIdeaSubtitle(pin: APIClient.CollectionMapPinDTO) -> String {
        let by = addedByPhrase(pin: pin)
        let when = ideaRelativeDate(pin.createdAt)
        return "Added by \(by) · \(when)"
    }

    private func addedByPhrase(pin: APIClient.CollectionMapPinDTO) -> String {
        if pin.addedByUserId == myId { return "You" }
        let n = pin.addedByDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = n.split(separator: " ").first { return String(first) }
        return n.isEmpty ? "Someone" : n
    }

    private func initialsFromContributor(_ pin: APIClient.CollectionMapPinDTO) -> String {
        let n = pin.addedByDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = n.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            let a = String(parts[0].prefix(1))
            let b = String(parts[1].prefix(1))
            return (a + b).uppercased()
        }
        if let f = parts.first { return String(f.prefix(2)).uppercased() }
        return "?"
    }

    private func ideaRelativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "today" }
        if cal.isDateInYesterday(date) { return "yesterday" }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func statsRow(ideas: Int, members: Int, thisWeek: Int) -> some View {
        HStack(spacing: 0) {
            statCell(value: ideas, label: "Ideas")
            Rectangle()
                .fill(RoamColors.reviewBorder.opacity(0.8))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            statCell(value: members, label: "Members")
            Rectangle()
                .fill(RoamColors.reviewBorder.opacity(0.8))
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            statCell(value: thisWeek, label: "This week")
        }
        .frame(minHeight: 56)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private func statCell(value: Int, label: String) -> some View {
        statCell(value: "\(value)", label: label)
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
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

    private func sectionTitle(_ title: String, color: Color = RoamColors.textMid) -> some View {
        Text(title)
            .font(RoamFont.mono(12, weight: .semibold))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func memberRow(
        collection c: APIClient.CollectionReadDTO,
        member m: APIClient.CollectionMemberPreviewDTO,
        ideasAdded: Int
    ) -> some View {
        let isYou = myId == m.userId
        let isCreator = c.creatorId == m.userId
        let label = [m.firstName, m.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let name = label.isEmpty ? "Member" : label
        let roleLine: String = {
            if isCreator { return "Created this collection" }
            if ideasAdded == 0 { return "No ideas added yet" }
            if ideasAdded == 1 { return "Added 1 idea" }
            return "Added \(ideasAdded) ideas"
        }()

        return HStack(spacing: 12) {
            RoamAvatar(
                initials: initialsFromNames(m.firstName, m.lastName),
                photoUrl: m.photoUrl,
                size: 36
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                Text(roleLine)
                    .font(RoamFont.mono(10, weight: .medium))
                    .foregroundStyle(RoamColors.textMid)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            Spacer(minLength: 0)
            if isYou {
                Text("You")
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.textMid)
            } else if !c.isPersonalDefault {
                Button {
                    Task { await removeMember(m.userId, from: c.id) }
                } label: {
                    Text("Remove")
                        .font(.system(size: 12))
                        .foregroundStyle(RoamColors.textMid)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .padding(.horizontal, 4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func loadPins() async {
        do {
            pins = try await api.listCollectionMapPins(collectionId: collectionId)
        } catch {
            pins = []
        }
    }

    private func leaveCollection() async {
        guard let mid = myId else { return }
        do {
            try await api.removeCollectionMember(collectionId: collectionId, memberUserId: mid)
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCollection() async {
        do {
            try await api.deleteCollection(collectionId: collectionId)
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(_ userId: UUID, from collectionId: UUID) async {
        do {
            try await api.removeCollectionMember(collectionId: collectionId, memberUserId: userId)
            await stores.mapCollections.refreshCollections()
            await stores.mapCollections.refreshPins()
            await loadPins()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shortDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: d)
    }

    private func initialsFromNames(_ first: String?, _ last: String?) -> String {
        let f = first?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let l = last?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "?" : s
    }
}

// MARK: - All ideas in collection

struct CollectionAllIdeasPage: View {
    @Environment(\.apiClient) private var api

    let collectionId: UUID

    @State private var pins: [APIClient.CollectionMapPinDTO] = []
    @State private var loadError: String?
    @State private var didLoad = false

    private var sortedPins: [APIClient.CollectionMapPinDTO] {
        pins.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if !didLoad {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError {
                Text(loadError)
                    .font(RoamFont.mono(12))
                    .foregroundStyle(RoamColors.textMid)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if sortedPins.isEmpty {
                Text("No ideas in this collection yet.")
                    .font(.system(size: 14))
                    .foregroundStyle(RoamColors.textMid)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sortedPins) { pin in
                            NavigationLink {
                                ProfileCollectionIdeaDetailDestination(pin: pin)
                            } label: {
                                CollectionAllIdeasRow(pin: pin)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
        }
        .background(RoamColors.background)
        .navigationTitle("ideas")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPins()
            didLoad = true
        }
    }

    private func loadPins() async {
        loadError = nil
        do {
            pins = try await api.listCollectionMapPins(collectionId: collectionId)
        } catch {
            pins = []
            loadError = error.localizedDescription
        }
    }
}

private struct CollectionAllIdeasRow: View {
    let pin: APIClient.CollectionMapPinDTO

    var body: some View {
        HStack(spacing: 12) {
            Text(initials)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(MapPinPalette.color(forIndex: pin.colorIndex))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.pinTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.textMid)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RoamColors.reviewBorder)
        }
        .padding(12)
        .padding(.trailing, 4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    private var initials: String {
        let n = pin.addedByDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = n.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return (String(parts[0].prefix(1)) + String(parts[1].prefix(1))).uppercased()
        }
        if let f = parts.first { return String(f.prefix(2)).uppercased() }
        return "?"
    }

    private var subtitle: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return "Added by \(pin.addedByDisplayName) · \(f.string(from: pin.createdAt))"
    }
}

// MARK: - Add friend to collection

struct AddFriendToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.apiClient) private var api

    let collectionId: UUID
    /// Known members from collection preview (may be incomplete if many members).
    let memberUserIds: Set<UUID>

    @State private var friends: [APIClient.FriendshipReadDTO] = []
    @State private var addingUserId: UUID?
    @State private var actionError: String?

    private var friendsNotInCollection: [APIClient.FriendshipReadDTO] {
        friends.filter { row in
            guard let fid = row.friendId else { return false }
            return !memberUserIds.contains(fid)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if friendsNotInCollection.isEmpty {
                    VStack(spacing: 10) {
                        Text(friends.isEmpty ? "No friends to add yet." : "Everyone here is already in this collection (or not shown in the member list).")
                            .font(.system(size: 14))
                            .foregroundStyle(RoamColors.textMid)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(friendsNotInCollection) { row in
                                if let fid = row.friendId {
                                    addFriendRow(row: row, friendId: fid)
                                }
                            }
                        }
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(RoamColors.background)
            .navigationTitle("Add to collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Couldn’t add friend",
                isPresented: Binding(
                    get: { actionError != nil },
                    set: { if !$0 { actionError = nil } }
                )
            ) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "")
            }
            .task {
                await loadFriends()
            }
        }
    }

    private func addFriendRow(row: APIClient.FriendshipReadDTO, friendId: UUID) -> some View {
        let name = [row.friendFirstName, row.friendLastName]
            .compactMap { $0 }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let display = name.isEmpty ? "Friend" : name
        let busy = addingUserId == friendId

        return HStack(spacing: 12) {
            RoamAvatar(initials: initialsForFriend(row), photoUrl: row.friendPhotoUrl, size: 40)
            Text(display)
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 0)
            Button {
                Task { await addMember(friendId) }
            } label: {
                if busy {
                    ProgressView()
                        .scaleEffect(0.85)
                } else {
                    Text("Add")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(RoamColors.reviewAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func initialsForFriend(_ row: APIClient.FriendshipReadDTO) -> String {
        let f = row.friendFirstName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let l = row.friendLastName?.trimmingCharacters(in: .whitespaces).first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "?" : s
    }

    private func loadFriends() async {
        do {
            friends = try await api.listFriends()
        } catch {
            friends = []
        }
    }

    private func addMember(_ userId: UUID) async {
        addingUserId = userId
        defer { addingUserId = nil }
        do {
            try await api.addCollectionMember(collectionId: collectionId, userId: userId)
            dismiss()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

// MARK: - Shared row

struct ProfileCollectionRow: View {
    let collection: APIClient.CollectionReadDTO
    let myUserId: UUID?
    var ideaCount: Int?

    var body: some View {
        HStack(spacing: 12) {
            collectionLeadingIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                Text(metaLine)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.textMid)
            }
            Spacer(minLength: 0)
            if let ideaCount {
                Text("\(ideaCount)")
                    .font(RoamFont.mono(12))
                    .foregroundStyle(RoamColors.textMid)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RoamColors.reviewBorder)
        }
        .padding(12)
        .padding(.trailing, 4)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.04), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private var collectionLeadingIcon: some View {
        if collection.isPersonalDefault {
            Circle()
                .fill(RoamColors.reviewSuccess)
                .frame(width: 12, height: 12)
                .frame(width: 38, height: 38)
                .background(RoamColors.reviewAccentLight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            let previews = Array((collection.memberPreview ?? []).prefix(3))
            HStack(spacing: 2) {
                ForEach(Array(previews.enumerated()), id: \.offset) { _, m in
                    Circle()
                        .fill(MapPinPalette.color(forIndex: abs(m.userId.hashValue % 8)))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 38, height: 38)
            .background(RoamColors.reviewAccentLight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var metaLine: String {
        if collection.isPersonalDefault { return "Just you" }
        guard let myUserId else { return "Shared" }
        let previews = collection.memberPreview ?? []
        var parts: [String] = []
        let ids = Set(previews.map(\.userId))
        if ids.contains(myUserId) { parts.append("You") }
        for m in previews where m.userId != myUserId {
            let n = [m.firstName, m.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            if !n.isEmpty { parts.append(n) }
        }
        if parts.isEmpty { return "Shared" }
        return parts.prefix(4).joined(separator: ", ")
    }
}

// MARK: - Idea detail (alpha vs main)

private struct ProfileCollectionIdeaDetailDestination: View {
    @Environment(AppConfig.self) private var appConfig
    let pin: APIClient.CollectionMapPinDTO

    var body: some View {
        Group {
            if appConfig.appMode == .alphaHeavyDevelopmentUnsafe {
                IdeaDetailPage(ideaId: pin.id.uuidString.lowercased())
            } else {
                ConsumerIdeaDetailPage(route: ConsumerIdeaDetailRoute.from(pin: pin))
            }
        }
    }
}

// MARK: - Helpers

enum ProfileNav: Hashable {
    case friends(initialTab: FriendsNavTab)
    case collections
    case collection(UUID)
    /// All ideas in a collection (newest first), tappable → idea detail.
    case collectionAllIdeas(UUID)
    case accountSettings
}

func uuidFromUser(_ user: RoamUser?) -> UUID? {
    guard let user else { return nil }
    return UUID(uuidString: user.id)
}
