import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var permissions: PermissionCenter
    @ObservedObject var agent: LocalAgentService
    let finish: (Bool) -> Void
    @State private var page = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            if page == 0 {
                welcome.transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity), removal: .opacity))
            } else if page == 1 {
                permissionSetup.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            } else {
                modelSetup.transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            }
        }
        .frame(width: 760, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(response: 0.52, dampingFraction: 0.86), value: page)
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.76).delay(0.08)) { appeared = true }
        }
    }

    private var welcome: some View {
        ZStack {
            Circle()
                .fill(NeloaPalette.lagoon.opacity(0.08))
                .frame(width: 460, height: 460)
                .blur(radius: 22)
                .offset(x: -310, y: -260)
            Circle()
                .fill(NeloaPalette.lagoonBright.opacity(0.07))
                .frame(width: 390, height: 390)
                .blur(radius: 28)
                .offset(x: 340, y: 290)

            VStack(spacing: 25) {
                Spacer(minLength: 20)
                animatedBrand
                    .scaleEffect(appeared ? 1 : 0.78)
                    .opacity(appeared ? 1 : 0)
                Text("Automate work that changes\na little every time.")
                    .font(.system(size: 39, weight: .bold, design: .rounded))
                    .tracking(-0.8)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: appeared ? 0 : 18)
                    .opacity(appeared ? 1 : 0)
                Text("Show Neloa once. Next time, say only what’s different—a date, amount, client, file, or instruction—and stay in control of every important action.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .frame(maxWidth: 590)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: appeared ? 0 : 14)
                    .opacity(appeared ? 1 : 0)
                HStack(spacing: 16) {
                    onboardingFeature("record.circle", "Show", "Do the task once", index: 0)
                    onboardingFeature("quote.bubble", "Say", "Tell us what changed", index: 1)
                    onboardingFeature("hand.raised", "Approve", "Stay in control", index: 2)
                }
                .padding(.vertical, 8)
                Spacer(minLength: 8)
                Button("Continue") { page = 1 }
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
                    .padding(.bottom, 26)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .padding(34)
    }

    private var animatedBrand: some View {
        HStack(spacing: 13) {
            NeloaAppIcon(size: 62)
                .shadow(color: NeloaPalette.lagoon.opacity(0.24), radius: 12, y: 5)
            Text("Neloa")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .fixedSize()
        }
    }

    private var permissionSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(title: "Allow only what you want to teach", subtitle: "These permissions let Neloa observe and replay your demonstration. Recordings stay on this Mac.")
            permissionRow(
                icon: "rectangle.on.rectangle",
                title: "Screen Recording",
                detail: "Records the apps you demonstrate",
                status: permissions.screen,
                permissionHelp: "Neloa needs Screen Recording permission to record the apps you demonstrate.",
                settingsAnchor: "Privacy_ScreenCapture"
            ) {
                permissions.requestScreen()
            }
            permissionRow(
                icon: "hand.tap",
                title: "Clicks & Typing",
                detail: "Learns your demonstration and replays only the actions you approve",
                status: permissions.accessibility,
                permissionHelp: "Neloa needs Accessibility permission to capture clicks and typing and replay approved actions.",
                settingsAnchor: "Privacy_Accessibility"
            ) {
                permissions.requestAccessibility()
            }
            permissionRow(
                icon: "mic",
                title: "Microphone & Speech",
                detail: "Understands explanations and spoken run instructions",
                status: combinedVoiceStatus,
                permissionHelp: "Neloa needs Microphone and Speech Recognition permissions for spoken explanations and voice instructions.",
                settingsAnchor: voiceSettingsAnchor
            ) {
                Task { await permissions.requestMicrophoneAndSpeech() }
            }
            HStack {
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") { NSWorkspace.shared.open(url) }
                }
                Spacer()
                Button("Back") { withAnimation { page = 0 } }
                Button("Continue") { page = 2 }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(34)
    }

    private var modelSetup: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeader(
                title: "Give Neloa visual understanding",
                subtitle: "A one-time local model download helps Neloa understand what each captured click and field means."
            )

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    Image(systemName: "eye.circle.fill")
                        .font(.system(size: 38, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 72, height: 72)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(LocalModelPaths.displayName)
                            .font(.system(size: 21, weight: .semibold, design: .rounded))
                        Text("\(LocalModelPaths.downloadSizeLabel) · Apple silicon · 16 GB or more")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    onboardingModelBadge
                }

                Divider()
                onboardingModelStatus

                if case .downloading(let progress) = agent.modelStatus {
                    VStack(alignment: .leading, spacing: 7) {
                        ProgressView(value: progress)
                        Text("\(Int(progress * 100))% downloaded")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Label("Downloaded and run entirely inside Neloa—no account, Terminal, Ollama, local server, or cloud upload.", systemImage: "lock.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(22)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))

            Spacer()
            HStack {
                Button("Back") { page = 1 }
                Spacer()
                Button("Skip tour") { finish(false) }
                Button("Start guided tour") { finish(true) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(34)
    }

    @ViewBuilder
    private var onboardingModelStatus: some View {
        switch agent.modelStatus {
        case .notInstalled:
            HStack {
                Text("Recommended for accurate workflow names, action labels, and narrated rules.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Download model") { Task { await agent.setupModel() } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .checking:
            Label("Checking the model…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .downloading:
            Label("Downloading in the background. You can continue using Neloa.", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
        case .loading:
            Label("Loading the model into memory…", systemImage: "memorychip")
                .foregroundStyle(Color.accentColor)
        case .ready:
            Label("Visual understanding is ready on this Mac.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            HStack {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Spacer()
                Button("Try again") { Task { await agent.setupModel() } }
                    .buttonStyle(.borderedProminent)
            }
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var onboardingModelBadge: some View {
        let ready = agent.modelStatus == .ready
        return Label(ready ? "Ready" : "Optional", systemImage: ready ? "checkmark.circle.fill" : "sparkles")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ready ? Color.green : Color.accentColor)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background((ready ? Color.green : Color.accentColor).opacity(0.1), in: Capsule())
    }

    private var combinedVoiceStatus: PermissionCenter.Status {
        if permissions.microphone == .denied || permissions.speech == .denied { return .denied }
        if permissions.microphone == .granted && permissions.speech == .granted { return .granted }
        return .unknown
    }

    private var voiceSettingsAnchor: String {
        permissions.microphone == .denied ? "Privacy_Microphone" : "Privacy_SpeechRecognition"
    }

    private func onboardingFeature(_ icon: String, _ title: String, _ detail: String, index: Int) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 27, weight: .medium)).foregroundStyle(Color.accentColor)
            Text(title).font(.system(size: 16, weight: .bold, design: .rounded))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(width: 168, height: 96)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
        .offset(y: appeared ? 0 : 20)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.7, dampingFraction: 0.78).delay(0.22 + Double(index) * 0.09), value: appeared)
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        status: PermissionCenter.Status,
        permissionHelp: String,
        settingsAnchor: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 15) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor).frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 17, weight: .semibold, design: .rounded))
                Text(detail).font(.system(size: 14)).foregroundStyle(.secondary)
            }
            Spacer()
            if status == .granted {
                Label(status.label, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Label(status.label, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .help(permissionHelp)
                Button(status == .denied ? "Open Settings" : "Allow") {
                    if status == .denied {
                        openPrivacyPane(settingsAnchor)
                    } else {
                        action()
                    }
                }
                .help(permissionHelp)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
