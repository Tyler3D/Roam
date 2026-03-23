import SwiftUI

struct IdeaCardView: View {
    let idea: Idea
    var requiresConfirmation: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(headline)
                    .font(RoamFont.notes(15, italic: true))
                    .foregroundStyle(RoamColors.text)
                    .multilineTextAlignment(.leading)
                Spacer()
                statusPill
            }
            if !idea.notes.isEmpty {
                Text(idea.notes)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.textMid)
                    .lineLimit(2)
            }
            if let place = idea.placeName, !place.isEmpty {
                Text(place)
                    .font(RoamFont.mono(9))
                    .foregroundStyle(RoamColors.loganDeep)
            }
            if requiresConfirmation {
                Text("Needs confirmation")
                    .font(RoamFont.mono(9, weight: .medium))
                    .foregroundStyle(RoamColors.error)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.logan.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: RoamColors.loganDark.opacity(0.07), radius: 8, y: 2)
    }

    private var headline: String {
        if let d = idea.displayName, !d.isEmpty { return d }
        return idea.title
    }

    @ViewBuilder
    private var statusPill: some View {
        Text(idea.status.rawValue)
            .font(RoamFont.mono(8, weight: .medium))
            .foregroundStyle(RoamColors.loganDark)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoamColors.lavender.opacity(0.65))
            .clipShape(Capsule())
    }
}
