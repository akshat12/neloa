import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var agent: LocalAgentService
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var store: WorkflowStore
    @State private var confirmDeleteRecordings = false
    @State private var showAdvanced = false
    @State private var copiedPullCommand = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                intelligenceCard

                HStack(alignment: .top, spacing: 18) {
                    permissionsCard.frame(maxWidth: .infinity)
                    privacyCard.frame(maxWidth: .infinity)
                }

                advancedCard
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { permissions.refresh() }
        .task(id: agent.modelName) {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await agent.refreshFallbackStatus()
        }
        .alert("Delete all teaching recordings?", isPresented: $confirmDeleteRecordings) {
            Button("Delete recordings", role: .destructive) { store.deleteAllRecordings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved automations will remain, but their screen and narration recordings cannot be recovered.")
        }
    }

    private var intelligenceCard: some View {
        SettingsCard {
            HStack(spacing: 18) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 4) {
                    Text("On-device intelligence")
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Neloa plans changes without sending your workflow or recordings to a cloud model.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 20)

                VStack(alignment: .trailing, spacing: 8) {
                    StatusBadge(label: consumerStatus, color: consumerStatus == "Ready" ? .green : .orange)
                    Label("On this Mac", systemImage: "laptopcomputer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var permissionsCard: some View {
        SettingsCard(title: "Permissions", icon: "checkmark.shield") {
            VStack(spacing: 0) {
                permissionRow("Screen recording", icon: "rectangle.on.rectangle", status: permissions.screen) {
                    grantScreenRecording()
                }
                Divider()
                permissionRow("Clicks, typing & replay", icon: "hand.tap", status: permissions.accessibility) {
                    grantAccessibility()
                }
                Divider()
                permissionRow("Voice", icon: "waveform", status: voicePermissionStatus) {
                    grantVoice()
                }
            }

            Button {
                openPrivacySettings()
            } label: {
                Label("Open macOS Privacy Settings", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var privacyCard: some View {
        SettingsCard(title: "Privacy", icon: "lock.shield") {
            VStack(spacing: 0) {
                settingsRow(title: "Storage", icon: "internaldrive", value: "On this Mac", color: .green)
                Divider()
                settingsRow(title: "Protected apps", icon: "eye.slash", value: "Automatically hidden", color: .green)
            }

            Text("Neloa excludes common password managers and Keychain Access from recordings and learned keystrokes. Avoid showing other secrets while teaching.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    privacyButtons
                }
                VStack(alignment: .leading, spacing: 10) {
                    privacyButtons
                }
            }
        }
    }

    @ViewBuilder
    private var privacyButtons: some View {
        Button {
            showSavedData()
        } label: {
            Label("Show saved data", systemImage: "folder")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)

        Button(role: .destructive) {
            confirmDeleteRecordings = true
        } label: {
            Label("Delete recordings…", systemImage: "trash")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.red)
    }

    private var advancedCard: some View {
        SettingsCard {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cpu")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Advanced model fallback").font(.system(size: 16, weight: .semibold))
                        Text("Optional local model for Macs without Apple Intelligence")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    StatusBadge(label: fallbackStatusLabel, color: fallbackStatusColor)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(showAdvanced ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdvanced {
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    fallbackStatusMessage

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Ollama model")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("Local model name", text: $agent.modelName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { Task { await agent.refreshFallbackStatus() } }
                        }
                        .frame(maxWidth: 380)

                        Button("Check again") {
                            Task { await agent.refreshFallbackStatus() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(agent.fallbackStatus == .checking)

                        fallbackAction
                    }

                    Text("Apple’s on-device intelligence remains the first choice. Neloa uses this model only when Apple Intelligence is unavailable or cannot complete a plan.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var fallbackStatusMessage: some View {
        switch agent.fallbackStatus {
        case .checking:
            Label("Checking the local model…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .ollamaUnavailable:
            Label("Ollama is not installed or is not running on this Mac.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .modelMissing:
            Label("Ollama is running, but \(agent.modelName) has not been downloaded.", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.orange)
        case .ready:
            Label("\(agent.modelName) is installed and ready for private, local use.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var fallbackAction: some View {
        switch agent.fallbackStatus {
        case .ollamaUnavailable:
            Button("Get Ollama") { openOllamaDownload() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .modelMissing:
            Button(copiedPullCommand ? "Copied" : "Copy download command") { copyPullCommand() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .checking, .ready:
            EmptyView()
        }
    }

    private var fallbackStatusLabel: String {
        switch agent.fallbackStatus {
        case .checking: "Checking"
        case .ollamaUnavailable: "Needs Ollama"
        case .modelMissing: "Needs model"
        case .ready: "Ready"
        }
    }

    private var fallbackStatusColor: Color {
        switch agent.fallbackStatus {
        case .checking: .secondary
        case .ollamaUnavailable, .modelMissing: .orange
        case .ready: .green
        }
    }

    private var consumerStatus: String {
        agent.status.contains("unavailable") ? "Limited" : "Ready"
    }

    private var voicePermissionStatus: PermissionCenter.Status {
        if permissions.microphone == .granted && permissions.speech == .granted { return .granted }
        if permissions.microphone == .denied || permissions.speech == .denied { return .denied }
        return .unknown
    }

    private func permissionRow(_ title: String, icon: String, status: PermissionCenter.Status, grant: @escaping () -> Void) -> some View {
        let appearance = permissionAppearance(status)
        return HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer(minLength: 10)
            Text(appearance.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(appearance.color)
            if status != .granted {
                Button("Grant", action: grant)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 8)
    }

    private func permissionAppearance(_ status: PermissionCenter.Status) -> (label: String, color: Color) {
        switch status {
        case .granted: ("Ready", .green)
        case .denied: ("Needs permission", .orange)
        case .unknown: ("Not requested", .secondary)
        }
    }

    private func settingsRow(title: String, icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.vertical, 10)
    }

    private func openPrivacySettings() {
        openPrivacyPane("Privacy")
    }

    private func grantScreenRecording() {
        permissions.requestScreen()
        if permissions.screen != .granted {
            openPrivacyPane("Privacy_ScreenCapture", after: 0.45)
        }
    }

    private func grantAccessibility() {
        permissions.requestAccessibility()
        if permissions.accessibility == .denied {
            openPrivacyPane("Privacy_Accessibility", after: 0.35)
        }
    }

    private func grantVoice() {
        Task {
            await permissions.requestMicrophoneAndSpeech()
            if permissions.microphone == .denied {
                openPrivacyPane("Privacy_Microphone")
            } else if permissions.speech == .denied {
                openPrivacyPane("Privacy_SpeechRecognition")
            }
        }
    }

    private func openPrivacyPane(_ anchor: String, after delay: TimeInterval = 0) {
        let open = {
            let modernRoute = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)")
            let legacyRoute = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
            if let modernRoute, NSWorkspace.shared.open(modernRoute) {
                return
            }
            if let legacyRoute {
                NSWorkspace.shared.open(legacyRoute)
            }
        }

        if delay == 0 {
            open()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: open)
        }
    }

    private func showSavedData() {
        let base = BrandMigration.applicationSupportDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        NSWorkspace.shared.open(base)
    }

    private func openOllamaDownload() {
        guard let url = URL(string: "https://ollama.com/download/mac") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyPullCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ollama pull \(agent.modelName)", forType: .string)
        copiedPullCommand = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedPullCommand = false
        }
    }
}

private struct SettingsCard<Content: View>: View {
    var title: String?
    var icon: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title, let icon {
                Label(title, systemImage: icon)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
            }
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.secondary.opacity(0.14)))
        .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
    }
}

private struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.11), in: Capsule())
    }
}

struct SettingsPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(title: "Settings", subtitle: "Control Neloa’s private, on-device intelligence.")
            SettingsView()
        }
        .padding(32)
    }
}
