import SwiftUI
import UIKit

/// Typography aligned with [frontend/tailwind.config.ts](frontend/tailwind.config.ts) (font-mono, display, notes).
enum RoamFont {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if UIFont(name: "DMMono-Regular", size: size) != nil {
            return Font.custom("DM Mono", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        if italic {
            if UIFont(name: "DMSerifDisplay-Italic", size: size) != nil {
                return .custom("DM Serif Display", size: size)
            }
        } else if UIFont(name: "DMSerifDisplay-Regular", size: size) != nil {
            return .custom("DM Serif Display", size: size)
        }
        return .system(size: size, weight: .regular, design: .serif)
    }

    static func notes(_ size: CGFloat, italic: Bool = true) -> Font {
        if italic {
            if UIFont(name: "Lora-Italic", size: size) != nil {
                return .custom("Lora", size: size)
            }
        } else if UIFont(name: "Lora-Regular", size: size) != nil {
            return .custom("Lora", size: size)
        }
        return .system(size: size, design: .serif)
    }
}
