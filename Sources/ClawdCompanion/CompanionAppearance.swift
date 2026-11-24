import AppKit
import SwiftUI

enum CompanionAppearance {
    static func apply(_ mode: String) {
        switch mode {
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }

    static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(rgb >> 16 & 255) / 255,
                           green: CGFloat(rgb >> 8 & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }
}

enum Ink {
    static let base = pair(0xf6f0e8, 0x1b191a)
    static let card = pair(0xfffbf5, 0x262324)
    static let cream = pair(0x2e2426, 0xf7eee0)
    static let dim = pair(0x625455, 0xbfb6b1)
    static let coral = pair(0x9c452d, 0xffa983)
    static let mint = pair(0x306954, 0x9ed1ba)
    static let line = pair(0xd9c9be, 0x463f43)
    static let control = pair(0xeadfd4, 0x383337)

    static func pair(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: CompanionAppearance.color(light: light, dark: dark))
    }
}
