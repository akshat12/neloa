import AppKit
import CoreFoundation
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

    func colorScheme(system: ColorScheme) -> ColorScheme {
        switch self {
        case .system: system
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolve(_ rawValue: String) -> AppAppearance {
        AppAppearance(rawValue: rawValue) ?? .system
    }
}

@MainActor
final class AppearanceController: ObservableObject {
    @Published var selection: AppAppearance {
        didSet {
            defaults.set(selection.rawValue, forKey: AppAppearance.storageKey)
        }
    }
    @Published private var systemColorScheme = AppearanceController.currentSystemColorScheme

    var colorScheme: ColorScheme {
        selection.colorScheme(system: systemColorScheme)
    }

    private let defaults: UserDefaults
    private var themeObserver: NSObjectProtocol?

    static var currentSystemColorScheme: ColorScheme {
        // Read the global preference directly. UserDefaults.standard can expose
        // Neloa's current forced appearance while the app is running, which makes
        // Dark look like the system setting and breaks Dark -> System.
        let style = CFPreferencesCopyValue(
            "AppleInterfaceStyle" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ) as? String
        return style == "Dark" ? .dark : .light
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = AppAppearance.resolve(defaults.string(forKey: AppAppearance.storageKey) ?? AppAppearance.system.rawValue)
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.systemColorScheme = Self.currentSystemColorScheme
            }
        }
    }

    deinit {
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
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
