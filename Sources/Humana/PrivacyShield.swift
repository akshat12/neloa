import Foundation

enum PrivacyShield {
    private static let protectedBundleIdentifiers = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword",
        "com.bitwarden.desktop",
        "com.dashlane.Dashlane",
        "com.lastpass.LastPass"
    ]

    static func excludes(_ bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        if bundleIdentifier == Bundle.main.bundleIdentifier { return true }
        return protectedBundleIdentifiers.contains { protected in
            bundleIdentifier.caseInsensitiveCompare(protected) == .orderedSame ||
            bundleIdentifier.lowercased().hasPrefix(protected.lowercased() + ".")
        }
    }
}
