import SwiftUI

/// “Thick needle” split-R mark (matches auth HTML mock).
struct RoamNeedleLogoView: View {
    var size: CGFloat = 56

    private let ref: CGFloat = 100
    private let strokeRing = Color(red: 234 / 255, green: 230 / 255, blue: 242 / 255)
    private let dark = Color(red: 26 / 255, green: 26 / 255, blue: 46 / 255)
    private let accent = RoamColors.reviewAccent

    var body: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width, canvasSize.height) / ref
            context.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -ref / 2, y: -ref / 2)

            let ring = Path(ellipseIn: CGRect(x: 4, y: 4, width: 92, height: 92))
            context.stroke(ring, with: .color(strokeRing), lineWidth: size >= 44 ? 2 : 2.5)

            func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
                var p = Path()
                p.move(to: a)
                p.addLine(to: b)
                p.addLine(to: c)
                p.closeSubpath()
                return p
            }

            // Left half
            context.drawLayer { ctx in
                ctx.clip(to: Path(CGRect(x: 0, y: 0, width: 50, height: 100)))
                ctx.fill(
                    tri(CGPoint(x: 4, y: 50), CGPoint(x: 50, y: 41), CGPoint(x: 50, y: 59)),
                    with: .color(dark)
                )
                ctx.fill(
                    tri(CGPoint(x: 96, y: 50), CGPoint(x: 50, y: 41), CGPoint(x: 50, y: 59)),
                    with: .color(accent.opacity(0.1))
                )
                ctx.draw(
                    Text("R")
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent),
                    at: CGPoint(x: 50, y: 58),
                    anchor: .center
                )
            }

            // Right half
            context.drawLayer { ctx in
                ctx.clip(to: Path(CGRect(x: 50, y: 0, width: 50, height: 100)))
                ctx.fill(
                    tri(CGPoint(x: 96, y: 50), CGPoint(x: 50, y: 41), CGPoint(x: 50, y: 59)),
                    with: .color(accent)
                )
                ctx.fill(
                    tri(CGPoint(x: 4, y: 50), CGPoint(x: 50, y: 41), CGPoint(x: 50, y: 59)),
                    with: .color(dark.opacity(0.1))
                )
                ctx.draw(
                    Text("R")
                        .font(.system(size: 60, weight: .bold, design: .monospaced))
                        .foregroundStyle(dark),
                    at: CGPoint(x: 50, y: 58),
                    anchor: .center
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        RoamNeedleLogoView(size: 56)
        RoamNeedleLogoView(size: 28)
    }
    .padding()
}
