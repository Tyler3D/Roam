import SwiftUI

struct PlanCardView: View {
    let plan: Plan

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.title)
                .font(RoamFont.notes(15, italic: true))
                .foregroundStyle(RoamColors.text)
            if let at = plan.scheduledAt {
                Text(scheduledLine(at))
                    .font(RoamFont.mono(9))
                    .foregroundStyle(RoamColors.textMuted)
            }
            if let place = plan.placeName, !place.isEmpty {
                Text(place)
                    .font(RoamFont.mono(9))
                    .foregroundStyle(RoamColors.loganDeep)
            }
            Text(plan.status.rawValue)
                .font(RoamFont.mono(8, weight: .medium))
                .foregroundStyle(RoamColors.loganDark)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoamColors.lavender.opacity(0.5))
                .clipShape(Capsule())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.logan.opacity(0.2), lineWidth: 1)
        )
    }

    private func scheduledLine(_ at: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM d · h:mm a"
        return df.string(from: at).lowercased()
    }
}
