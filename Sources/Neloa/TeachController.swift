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

    init(
        arguments: [String] = CommandLine.arguments,
        defaults: UserDefaults = .standard
    ) {
        // Older development builds used a persistent default for this fixture.
        // That could leak into normal launches and make a real recording look like
        // a canned demo indefinitely. Keep UI fixtures launch-scoped instead.
        Self.clearLegacyReviewFixture(in: defaults)
        #if DEBUG
        if Self.shouldLoadReviewFixture(arguments: arguments) {
            draft = Workflow(
                name: "Prepare weekly report",
                transcript: "Open the report, enter this week’s amount, flag the large change, and ask before sharing it.",
                recordingPath: "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/BentoGalleryIntroduction.mov",
                steps: [
                    WorkflowStep(kind: .openApp, title: "Open the weekly report", time: 1.2, application: "Numbers"),
                    WorkflowStep(kind: .click, title: "Select the revenue cell", time: 3.8, x: 640, y: 420, application: "Numbers"),
                    WorkflowStep(kind: .typeText, title: "Enter the weekly amount", detail: "Type $12,400", time: 6.4, text: "$12,400", application: "Numbers"),
                    WorkflowStep(kind: .decision, title: "Flag changes over 20%", detail: "Use judgment when the threshold is crossed", time: 9.1, application: "Numbers"),
                    WorkflowStep(kind: .click, title: "Choose Share", time: 12.0, x: 900, y: 120, application: "Numbers"),
                    WorkflowStep(kind: .approval, title: "Ask before sharing", time: 12.0, application: "Mail", requiresApproval: true)
                ]
            )
            phase = .review
        }
        #endif
    }

    nonisolated static func shouldLoadReviewFixture(arguments: [String]) -> Bool {
        arguments.contains("--ui-test-review")
    }

    nonisolated static func clearLegacyReviewFixture(in defaults: UserDefaults) {
        defaults.removeObject(forKey: "NeloaUITestReview")
    }

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
                message = captureScreen
                    ? "Screen recording will continue, but Accessibility is needed to capture clicks and typing precisely. Qwen can still draft actions from the video."
                    : "Voice recording will continue, but Accessibility is needed to capture clicks, typing, and replay actions."
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

    func stopAndBuild(using agent: LocalAgentService) async {
        phase = .building
        let events = interactions.stop()
        if screen.isRecording { screenURL = await screen.stop() }
        if voice.isListening { narrationURL = voice.stop() }

        var workflow = WorkflowCompiler.compile(events: events, transcript: voice.transcript)
        workflow.name = suggestedName(from: voice.transcript)
        workflow.recordingPath = screenURL?.path
        workflow.narrationPath = narrationURL?.path
        draft = await agent.learnWorkflow(
            candidate: workflow,
            recordingURL: screenURL,
            captureFrame: screen.captureFrame
        )
        if captureScreen,
           draft?.steps.contains(where: { [.click, .typeText, .keyPress].contains($0.kind) }) != true {
            message = "Qwen could not ground any repeatable actions in this recording. Play it back to confirm the correct app was visible, then teach the task again."
        } else {
            message = nil
        }
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
