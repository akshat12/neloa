import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var agent: LocalAgentService
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var appearance: AppearanceController
    @State private var confirmDeleteRecordings = false
    @State private var confirmRemoveModel = false
    @State private var diagnosticsReport: DiagnosticsReport?

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                intelligenceCard
                appearanceCard

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        permissionsCard.frame(minWidth: 450, maxWidth: .infinity)
                        privacyCard.frame(minWidth: 360, maxWidth: .infinity)
                    }
                    VStack(spacing: 18) {
                        permissionsCard
                        privacyCard
                    }
                }

                localModelCard
                diagnosticsCard
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            permissions.refresh()
            agent.refreshModelStatus()
        }
        .alert("Delete all teaching recordings?", isPresented: $confirmDeleteRecordings) {
            Button("Delete recordings", role: .destructive) { store.deleteAllRecordings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your saved automations will remain, but their screen and narration recordings cannot be recovered.")
        }
        .alert("Remove the local visual model?", isPresented: $confirmRemoveModel) {
            Button("Remove model", role: .destructive) { Task { await agent.removeModel() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Neloa will keep your automations, recordings, and any other model tier. The selected tier can be downloaded again later.")
        }
        .sheet(item: $diagnosticsReport) { report in
            DiagnosticsPreviewView(report: report)
                .frame(width: 820, height: 680)
                .presentationSizing(.fitted)
        }
    }

    private var appearanceCard: some View {
        SettingsCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    appearanceSummary
                    Spacer(minLength: 20)
                    appearancePicker
                }

                VStack(alignment: .leading, spacing: 16) {
                    appearanceSummary
                    appearancePicker
                }
            }
        }
    }

    private var appearanceSummary: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 15)
                    .fill(LinearGradient(
                        colors: [NeloaPalette.lagoonDeep, NeloaPalette.lagoon],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Circle()
                    .fill(NeloaPalette.lagoonBright)
                    .frame(width: 17, height: 17)
                    .offset(x: -10, y: 9)
                Circle()
                    .fill(NeloaPalette.coral)
                    .frame(width: 14, height: 14)
                    .offset(x: 11, y: -10)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text("Appearance")
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Lagoon palette · Choose how Neloa looks on this Mac.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appearancePicker: some View {
        Picker("Theme", selection: $appearance.selection) {
            ForEach(AppAppearance.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .frame(width: 270)
        .accessibilityLabel("Appearance theme")
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
                    Text(intelligenceDescription)
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
                permissionRow(
                    "Screen recording",
                    icon: "rectangle.on.rectangle",
                    status: permissions.screen,
                    statusLabel: permissions.screenRestartNeeded ? "Restart to finish" : nil,
                    actionTitle: permissions.screenRestartNeeded ? "Restart Neloa" : "Grant",
                    permissionHelp: permissions.screenRestartNeeded
                        ? "macOS granted Screen Recording, but Neloa must restart before it can use the permission."
                        : "Neloa needs Screen Recording permission to record the apps you demonstrate."
                ) {
                    if permissions.screenRestartNeeded {
                        restartNeloa()
                    } else {
                        grantScreenRecording()
                    }
                }
                Divider()
                permissionRow(
                    "Clicks & Typing",
                    icon: "hand.tap",
                    status: permissions.accessibility,
                    permissionHelp: "Neloa needs Accessibility permission to capture clicks and typing and replay approved actions."
                ) {
                    grantAccessibility()
                }
                Divider()
                permissionRow(
                    "Voice",
                    icon: "waveform",
                    status: voicePermissionStatus,
                    permissionHelp: "Neloa needs Microphone and Speech Recognition permissions for spoken explanations and voice instructions."
                ) {
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

    private var localModelCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 5) {
                    Text("Local visual intelligence")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text("\(LocalModelPaths.displayName) · \(agent.selectedTier.precisionLabel) · Apple silicon")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)
                StatusBadge(label: modelStatusLabel, color: modelStatusColor)
            }

            Divider()

            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Model quality")
                        .font(.system(size: 13, weight: .semibold))
                    Picker("Model quality", selection: Binding(
                        get: { agent.selectedTier },
                        set: { tier in Task { await agent.selectTier(tier) } }
                    )) {
                        ForEach(LocalModelTier.allCases) { tier in
                            Text("\(tier.title) · \(tier.precisionLabel)").tag(tier)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(modelSelectionDisabled)
                    Text("\(agent.selectedTier.recommendation) · \(agent.selectedTier.downloadSizeLabel) download")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                modelStatusMessage

                if case .downloading(let progress) = agent.modelStatus {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                            .accessibilityLabel("Model download progress")
                            .accessibilityValue("\(Int(progress * 100)) percent")
                        Text("\(Int(progress * 100))% · Keep Neloa open while the first-time download finishes")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    modelAction
                    if canRemoveModel {
                        Button("Remove \(agent.selectedTier.precisionLabel) model…", role: .destructive) { confirmRemoveModel = true }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .tint(.red)
                    }
                    Spacer()
                    Label("\(agent.hardware.memoryLabel) memory", systemImage: "memorychip")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text("The model is downloaded directly inside Neloa and stays on this Mac. There is no Ollama setup, Terminal command, local server, account, or cloud upload.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var diagnosticsCard: some View {
        SettingsCard(title: "Support & diagnostics", icon: "stethoscope") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 18) {
                    diagnosticsDescription
                    Spacer(minLength: 20)
                    diagnosticsButton
                }
                VStack(alignment: .leading, spacing: 14) {
                    diagnosticsDescription
                    diagnosticsButton
                }
            }
        }
    }

    private var diagnosticsDescription: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Create a report you can inspect before sharing")
                .font(.system(size: 15, weight: .semibold))
            Text("Includes versions, health, and structural counts. Never includes recordings, transcripts, typed values, paths, workflow names, click positions, or failure messages.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var diagnosticsButton: some View {
        Button {
            permissions.refresh()
            agent.refreshModelStatus()
            diagnosticsReport = DiagnosticsReportBuilder.makeLive(
                store: store,
                permissions: permissions,
                agent: agent
            )
        } label: {
            Label("Preview diagnostics", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    @ViewBuilder
    private var modelStatusMessage: some View {
        switch agent.modelStatus {
        case .checking:
            Label("Checking the local model…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notInstalled:
            Label("Download once to let Neloa understand the screen around each captured action.", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.secondary)
        case .downloading:
            Label("Downloading \(agent.selectedTier.downloadSizeLabel) directly to this Mac…", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .loading:
            Label("Loading the local model into memory…", systemImage: "memorychip")
                .foregroundStyle(Color.accentColor)
        case .removing:
            Label("Finishing up…", systemImage: "hourglass")
                .foregroundStyle(Color.accentColor)
        case .ready:
            Label("Ready to understand recordings and plan custom runs privately.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var modelAction: some View {
        switch agent.modelStatus {
        case .notInstalled:
            Button("Download \(agent.selectedTier.precisionLabel) model · \(agent.selectedTier.downloadSizeLabel)") {
                Task { await agent.setupModel() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        case .failed:
            Button("Try again") { Task { await agent.setupModel() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .downloading, .loading:
            Button("Cancel download") { Task { await agent.cancelModelSetup() } }
                .buttonStyle(.bordered)
                .controlSize(.large)
        case .checking:
            Button("Load model") { Task { await agent.setupModel() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        case .unavailable, .removing, .ready:
            EmptyView()
        }
    }

    private var modelStatusLabel: String {
        switch agent.modelStatus {
        case .checking: "Checking"
        case .unavailable: "Unavailable"
        case .notInstalled: "Not installed"
        case .downloading: "Downloading"
        case .loading: "Loading"
        case .removing: "Working"
        case .ready: "Ready"
        case .failed: "Needs attention"
        }
    }

    private var modelStatusColor: Color {
        switch agent.modelStatus {
        case .ready: .green
        case .failed, .unavailable: .orange
        case .downloading, .loading, .removing: Color.accentColor
        case .checking, .notInstalled: .secondary
        }
    }

    private var consumerStatus: String {
        agent.modelStatus == .ready ? "Ready" : "Basic"
    }

    private var canRemoveModel: Bool {
        guard LocalModelPaths.hasCachedFiles(for: agent.selectedTier) else { return false }
        return switch agent.modelStatus {
        case .downloading, .loading, .removing: false
        default: true
        }
    }

    private var modelSelectionDisabled: Bool {
        switch agent.modelStatus {
        case .downloading, .loading, .removing: true
        default: false
        }
    }

    private var intelligenceDescription: String {
        if agent.modelStatus == .ready {
            return "Neloa interprets recordings and plans changes on this Mac without using a cloud model."
        }
        return "Basic mode records and replays workflows. The optional local model also interprets what appears on screen."
    }

    private var voicePermissionStatus: PermissionCenter.Status {
        if permissions.microphone == .granted && permissions.speech == .granted { return .granted }
        if permissions.microphone == .denied || permissions.speech == .denied { return .denied }
        return .unknown
    }

    private func permissionRow(
        _ title: String,
        icon: String,
        status: PermissionCenter.Status,
        statusLabel: String? = nil,
        actionTitle: String = "Grant",
        permissionHelp: String,
        grant: @escaping () -> Void
    ) -> some View {
        let appearance = permissionAppearance(status)
        return HStack(spacing: 11) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer(minLength: 10)
            Label(
                statusLabel ?? appearance.label,
                systemImage: status == .granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(appearance.color)
            .help(status == .granted ? "\(title) is ready." : permissionHelp)
            if status != .granted {
                Button(actionTitle, action: grant)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help(permissionHelp)
            }
        }
        .padding(.vertical, 8)
    }

    private func permissionAppearance(_ status: PermissionCenter.Status) -> (label: String, color: Color) {
        switch status {
        case .granted: ("Ready", .green)
        case .denied: ("Permission needed", .red)
        case .unknown: ("Permission required", .red)
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

    private func restartNeloa() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            guard error == nil else { return }
            NSApplication.shared.terminate(nil)
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
