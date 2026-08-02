import AppKit
import SwiftUI

@MainActor
final class HumanaAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = icon
    }
}

struct HumanaApp: App {
    @NSApplicationDelegateAdaptor(HumanaAppDelegate.self) private var appDelegate
    @StateObject private var store = WorkflowStore()
    @StateObject private var teacher = TeachController()
    @StateObject private var agent = LocalAgentService()
    @StateObject private var runner = AutomationRunner()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(teacher)
                .environmentObject(agent)
                .environmentObject(runner)
                .frame(minWidth: 1_080, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_280, height: 820)

        Settings {
            SettingsView()
                .environmentObject(agent)
        }
        .commands {
            CommandGroup(after: .help) {
                Button("Show Welcome") {
                    NotificationCenter.default.post(name: .showHumanaWelcome, object: nil)
                }
            }
        }
    }
}

@main
enum HumanaMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            do {
                try SelfTests.run()
                print("Humana self-tests passed")
            } catch {
                fputs("Humana self-tests failed: \(error)\n", stderr)
                Foundation.exit(1)
            }
        } else if CommandLine.arguments.contains("--agent-smoke-test") {
            Task { @MainActor in
                do {
                    try await SelfTests.agentSmokeTest()
                    print("Humana on-device agent smoke test passed")
                    Foundation.exit(0)
                } catch {
                    fputs("Humana on-device agent smoke test failed: \(error)\n", stderr)
                    Foundation.exit(1)
                }
            }
            dispatchMain()
        } else {
            HumanaApp.main()
        }
    }
}
