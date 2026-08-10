import AppKit
import SwiftUI

@MainActor
final class NeloaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        WorkflowEvidenceExtractor.purgeStaleTemporaryEvidence()
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = icon
    }
}

struct NeloaApp: App {
    @NSApplicationDelegateAdaptor(NeloaAppDelegate.self) private var appDelegate
    @StateObject private var appearance = AppearanceController()
    @StateObject private var store = WorkflowStore()
    @StateObject private var teacher = TeachController()
    @StateObject private var agent = LocalAgentService()
    @StateObject private var runner = AutomationRunner()
    @StateObject private var permissions = PermissionCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(teacher)
                .environmentObject(agent)
                .environmentObject(runner)
                .environmentObject(permissions)
                .environmentObject(appearance)
                .tint(NeloaPalette.accent)
                .accentColor(NeloaPalette.accent)
                .preferredColorScheme(appearance.colorScheme)
                .frame(minWidth: 1_080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_280, height: 820)

        Settings {
            SettingsView()
                .environmentObject(agent)
                .environmentObject(store)
                .environmentObject(permissions)
                .environmentObject(appearance)
                .tint(NeloaPalette.accent)
                .accentColor(NeloaPalette.accent)
                .preferredColorScheme(appearance.colorScheme)
                .padding(24)
                .frame(minWidth: 760, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Show Welcome") {
                    NotificationCenter.default.post(name: .showNeloaWelcome, object: nil)
                }
                Button("Show Guided Tour") {
                    NotificationCenter.default.post(name: .showNeloaTour, object: nil)
                }
            }
        }
    }
}

@main
enum NeloaMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            do {
                try SelfTests.run()
                print("Neloa self-tests passed")
            } catch {
                fputs("Neloa self-tests failed: \(error)\n", stderr)
                Foundation.exit(1)
            }
        } else if CommandLine.arguments.contains("--agent-smoke-test") {
            Task { @MainActor in
                do {
                    try await SelfTests.agentSmokeTest()
                    print("Neloa on-device agent smoke test passed")
                    Foundation.exit(0)
                } catch {
                    fputs("Neloa on-device agent smoke test failed: \(error)\n", stderr)
                    Foundation.exit(1)
                }
            }
            dispatchMain()
        } else if CommandLine.arguments.contains("--qwen-smoke-test") || CommandLine.arguments.contains("--qwen-8bit-smoke-test") {
            Task { @MainActor in
                do {
                    let tier: LocalModelTier = CommandLine.arguments.contains("--qwen-8bit-smoke-test") ? .quality8Bit : .balanced4Bit
                    try await SelfTests.qwenSmokeTest(tier: tier)
                    print("Neloa Qwen visual model smoke test passed")
                    Foundation.exit(0)
                } catch {
                    fputs("Neloa Qwen visual model smoke test failed: \(error)\n", stderr)
                    Foundation.exit(1)
                }
            }
            dispatchMain()
        } else {
            BrandMigration.migrateUserDefaults()
            NeloaApp.main()
        }
    }
}
