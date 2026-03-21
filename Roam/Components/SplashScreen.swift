import SwiftUI

/// Branded loading screen shown during auth init, backend sync, and store bootstrap.
/// Displays the compass logo with a breathing animation over blurred, sliding background images.
struct SplashScreen: View {
    var status: String = "Loading…"

    @State private var offset: CGFloat = 0
    @State private var logoBreathing = false
    @State private var textVisible = false

    /// Total width of one image pair (two images side-by-side).
    /// We duplicate the pair so it loops seamlessly.
    private let stripUnitWidth: CGFloat = UIScreen.main.bounds.width * 2

    var body: some View {
        ZStack {
            RoamColors.background
                .ignoresSafeArea()

            // Sliding blurred background
            slidingBackground
                .ignoresSafeArea()

            // Center content
            VStack(spacing: 20) {
                // Breathing compass logo
                RoamNeedleLogoView(size: 80)
                    .scaleEffect(logoBreathing ? 1.04 : 1.0)
                    .opacity(logoBreathing ? 0.85 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: logoBreathing
                    )

                // App name
                Text("roam")
                    .font(RoamFont.display(28, italic: true))
                    .foregroundStyle(RoamColors.text)
                    .opacity(textVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.6), value: textVisible)

                // Status label
                Text(status)
                    .font(RoamFont.mono(10))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(RoamColors.textMuted)
                    .opacity(textVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.6).delay(0.1), value: textVisible)
            }
        }
        .onAppear {
            logoBreathing = true
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                textVisible = true
            }
        }
    }

    @ViewBuilder
    private var slidingBackground: some View {
        GeometryReader { geo in
            let imageHeight = geo.size.height
            let imageWidth = geo.size.width

            HStack(spacing: 0) {
                // First pair
                Image("splash_bg_1")
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageWidth, height: imageHeight)
                    .clipped()
                Image("splash_bg_2")
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageWidth, height: imageHeight)
                    .clipped()
                // Duplicate pair for seamless loop
                Image("splash_bg_1")
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageWidth, height: imageHeight)
                    .clipped()
                Image("splash_bg_2")
                    .resizable()
                    .scaledToFill()
                    .frame(width: imageWidth, height: imageHeight)
                    .clipped()
            }
            .offset(x: offset)
            .onAppear {
                // Slide leftward by one pair width, then jump back
                let pairWidth = imageWidth * 2
                withAnimation(
                    .linear(duration: 28)
                    .repeatForever(autoreverses: false)
                ) {
                    offset = -pairWidth
                }
            }
            .blur(radius: 2)
            .saturation(0.5)
            .brightness(0.02)
            .opacity(0.45)
        }
    }
}

#Preview("Default") {
    SplashScreen()
}

#Preview("Syncing") {
    SplashScreen(status: "Syncing…")
}
