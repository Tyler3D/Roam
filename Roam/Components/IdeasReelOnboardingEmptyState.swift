import SwiftUI

/// Visual onboarding when the Ideas list is empty: share reel → Roam → places on map.
struct IdeasReelOnboardingEmptyState: View {
    @State private var pulsePhase: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            hero

            stepReelCard
            stepArrow

            stepShareSheetCard
            stepArrow

            stepResultCard

            tipBox
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulsePhase = 1
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 6) {
            Text("Turn reels into places")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(RoamColors.text)
                .multilineTextAlignment(.center)
            Text("Three taps. That's it.")
                .font(.system(size: 13))
                .foregroundStyle(RoamColors.textMuted)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Step 1

    private var stepReelCard: some View {
        VStack(spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.55, green: 0.13, blue: 0.13),
                        Color(red: 0.75, green: 0.22, blue: 0.17),
                        Color(red: 0.63, green: 0.19, blue: 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.85)

                VStack(spacing: 2) {
                    Text("This NYC Bar\nHas $6 Drinks")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    Text("@noshplate · instagram.com")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .stroke(RoamColors.reviewAccent, lineWidth: 2)
                            .frame(width: 48, height: 48)
                            .scaleEffect(0.85 + pulsePhase * 0.35)
                            .opacity(0.85 - pulsePhase * 0.85)

                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 32, height: 32)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    Text("Share")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 12)
                .padding(.bottom, 12)
            }
            .frame(height: 140)
            .clipped()

            stepLabelRow(
                number: "1",
                title: {
                    Text("See a place you like? Tap ") + Text("Share").fontWeight(.bold)
                },
                hint: "Works on Instagram Reels and TikTok"
            )
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .padding(.horizontal, 4)
        .padding(.top, 16)
    }

    // MARK: - Step 2

    private var stepShareSheetCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.29, green: 0.29, blue: 0.30))
                    .frame(width: 36, height: 4)
                    .padding(.bottom, 10)

                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.75, green: 0.22, blue: 0.17),
                                    Color(red: 0.55, green: 0.13, blue: 0.13)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reel from noshplate")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("instagram.com")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
                .background(Color(red: 0.23, green: 0.23, blue: 0.24))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.bottom, 12)

                HStack(spacing: 12) {
                    shareAppIcon(
                        gradient: [Color(red: 0.20, green: 0.78, blue: 0.35), Color(red: 0.19, green: 0.82, blue: 0.35)],
                        symbol: "message.fill",
                        name: "Messages"
                    )
                    shareAppIcon(
                        gradient: [Color(red: 0, green: 0.48, blue: 1), Color(red: 0.35, green: 0.78, blue: 0.98)],
                        symbol: "envelope.fill",
                        name: "Mail"
                    )
                    roamShareAppIcon
                    shareAppIcon(
                        gradient: [Color(red: 1, green: 0.58, blue: 0)],
                        symbol: "note.text",
                        name: "Notes"
                    )
                    shareAppIcon(
                        gradient: [Color(red: 0.56, green: 0.56, blue: 0.58)],
                        symbol: "ellipsis",
                        name: "More"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(Color(red: 0.17, green: 0.17, blue: 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            stepLabelRow(
                number: "2",
                title: {
                    Text("Choose ") + Text("Roam").fontWeight(.bold) + Text(" from the share sheet")
                },
                hint: "Don't see it? Scroll right or tap More"
            )
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .padding(.horizontal, 4)
    }

    private func shareAppIcon(gradient: [Color], symbol: String, name: String) -> some View {
        VStack(spacing: 4) {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.white)
                }
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(Color(red: 0.56, green: 0.56, blue: 0.58))
                .lineLimit(1)
                .frame(width: 52)
        }
    }

    private var roamShareAppIcon: some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                Text("Tap here!")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(RoamColors.reviewAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoamColors.reviewAccent.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                TrianglePointer()
                    .fill(RoamColors.reviewAccent)
                    .frame(width: 10, height: 6)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(RoamColors.reviewAccent)
                    .shadow(color: RoamColors.reviewAccent.opacity(0.4), radius: 6, y: 0)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(RoamColors.reviewAccent, lineWidth: 2.5)
                    )
                Text("R")
                    .font(RoamFont.mono(22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            Text("Roam")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(RoamColors.reviewAccent)
                .frame(width: 52)
        }
    }

    // MARK: - Step 3

    private var stepResultCard: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                resultRow(name: "The Magician", address: "118 Rivington St, Lower East Side")
                resultRow(name: "The Laundry Room", address: "121 Rivington St, Lower East Side")
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(RoamColors.reviewAccent)
                    Text("Now on your map")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(RoamColors.reviewAccent)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(Color(red: 0.96, green: 0.95, blue: 0.97))

            stepLabelRow(
                number: "3",
                title: {
                    Text("Places appear").fontWeight(.bold) + Text(" on your map automatically")
                },
                hint: "AI extracts every place mentioned in the reel"
            )
        }
        .background(RoamColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RoamColors.reviewBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
        .padding(.horizontal, 4)
    }

    private func resultRow(name: String, address: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(RoamColors.reviewAccent)
                    .frame(width: 28, height: 28)
                Image(systemName: "mappin")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(RoamColors.text)
                Text(address)
                    .font(.system(size: 10))
                    .foregroundStyle(RoamColors.textMuted)
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .fill(RoamColors.reviewSuccess)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(10)
        .background(RoamColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(RoamColors.reviewBorder.opacity(0.6), lineWidth: 1)
        )
    }

    // MARK: - Shared pieces

    private var stepArrow: some View {
        Image(systemName: "arrow.down")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(RoamColors.reviewBorder)
            .padding(.vertical, 6)
    }

    private func stepLabelRow(
        number: String,
        @ViewBuilder title: () -> Text,
        hint: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(RoamFont.mono(12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(RoamColors.reviewAccent)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                title()
                    .font(.system(size: 13))
                    .foregroundStyle(RoamColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(RoamColors.textMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tipBox: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("💡")
                .font(.system(size: 14))
            (
                Text("Don't see Roam in your share sheet? ").fontWeight(.semibold)
                    + Text("Scroll right in the app row and tap ")
                    + Text("More").fontWeight(.semibold)
                    + Text(", then drag Roam to the top of the list. The more you use it, the higher it appears automatically.")
            )
            .font(.system(size: 11))
            .foregroundStyle(RoamColors.text)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoamColors.reviewAccentLight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(RoamColors.reviewAccent.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }
}

// MARK: - Small shape for “Tap here!” arrow

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
