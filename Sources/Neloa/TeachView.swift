import AppKit
import SwiftUI

struct TeachView: View {
    @EnvironmentObject private var teacher: TeachController
    @EnvironmentObject private var agent: LocalAgentService
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var permissions: PermissionCenter
    @State private var savedMessage = false

    var body: some View {
        VStack(spacing: 0) {
            switch teacher.phase {
            case .ready, .starting:
                setupView
            case .recording:
                RecordingView(controller: teacher)
            case .building:
                ProgressView("Turning your demonstration into an automation…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .review:
                if teacher.draft != nil { reviewView }
            }
        }
        .padding(32)
        .overlay(alignment: .topTrailing) {
            if savedMessage {
                Label("Automation saved", systemImage: "checkmark.circle.fill")
                    .padding(12).background(.regularMaterial, in: Capsule()).padding()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 26) {
            PageHeader(
                title: "Let’s get your teaching session ready.",
                subtitle: "Three quick choices, then show Neloa the task."
            )

            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        TeachSetupStep(number: 1, title: "What should Neloa observe?") {
                            HStack(spacing: 9) {
                                TeachOptionToggle(
                                    icon: "rectangle.on.rectangle",
                                    title: "Screen",
                                    isOn: captureScreenBinding,
                                    permissionStatus: permissions.screen,
                                    permissionHelp: "Screen Recording permission is required to record the apps you demonstrate. Grant it in System Settings → Privacy & Security → Screen & System Audio Recording."
                                )
                                TeachIncludedOption(
                                    icon: "hand.tap",
                                    title: "Clicks & Typing",
                                    permissionStatus: permissions.accessibility,
                                    permissionHelp: "Accessibility permission is required to capture clicks and typing and replay approved actions. Grant it in System Settings → Privacy & Security → Accessibility."
                                )
                            }
                        }

                        Divider().padding(.leading, 50)

                        TeachSetupStep(number: 2, title: "How will you explain choices?") {
                            HStack(spacing: 9) {
                                TeachOptionToggle(
                                    icon: "mic",
                                    title: "Use my voice",
                                    isOn: captureMicrophoneBinding,
                                    permissionStatus: voicePermissionStatus,
                                    permissionHelp: "Microphone and Speech Recognition permissions are required for spoken explanations. Grant them in System Settings → Privacy & Security."
                                )
                                TeachOptionToggle(
                                    icon: "speaker.wave.2",
                                    title: "Computer audio",
                                    isOn: captureSystemAudioBinding,
                                    permissionStatus: permissions.screen,
                                    permissionHelp: "Screen & System Audio Recording permission is required to capture computer audio. Grant it in System Settings → Privacy & Security."
                                )
                                .disabled(!teacher.captureScreen)
                            }
                        }

                        Divider().padding(.leading, 50)

                        TeachSetupStep(number: 3, title: "You stay in control") {
                            Label("Neloa asks before important actions.", systemImage: "checkmark.shield")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.secondary.opacity(0.16)))
                    .appTourTarget(.teachingSetup)

                    if let message = teacher.message {
                        permissionMessage(message)
                    }

                    HStack(spacing: 14) {
                        Button {
                            Task { await teacher.start() }
                        } label: {
                            Label(teacher.phase == .starting ? "Starting…" : "Start teaching", systemImage: "record.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(teacher.phase == .starting || (!teacher.captureScreen && !teacher.captureMicrophone))
                        .appTourTarget(.startTeaching)

                        Label("Secure fields stay hidden.", systemImage: "eye.slash")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                WhatNeloaLearnsCard()
                    .frame(minWidth: 280, idealWidth: 310, maxWidth: 340)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func permissionMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.red)
            if teacher.requiredPermission == .screenRecording {
                HStack(spacing: 10) {
                    Button("Open Screen Recording Settings") { openScreenRecordingSettings() }
                        .buttonStyle(.borderedProminent)
                    Button(teacher.captureMicrophone ? "Record without screen" : "Use microphone instead") {
                        teacher.useMicrophoneOnly()
                        Task { await teacher.start() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private var captureScreenBinding: Binding<Bool> {
        Binding(
            get: { teacher.captureScreen },
            set: { teacher.setScreenCaptureEnabled($0) }
        )
    }

    private var captureMicrophoneBinding: Binding<Bool> {
        Binding(
            get: { teacher.captureMicrophone },
            set: { teacher.setMicrophoneCaptureEnabled($0) }
        )
    }

    private var captureSystemAudioBinding: Binding<Bool> {
        Binding(
            get: { teacher.captureSystemAudio },
            set: { teacher.setSystemAudioCaptureEnabled($0) }
        )
    }

    private var voicePermissionStatus: PermissionCenter.Status {
        if permissions.microphone == .granted && permissions.speech == .granted { return .granted }
        if permissions.microphone == .denied || permissions.speech == .denied { return .denied }
        return .unknown
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Review what Neloa learned", subtitle: "Play back the recording and confirm the actions Neloa should repeat.")
            if let message = teacher.message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let draftBinding = Binding($teacher.draft) {
                WorkflowReviewView(workflow: draftBinding)
                HStack {
                    Button("Teach again") { teacher.reset() }
                    Spacer()
                    Button("Save automation") {
                        if let workflow = teacher.draft {
                            store.save(workflow)
                            withAnimation { savedMessage = true }
                            Task {
                                try? await Task.sleep(for: .seconds(1.6))
                                await MainActor.run {
                                    withAnimation { savedMessage = false }
                                    teacher.reset()
                                    NotificationCenter.default.post(name: .showNeloaAutomations, object: nil)
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(teacher.draft?.steps.isEmpty != false)
                }
            }
        }
    }
}

private struct TeachSetupStep<Content: View>: View {
    let number: Int
    let title: String
    let content: Content

    init(number: Int, title: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
    }
}

private struct TeachOptionToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    let permissionStatus: PermissionCenter.Status
    let permissionHelp: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            TeachCaptureOptionLabel(
                icon: icon,
                title: title,
                isActive: isOn,
                needsPermission: isOn && permissionStatus != .granted,
                permissionHelp: permissionHelp
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct TeachIncludedOption: View {
    let icon: String
    let title: String
    let permissionStatus: PermissionCenter.Status
    let permissionHelp: String

    var body: some View {
        TeachCaptureOptionLabel(
            icon: icon,
            title: title,
            isActive: true,
            needsPermission: permissionStatus != .granted,
            permissionHelp: permissionHelp
        )
        .accessibilityLabel("\(title), included")
    }
}

private struct TeachCaptureOptionLabel: View {
    let icon: String
    let title: String
    let isActive: Bool
    let needsPermission: Bool
    let permissionHelp: String

    var body: some View {
        HStack(spacing: 7) {
            Label(title, systemImage: icon)
                .lineLimit(1)
            Spacer(minLength: 4)
            if needsPermission {
                Image(systemName: "exclamationmark.circle.fill")
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(optionColor)
        .frame(width: 174, alignment: .leading)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(optionColor.opacity(isActive ? 0.11 : 0.06), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(optionColor.opacity(isActive ? 0.32 : 0.18)))
        .contentShape(Rectangle())
        .help(needsPermission ? permissionHelp : "\(title) is ready.")
    }

    private var optionColor: Color {
        if needsPermission { return .red }
        return isActive ? Color.accentColor : .secondary
    }
}

private struct WhatNeloaLearnsCard: View {
    private let examples = [
        ("calendar", "Dates", "Use next Friday instead."),
        ("dollarsign.circle", "Amounts", "Make it $2,500 this time."),
        ("person.2", "People", "Send this one to Maya."),
        ("doc", "Files", "Use the July report.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("What Neloa can learn")
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: example.0)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(example.1)
                            .font(.system(size: 14, weight: .semibold))
                        Text("“\(example.2)”")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            Label("Built for work that changes a little every time.", systemImage: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct RecordingView: View {
    @EnvironmentObject private var agent: LocalAgentService
    @ObservedObject var controller: TeachController
    @ObservedObject private var screen: ScreenRecorder
    @ObservedObject private var voice: VoiceService
    @ObservedObject private var interactions: InteractionRecorder

    init(controller: TeachController) {
        self.controller = controller
        self.screen = controller.screen
        self.voice = controller.voice
        self.interactions = controller.interactions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                PageHeader(title: "Teaching in progress", subtitle: "Complete the task naturally. Narrate the choices another person would need to understand.")
                Spacer()
                Label(screen.elapsed.clockString, systemImage: "record.circle.fill")
                    .font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.red)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(.red.opacity(0.08), in: Capsule())
            }

            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [NeloaPalette.lagoonDeep.opacity(0.94), NeloaPalette.lagoon.opacity(0.76)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "rectangle.inset.filled.and.person.filled")
                            .font(.system(size: 54)).foregroundStyle(.white)
                        Text("Neloa is watching the workflow")
                            .font(.title2.bold()).foregroundStyle(.white)
                        Text("Switch to the app you want to teach. Return here when you are finished.")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(maxHeight: .infinity)

            HStack(alignment: .top, spacing: 14) {
                Label(voice.isListening ? "Listening" : "Mic off", systemImage: voice.isListening ? "waveform" : "mic.slash")
                    .foregroundStyle(voice.isListening ? .green : .secondary)
                Text(voice.transcript.isEmpty ? "Your explanation will appear here…" : voice.transcript)
                    .font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                Label("\(interactions.events.count) actions", systemImage: "cursorarrow.click")
                    .foregroundStyle(.secondary)
            }
            .padding(18).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))

            if let message = controller.message {
                HStack {
                    Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Spacer()
                    Button("Open Privacy Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }

            Button {
                Task { await controller.stopAndBuild(using: agent) }
            } label: {
                Label("Finish teaching", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        }
    }
}
