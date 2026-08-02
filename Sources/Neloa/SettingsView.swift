import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var agent: LocalAgentService
    @EnvironmentObject private var permissions: PermissionCenter
    @EnvironmentObject private var store: WorkflowStore
    @State private var confirmDeleteRecordings = false
    @State private var showAdvanced = false

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
                permissionRow("Screen recording", icon: "rectangle.on.rectangle", status: permissions.screen)
                Divider()
                permissionRow("Clicks and typing", icon: "cursorarrow.click", status: permissions.inputMonitoring)
                Divider()
                permissionRow("Replay actions", icon: "hand.tap", status: permissions.accessibility)
                Divider()
                settingsRow(title: "Voice", icon: "waveform", value: voicePermissionLabel, color: voicePermissionColor)
            }

            Button {
                openPrivacySettings()
            } label: {
                Label("Open macOS Privacy Settings", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
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
        .buttonStyle(.bordered)

        Button(role: .destructive) {
            confirmDeleteRecordings = true
        } label: {
            Label("Delete recordings…", systemImage: "trash")
        }
        .buttonStyle(.bordered)
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
                HStack(spacing: 14) {
                    TextField("Local Qwen model", text: $agent.modelName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                    Text("Used through Ollama only if Apple’s on-device intelligence is unavailable.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var consumerStatus: String {
        agent.status.contains("unavailable") ? "Limited" : "Ready"
    }

    private var voicePermissionLabel: String {
        permissions.microphone == .granted && permissions.speech == .granted ? "Ready" : "Not ready"
    }

    private var voicePermissionColor: Color {
        voicePermissionLabel == "Ready" ? .green : .secondary
    }

    private func permissionRow(_ title: String, icon: String, status: PermissionCenter.Status) -> some View {
        let appearance = permissionAppearance(status)
        return settingsRow(title: title, icon: icon, value: appearance.label, color: appearance.color)
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
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
