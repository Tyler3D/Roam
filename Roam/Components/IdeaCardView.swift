import SwiftUI

struct IdeaCardView: View {
    let idea: Idea

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(headline)
                    .font(RoamFont.notes(15, italic: true))
                    .foregroundStyle(RoamColors.text)
                    .multilineTextAlignment(.leading)
                Spacer()
                statusIndicator
            }

            if !idea.notes.isEmpty {
                Text(idea.notes)
                    .font(RoamFont.mono(10))
                    .foregroundStyle(RoamColors.textMid)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                if let place = idea.placeName, !place.isEmpty {
                    Label(place, systemImage: "mappin")
                        .font(RoamFont.mono(9))
                        .foregroundStyle(RoamColors.loganDeep)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let cat = category, !cat.isEmpty {
                    categoryChip(cat)
                }
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

    private var category: String? {
        idea.pipelineResult?.category
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if idea.status == .suggesting {
            ProgressView()
                .scaleEffect(0.65)
                .tint(RoamColors.loganDeep)
                .frame(width: 20, height: 20)
        } else if idea.pipelineResult == nil {
            // Raw capture — not yet enriched; show subtle sparkle hint
            Image(systemName: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(RoamColors.loganDark.opacity(0.45))
        }
        // No pill when enriched — the category chip carries that signal
    }

    private func categoryChip(_ category: String) -> some View {
        let label = category.replacingOccurrences(of: "-", with: " ")
        return Text(label)
            .font(RoamFont.mono(8, weight: .medium))
            .foregroundStyle(RoamColors.loganDark)
            .textCase(.uppercase)
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoamColors.lavender.opacity(0.65))
            .clipShape(Capsule())
    }
}
