import SwiftUI

struct ProfilePage: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.roamStores) private var stores
    var onDismiss: (() -> Void)?

    var body: some View {
        List {
            if let user = stores.user.me {
                Section {
                    HStack(spacing: 14) {
                        RoamAvatar(initials: initials(user), photoUrl: user.photoUrl, size: 56)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(user.displayName)
                                .font(RoamFont.display(20, italic: true))
                            if let u = user.username {
                                Text("@\(u)")
                                    .font(RoamFont.mono(11))
                                    .foregroundStyle(RoamColors.textMuted)
                            }
                            if let email = user.email {
                                Text(email)
                                    .font(RoamFont.mono(10))
                                    .foregroundStyle(RoamColors.textMid)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                if let city = user.city, !city.isEmpty {
                    Section("City") {
                        Text(city)
                            .font(RoamFont.mono(12))
                    }
                }
            } else {
                Section {
                    Text("Loading profile…")
                        .font(RoamFont.mono(11))
                        .foregroundStyle(RoamColors.textMuted)
                }
            }

            Section {
                Button("Sign out", role: .destructive) {
                    authManager.signOut()
                    onDismiss?()
                }
                .font(RoamFont.mono(12, weight: .medium))
            }
        }
        .navigationTitle("profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { onDismiss?() }
            }
        }
        .task {
            await stores.user.refresh()
        }
    }

    private func initials(_ user: RoamUser) -> String {
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? "?" : s
    }
}
