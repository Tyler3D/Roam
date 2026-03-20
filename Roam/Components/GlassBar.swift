import SwiftUI
import UIKit

/// Frosted strip like `.glass-bar` + roam tint ([frontend/src/index.css](frontend/src/index.css)).
struct GlassBarBackground: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            RoamColors.glassTint
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(RoamColors.logan.opacity(0.15))
                .frame(height: 1 / UIScreen.main.scale)
        }
    }
}
