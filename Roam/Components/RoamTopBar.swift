import SwiftUI
import UIKit

/// Compact header aligned with [frontend/src/components/TopBar.tsx](frontend/src/components/TopBar.tsx).
struct RoamTopBar: View {
    let user: RoamUser?
    let unreadNotifications: Int
    var onNotifications: () -> Void
    var onProfile: () -> Void

    var body: some View {
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
