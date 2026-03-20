import SwiftUI

struct InboxPage: View {
    @Environment(\.roamStores) private var stores

    var body: some View {
        list(stores: stores)
            .navigationTitle("inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if stores.notifications.unreadCount > 0 {
                        Button("Read all") {
                            Task {
                                try? await stores.notifications.markAllRead()
                            }
                        }
                        .font(RoamFont.mono(10, weight: .medium))
                    }
                }
            }
    }

    @ViewBuilder
    private func list(stores: RoamStores) -> some View {
        List {
            if stores.notifications.isLoading && stores.notifications.notifications.isEmpty {
                ProgressView()
            } else if stores.notifications.notifications.isEmpty {
                Text("No notifications")
                    .font(RoamFont.mono(11))
                    .foregroundStyle(RoamColors.textMuted)
            } else {
                ForEach(stores.notifications.notifications) { n in
                    Button {
                        Task {
                            if !n.isRead {
                                try? await stores.notifications.markRead(id: n.id)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(n.title)
                                    .font(RoamFont.notes(14, italic: true))
                                    .foregroundStyle(RoamColors.text)
                                Spacer()
                                if !n.isRead {
                                    Circle()
                                        .fill(RoamColors.notifDot)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            if let body = n.body, !body.isEmpty {
                                Text(body)
                                    .font(RoamFont.mono(10))
                                    .foregroundStyle(RoamColors.textMid)
                            }
                            Text(n.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(RoamFont.mono(8))
                                .foregroundStyle(RoamColors.textMuted)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await stores.notifications.refresh() }
        .task { await stores.notifications.loadIfStale() }
    }
}
