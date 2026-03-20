import SwiftUI

/// Roam light palette — matches `roam.*` in [frontend/tailwind.config.ts](frontend/tailwind.config.ts).
enum RoamColors {
    static let text = Color(red: 30 / 255, green: 26 / 255, blue: 46 / 255)
    static let textMid = Color(red: 107 / 255, green: 100 / 255, blue: 128 / 255)
    static let textMuted = Color(red: 168 / 255, green: 159 / 255, blue: 192 / 255)

    static let logan = Color(red: 171 / 255, green: 161 / 255, blue: 198 / 255)
    static let loganDeep = Color(red: 123 / 255, green: 111 / 255, blue: 168 / 255)
    static let loganDark = Color(red: 74 / 255, green: 64 / 255, blue: 112 / 255)

    static let lavender = Color(red: 223 / 255, green: 221 / 255, blue: 242 / 255)
    static let lavDeep = Color(red: 201 / 255, green: 197 / 255, blue: 232 / 255)

    static let greenTint = Color(red: 212 / 255, green: 237 / 255, blue: 218 / 255)
    static let greenDeep = Color(red: 74 / 255, green: 158 / 255, blue: 84 / 255)

    static let surface = Color.white.opacity(0.96)
    static let background = Color(red: 245 / 255, green: 243 / 255, blue: 250 / 255)

    static let notifDot = Color(red: 242 / 255, green: 184 / 255, blue: 203 / 255)
    static let error = Color(red: 229 / 255, green: 115 / 255, blue: 115 / 255)

    /// Reels grid: outline for items that need a user decision (review / promote).
    static let actionRequired = Color(red: 52 / 255, green: 120 / 255, blue: 246 / 255)

    /// Reels grid / device queue: server `processing` or pending upload to Roam.
    static let processingTeal = Color(red: 32 / 255, green: 150 / 255, blue: 155 / 255)

    /// Glass bar tint over material blur (see `.glass-bar` in frontend `index.css`).
    static let glassTint = Color(red: 245 / 255, green: 243 / 255, blue: 250 / 255).opacity(0.92)

    static let dotGridDot = Color(red: 171 / 255, green: 161 / 255, blue: 198 / 255).opacity(0.30)
}

/// Legacy name used by older auth screens; maps to Roam primary actions.
enum ThemeColors {
    static let background = RoamColors.background
    static let card = RoamColors.surface
    static let primary = RoamColors.loganDeep
    static let primaryForeground = Color.white
    static let secondary = RoamColors.lavender
    static let mutedForeground = RoamColors.textMid
    static let accent = RoamColors.greenDeep
    static let border = RoamColors.logan.opacity(0.2)
    static let shadow = Color.black.opacity(0.06)
}
