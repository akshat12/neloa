import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class NeloaAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private(set) static var pendingRunWorkflowID: UUID?

    static func consumePendingRunWorkflowID() -> UUID? {
        defer { pendingRunWorkflowID = nil }
        return pendingRunWorkflowID
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let workflowID = urls.lazy.compactMap(NeloaDeepLink.runWorkflowID).first else { return }
        routeToReviewedRun(workflowID)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        WorkflowEvidenceExtractor.purgeStaleTemporaryEvidence()
        UNUserNotificationCenter.current().delegate = self
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else { return }
        NSApplication.shared.applicationIconImage = icon
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let workflowID = response.notification.request.content.userInfo["workflowID"] as? String else { return }
        await MainActor.run {
            guard let workflowID = UUID(uuidString: workflowID) else { return }
            self.routeToReviewedRun(workflowID)
        }
    }

    private func routeToReviewedRun(_ workflowID: UUID) {
        Self.pendingRunWorkflowID = workflowID
        NSApplication.shared.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .openRequestedAutomation, object: workflowID.uuidString)
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
    @StateObject private var schedules = AutomationScheduleCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(teacher)
                .environmentObject(agent)
                .environmentObject(runner)
                .environmentObject(permissions)
                .environmentObject(appearance)
                .environmentObject(schedules)
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
        } else if CommandLine.arguments.contains("--model-eval") || CommandLine.arguments.contains("--model-eval-8bit") {
            Task { @MainActor in
                do {
                    let tier: LocalModelTier = CommandLine.arguments.contains("--model-eval-8bit") ? .quality8Bit : .balanced4Bit
                    let defaultReport = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                        .appendingPathComponent("neloa-model-eval-\(tier.precisionLabel).json")
                    let reportURL = ProcessInfo.processInfo.environment["NELOA_MODEL_EVAL_REPORT"]
                        .map { URL(fileURLWithPath: $0) } ?? defaultReport
                    let report = try await ModelEvaluation.run(tier: tier, reportURL: reportURL)
                    Foundation.exit(report.passed ? 0 : 1)
                } catch {
                    fputs("Neloa model evaluation could not run: \(error)\n", stderr)
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
        } else if CommandLine.arguments.contains("--qwen-recording-test") {
            Task { @MainActor in
                do {
                    guard let path = ProcessInfo.processInfo.environment["NELOA_RECORDING_PATH"] else {
                        throw SelfTests.Failure(description: "NELOA_RECORDING_PATH is required")
                    }
                    try await SelfTests.qwenRecordingTest(recordingPath: path)
                    print("Neloa Qwen recording test passed")
                    Foundation.exit(0)
                } catch {
                    fputs("Neloa Qwen recording test failed: \(error)\n", stderr)
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
