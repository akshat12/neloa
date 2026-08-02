import AppKit
import SwiftUI

struct TeachView: View {
    @EnvironmentObject private var teacher: TeachController
    @EnvironmentObject private var store: WorkflowStore
    @State private var savedMessage = false
    @State private var showRecordingOptions = false

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
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "What should Neloa learn?", subtitle: "Show it once. Next time, just say what’s different.")
            Spacer()
            HStack(spacing: 15) {
                Image(systemName: "quote.bubble.fill")
                    .font(.system(size: 30)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Built for work that changes a little every time")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("Dates, amounts, clients, files, and thresholds become safe choices you can change on each run.")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(18)
            .background(Color.accentColor.opacity(0.075), in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
            Label("Common password managers and secure typing are automatically excluded.", systemImage: "eye.slash.fill")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRecordingOptions.toggle()
                    }
                } label: {
                    HStack {
                        Label("Recording options", systemImage: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showRecordingOptions ? 90 : 0))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showRecordingOptions {
                    Divider()
                        .padding(.horizontal, 18)

                    VStack(spacing: 10) {
                        FeatureToggle(icon: "rectangle.on.rectangle", title: "Record screen", subtitle: "See the apps and controls you use", isOn: captureScreenBinding)
                        FeatureToggle(icon: "mic", title: "Listen to your explanation", subtitle: "Turn your narration into rules and context", isOn: captureMicrophoneBinding)
                        FeatureToggle(icon: "speaker.wave.2", title: "Include computer audio", subtitle: "Capture useful sounds from the workflow", isOn: captureSystemAudioBinding)
                            .disabled(!teacher.captureScreen)
                    }
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(maxWidth: 700)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.15)))
            .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
            .frame(maxWidth: .infinity)
            Spacer()
            if let message = teacher.message {
                VStack(spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.orange)
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
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
            Button {
                Task { await teacher.start() }
            } label: {
                Label(teacher.phase == .starting ? "Starting…" : "Start teaching", systemImage: "record.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(teacher.phase == .starting || (!teacher.captureScreen && !teacher.captureMicrophone))
        }
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

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private var reviewView: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(title: "Review what Neloa learned", subtitle: "Name the automation and remove any steps Neloa should not repeat.")
            if let message = teacher.message {
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }
            if let draftBinding = Binding($teacher.draft) {
                WorkflowEditor(workflow: draftBinding)
                HStack {
                    Button("Teach again") { teacher.reset() }
                    Spacer()
                    if let path = teacher.draft?.recordingPath {
                        Button("Open recording") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    }
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

private struct RecordingView: View {
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
                .fill(LinearGradient(colors: [Color.indigo.opacity(0.88), Color.blue.opacity(0.62)], startPoint: .topLeading, endPoint: .bottomTrailing))
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
                Task { await controller.stopAndBuild() }
            } label: {
                Label("Finish teaching", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
        }
    }
}

private struct WorkflowEditor: View {
    @Binding var workflow: Workflow

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Automation name").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Automation name", text: $workflow.name).textFieldStyle(.roundedBorder)
                Text("What you said").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView {
                    Text(workflow.transcript.isEmpty ? "No narration was captured." : workflow.transcript)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                .padding().background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.trailing, 14).frame(minWidth: 320, idealWidth: 400)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(workflow.steps.count) learned steps").font(.headline)
                    Spacer()
                    Text("Right-click a step to remove it").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                            StepRow(number: index + 1, step: step)
                                .contextMenu {
                                    Button("Remove step", role: .destructive) { workflow.steps.removeAll { $0.id == step.id } }
                                }
                        }
                    }
                }
            }
            .padding(.leading, 14).frame(minWidth: 380)
        }
    }
}
