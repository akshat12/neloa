import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var agent: LocalAgentService

    var body: some View {
        Form {
            Section("Local intelligence") {
                TextField("Model", text: $agent.modelName)
                Text("Humana looks for this model through Ollama at 127.0.0.1. If it is unavailable, safe built-in planning still handles simple date, amount, and replace-value instructions.")
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
