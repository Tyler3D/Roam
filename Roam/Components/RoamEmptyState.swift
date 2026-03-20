import SwiftUI

struct RoamEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Text(icon)
                .font(.system(size: 28))
                .frame(width: 56, height: 56)
                .background(RoamColors.lavender)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title)
                .font(RoamFont.mono(11, weight: .medium))
                .foregroundStyle(RoamColors.text)
                .textCase(.uppercase)
                .tracking(1.2)
            Text(subtitle)
                .font(RoamFont.mono(10))
                .foregroundStyle(RoamColors.textMid)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }
}
