import SwiftUI

/// Light collection map chrome — aligned with the Roam “Collection Map (Light)” HTML concept.
enum RoamMapChrome {
    static let bg = Color(red: 245 / 255, green: 244 / 255, blue: 248 / 255)
    static let surface = Color.white
    static let border = Color(red: 221 / 255, green: 216 / 255, blue: 232 / 255)
    static let borderLight = Color(red: 234 / 255, green: 230 / 255, blue: 242 / 255)
    static let text = Color(red: 26 / 255, green: 26 / 255, blue: 46 / 255)
    static let textMuted = Color(red: 124 / 255, green: 120 / 255, blue: 149 / 255)
    static let accent = Color(red: 108 / 255, green: 92 / 255, blue: 231 / 255)
    static let accentGlow = Color(red: 108 / 255, green: 92 / 255, blue: 231 / 255).opacity(0.08)
    static let glass = Color.white.opacity(0.88)
    /// “You” pin / legend — matches mock `--you-color`.
    static let youTeal = Color(red: 46 / 255, green: 204 / 255, blue: 135 / 255)
}

enum MapPlaceCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case restaurant = "Restaurant"
    case bar = "Bar"
    case cafe = "Café"
    /// Catch-all for parks/nature **and** anything that isn’t restaurant / bar / café.
    case other = "Other"

    var id: String { rawValue }

    /// Buckets API `category` strings into filter keys (best-effort).
    static func bucket(for pin: APIClient.CollectionMapPinDTO) -> String {
        let c = (pin.category ?? "").lowercased()
        if c.contains("restaurant") || c.contains("food") || c.contains("dining") { return "restaurant" }
        if c.contains("bar") || c.contains("pub") || c.contains("cocktail") || c.contains("wine") { return "bar" }
        if c.contains("cafe") || c.contains("café") || c.contains("coffee") || c.contains("bakery") { return "cafe" }
        if c.contains("park") || c.contains("outdoor") || c.contains("trail") || c.contains("beach") || c.contains("garden") {
            return "outdoor"
        }
        return "other"
    }

    func matches(_ pin: APIClient.CollectionMapPinDTO) -> Bool {
        if self == .all { return true }
        let b = Self.bucket(for: pin)
        switch self {
        case .all: return true
        case .restaurant: return b == "restaurant"
        case .bar: return b == "bar"
        case .cafe: return b == "cafe"
        case .other: return b == "outdoor" || b == "other"
        }
    }
}
