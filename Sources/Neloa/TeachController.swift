import Foundation

@MainActor
final class TeachController: ObservableObject {
    enum Phase { case ready, starting, recording, building, review }

    @Published var phase: Phase = .ready
    @Published var captureScreen = true
    @Published var captureMicrophone = true
    @Published var captureSystemAudio = true
    @Published var draft: Workflow?
    @Published var message: String?

    let screen = ScreenRecorder()
    let voice = VoiceService()
    let interactions = InteractionRecorder()
    private var screenURL: URL?
    private var narrationURL: URL?

    func start() async {
        phase = .starting
        message = nil
        do {
            if captureScreen {
                screenURL = try await screen.start(includeSystemAudio: captureSystemAudio)
            }
            if captureMicrophone {
                narrationURL = try await voice.start()
            }
            interactions.start()
            if interactions.permissionMissing {
                message = "Screen and voice are recording, but Input Monitoring is needed to learn clicks and typing."
            }
            phase = .recording
        } catch {
            if screen.isRecording { _ = await screen.stop() }
            if voice.isListening { voice.stop() }
            message = error.localizedDescription
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
        phase = .ready
    }

    private func suggestedName(from transcript: String) -> String {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "My automation" }
        let words = clean.split(separator: " ").prefix(6).joined(separator: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}
