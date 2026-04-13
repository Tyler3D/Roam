import SwiftUI

/// Branded loading screen shown during auth init, backend sync, and store bootstrap.
/// Displays a pill logo with a breathing animation over a clean lavender background with a soft radial glow.
struct SplashScreen: View {
    var status: String = "Loading…"

    @State private var logoBreathing = false
    @State private var textVisible = false

    var body: some View {
        ZStack {
            // Base background
            RoamColors.background
                .ignoresSafeArea()

            // Soft radial glow centered on screen
            RadialGradient(
                colors: [
                    RoamColors.lavender.opacity(0.65),
                    RoamColors.background.opacity(0)
                ],
                center: .center,
                startRadius: 0,
                endRadius: 260
            )
            .ignoresSafeArea()

            // Center content
            VStack(spacing: 28) {
                // Pill logo with breathing animation
                SplashPillLogo()
                    .scaleEffect(logoBreathing ? 1.03 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                        value: logoBreathing
                    )

                VStack(spacing: 10) {
                    // App name
                    Text("roam")
                        .font(RoamFont.display(28, italic: true))
                        .foregroundStyle(RoamColors.loganDark)
                        .opacity(textVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.6), value: textVisible)

                    // Status label
                    Text(status.lowercased())
                        .font(RoamFont.mono(10))
                        .tracking(1.5)
                        .foregroundStyle(RoamColors.textMuted)
                        .opacity(textVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.1), value: textVisible)
                }
            }
        }
        .onAppear {
            logoBreathing = true
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                textVisible = true
            }
        }
    }
}

/// Pill-shaped logo matching the Roam brand mark — light lavender to deep purple gradient with a glossy highlight.
private struct SplashPillLogo: View {
    var body: some View {
        ZStack {
            // Main capsule fill
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 232 / 255, green: 228 / 255, blue: 250 / 255), // light lavender
                            RoamColors.loganDark                                       // deep purple
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Inner glossy highlight — curved white stroke on the left edge
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.80),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: UnitPoint(x: 0.25, y: 0.65)
                    ),
                    lineWidth: 2.5
                )
                .padding(3)
        }
        .frame(width: 62, height: 120)
        .shadow(color: RoamColors.loganDeep.opacity(0.28), radius: 28, x: 0, y: 14)
    }
}

#Preview("Default") {
    SplashScreen()
}

#Preview("Syncing") {
    SplashScreen(status: "Syncing…")
}
