import SwiftUI

struct HumanaApp: App {
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
        } else {
            HumanaApp.main()
        }
    }
}
