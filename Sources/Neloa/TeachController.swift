import Foundation

@MainActor
final class TeachController: ObservableObject {
    enum Phase { case ready, starting, recording, building, review }
    enum RequiredPermission { case screenRecording }

    @Published var phase: Phase = .ready
    @Published private(set) var captureScreen = true
    @Published private(set) var captureMicrophone = true
    @Published private(set) var captureSystemAudio = true
    @Published var draft: Workflow?
    @Published var message: String?
    @Published private(set) var requiredPermission: RequiredPermission?

    let screen = ScreenRecorder()
    let voice = VoiceService()
    let interactions = InteractionRecorder()
    private var screenURL: URL?
    private var narrationURL: URL?

    func start() async {
        phase = .starting
        message = nil
        requiredPermission = nil
        do {
            if captureScreen {
                screenURL = try await screen.start(includeSystemAudio: captureSystemAudio)
            }
            if captureMicrophone {
                narrationURL = try await voice.start()
            }
            interactions.start()
            if interactions.permissionMissing {
                message = "Screen and voice are recording, but Accessibility is needed to learn clicks, typing, and replay actions."
            }
            phase = .recording
        } catch {
            if screen.isRecording { _ = await screen.stop() }
            if voice.isListening { voice.stop() }
            message = error.localizedDescription
            if let recordingError = error as? ScreenRecorder.RecordingError,
               recordingError == .screenPermissionRequired {
                requiredPermission = .screenRecording
            }
            phase = .ready
        }
    }

    func stopAndBuild() async {
        phase = .building
        let events = interactions.stop()
        if screen.isRecording { screenURL = await screen.stop() }
        if voice.isListening { narrationURL = voice.stop() }

        var workflow = WorkflowCompiler.compile(events: events, transcript: voice.transcript)
        workflow.name = suggestedName(from: voice.transcript)
        workflow.recordingPath = screenURL?.path
        workflow.narrationPath = narrationURL?.path
        draft = workflow
        phase = .review
    }

    func reset() {
        draft = nil
        screenURL = nil
        narrationURL = nil
        message = nil
        requiredPermission = nil
        phase = .ready
    }

    func useMicrophoneOnly() {
        setScreenCaptureEnabled(false)
        captureMicrophone = true
        message = nil
        requiredPermission = nil
    }

    func setScreenCaptureEnabled(_ isEnabled: Bool) {
        captureScreen = isEnabled
        captureSystemAudio = Self.resolvedSystemAudio(screenEnabled: isEnabled, requested: captureSystemAudio)
    }

    func setMicrophoneCaptureEnabled(_ isEnabled: Bool) {
        captureMicrophone = isEnabled
    }

    func setSystemAudioCaptureEnabled(_ isEnabled: Bool) {
        captureSystemAudio = Self.resolvedSystemAudio(screenEnabled: captureScreen, requested: isEnabled)
    }

    nonisolated static func resolvedSystemAudio(screenEnabled: Bool, requested: Bool) -> Bool {
        screenEnabled && requested
    }

    private func suggestedName(from transcript: String) -> String {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "My automation" }
        let words = clean.split(separator: " ").prefix(6).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
