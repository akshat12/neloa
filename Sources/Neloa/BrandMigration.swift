import Foundation

enum BrandMigration {
    static let legacyBundleIdentifier = "ai.humana.desktop"
    static let legacyApplicationSupportName = "Humana"
    static let applicationSupportName = "Neloa"

    static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(applicationSupportName, isDirectory: true)
    }

    static var legacyApplicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent(legacyApplicationSupportName, isDirectory: true)
    }

    static func migrateUserDefaults() {
        guard let legacy = UserDefaults(suiteName: legacyBundleIdentifier) else { return }
        let current = UserDefaults.standard
        for key in ["hasCompletedOnboarding", "localModelName"] where current.object(forKey: key) == nil {
            if let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
    }

    static func migrateApplicationSupportIfNeeded() throws {
        let manager = FileManager.default
        let legacy = legacyApplicationSupportDirectory
        let current = applicationSupportDirectory
        guard manager.fileExists(atPath: legacy.path), !manager.fileExists(atPath: current.path) else { return }
        try manager.moveItem(at: legacy, to: current)
    }

    static func repairedAssetPath(_ path: String?) -> String? {
        guard let path, path.hasPrefix(legacyApplicationSupportDirectory.path) else { return path }
        return applicationSupportDirectory.path + path.dropFirst(legacyApplicationSupportDirectory.path.count)
    }
}
