import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appAppearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolve(_ rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? .system
    }
}

enum NeloaPalette {
    static let lagoonDeep = Color(red: 0.02, green: 0.19, blue: 0.25)
    static let lagoon = Color(red: 0.00, green: 0.50, blue: 0.52)
    static let lagoonBright = Color(red: 0.27, green: 0.78, blue: 0.76)
    static let coral = Color(red: 1.00, green: 0.40, blue: 0.38)

    static let accent = Color(nsColor: NSColor(name: NSColor.Name("NeloaLagoonAccent")) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(calibratedRed: 0.27, green: 0.78, blue: 0.76, alpha: 1)
        }
        return NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.50, alpha: 1)
    })
}
