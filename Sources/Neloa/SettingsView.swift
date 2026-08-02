import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var agent: LocalAgentService
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var store: WorkflowStore
    @State private var confirmDeleteRecordings = false

    var body: some View {
        Form {
            Section("On-device intelligence") {
                LabeledContent("Processing", value: "On this Mac")
                LabeledContent("Status", value: consumerStatus)
                Text("Neloa plans changes without sending your workflow or recordings to a cloud model.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Permissions") {
                LabeledContent("Screen recording", value: permissions.screen.label)
                LabeledContent("Clicks and typing", value: permissions.inputMonitoring.label)
                LabeledContent("Replay actions", value: permissions.accessibility.label)
                LabeledContent("Voice", value: voicePermissionLabel)
                Button("Open macOS Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section("Privacy") {
                LabeledContent("Storage", value: "Only on this Mac")
                LabeledContent("Protected apps", value: "Password managers hidden")
                Text("Neloa automatically excludes common password managers and Keychain Access from recordings and learned keystrokes. Avoid showing other secrets while teaching.")
                    .font(.callout)
                Button("Show saved data in Finder") { showSavedData() }
                Button("Delete all teaching recordings…", role: .destructive) {
                    confirmDeleteRecordings = true
                }
            }
            DisclosureGroup("Advanced model fallback") {
                TextField("Local Qwen model", text: $agent.modelName)
                Text("Used through Ollama only if Apple’s on-device intelligence is unavailable.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 680, maxHeight: .infinity)
        .onAppear { permissions.refresh() }
        .alert("Delete all teaching recordings?", isPresented: $confirmDeleteRecordings) {
            Button("Delete recordings", role: .destructive) { store.deleteAllRecordings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved automations will remain, but their screen and narration recordings cannot be recovered.")
        }
    }

    private var consumerStatus: String {
        agent.status.contains("unavailable") ? "Limited" : "Ready"
    }

    private var voicePermissionLabel: String {
        permissions.microphone == .granted && permissions.speech == .granted ? "Ready" : "Not ready"
    }

    private func showSavedData() {
        let base = BrandMigration.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        NSWorkspace.shared.open(base)
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var agent: LocalAgentService

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Settings", subtitle: "Control Neloa’s private, on-device intelligence.")
            SettingsView()
                .environmentObject(agent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(32)
    }
}
