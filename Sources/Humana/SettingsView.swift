import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var agent: LocalAgentService

    var body: some View {
        Form {
            Section("Local intelligence") {
                LabeledContent("Primary", value: "Apple on-device model")
                TextField("Qwen fallback", text: $agent.modelName)
                Text("On macOS 26, Humana first uses Apple's private on-device model. If it is unavailable, Humana looks for this Qwen model through Ollama at 127.0.0.1. A safe built-in planner remains available for simple replacements.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Status", value: agent.status)
            }
            Section("Privacy") {
                Text("Recordings and saved automations stay on this Mac. Humana only connects to the local model address above.")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 310)
        .padding()
    }
}
