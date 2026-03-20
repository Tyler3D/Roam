import SwiftUI

/// Matches `.dot-grid` in [frontend/src/index.css](frontend/src/index.css).
struct DotGridBackground: View {
    var dotOpacity: Double = 0.28
    var spacing: CGFloat = 20
    var dotRadius: CGFloat = 0.8

    var body: some View {
        Canvas { context, size in
            let dotColor = RoamColors.dotGridDot.opacity(dotOpacity / 0.30)
            for x in stride(from: 0, to: size.width + spacing, by: spacing) {
                for y in stride(from: 0, to: size.height + spacing, by: spacing) {
                    let rect = CGRect(x: x, y: y, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(dotColor)
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}
