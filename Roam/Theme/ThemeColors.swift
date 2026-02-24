import SwiftUI

/// Colors matching frontend index.css (light theme): bright warm background, coral primary.
enum ThemeColors {
    /// Background: bright warm white (lighter than 30 40% 98%)
    static let background = Color(hue: 30/360, saturation: 0.15, brightness: 0.99)
    /// Card: bright off-white
    static let card = Color(hue: 30/360, saturation: 0.08, brightness: 1.0)
    /// Primary (warm coral/rose): 12 76% 61%
    static let primary = Color(hue: 12/360, saturation: 0.76, brightness: 0.61)
    /// Primary foreground (white on primary)
    static let primaryForeground = Color.white
    /// Secondary / muted: 30 30% 94%
    static let secondary = Color(hue: 30/360, saturation: 0.3, brightness: 0.94)
    /// Muted text: 20 10% 45%
    static let mutedForeground = Color(hue: 20/360, saturation: 0.1, brightness: 0.45)
    /// Accent (sage): 150 25% 45%
    static let accent = Color(hue: 150/360, saturation: 0.25, brightness: 0.45)
    /// Border: 30 20% 88%
    static let border = Color(hue: 30/360, saturation: 0.2, brightness: 0.88)
    /// Soft shadow
    static let shadow = Color.black.opacity(0.06)
}
