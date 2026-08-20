import AppKit
import Foundation

@MainActor
final class TeachController: ObservableObject {
    enum Phase { case ready, starting, recording, building, review }
    enum RequiredPermission { case screenRecording }

    @Published var phase: Phase = .ready
    @Published private(set) var captureScreen = true
    @Published private(set) var captureMicrophone = true
    @Published private(set) var captureSystemAudio = true
    @Published var screenCaptureTarget: ScreenCaptureTarget = .followActiveApplication
    @Published var targetApplicationBundleIdentifier: String?
    @Published var draft: Workflow?
    @Published var message: String?
    @Published private(set) var requiredPermission: RequiredPermission?
    @Published private(set) var templateGuide: AutomationTemplate?

    let screen = ScreenRecorder()
    let voice = VoiceService()
    let interactions = InteractionRecorder()
    private var screenURL: URL?
    private var narrationURL: URL?

    init(
        arguments: [String] = CommandLine.arguments,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        // Older development builds used a persistent default for this fixture.
        // That could leak into normal launches and make a real recording look like
        // a canned demo indefinitely. Keep UI fixtures launch-scoped instead.
        Self.clearLegacyReviewFixture(in: defaults)
        #if DEBUG
        if Self.shouldLoadReviewFixture(arguments: arguments, environment: environment) {
            draft = Workflow(
                name: "Prepare weekly report",
                transcript: "Open the report, enter this week’s amount, flag the large change, and ask before sharing it.",
                narrationSegments: [
                    NarrationSegment(text: "Open the report.", time: 1.0, duration: 1.1),
                    NarrationSegment(text: "Enter this week's amount.", time: 5.6, duration: 1.4),
                    NarrationSegment(text: "Flag the large change.", time: 8.5, duration: 1.3),
                    NarrationSegment(text: "Always ask before sharing it.", time: 10.8, duration: 1.6)
                ],
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

    nonisolated static func shouldLoadReviewFixture(
        arguments: [String],
        environment: [String: String] = [:]
    ) -> Bool {
        arguments.contains("--ui-test-review") || environment["NELOA_UI_TEST_REVIEW"] == "1"
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
                screenURL = try await screen.start(
                    includeSystemAudio: captureSystemAudio,
                    preferredBundleIdentifier: targetApplicationBundleIdentifier,
                    captureTarget: screenCaptureTarget
                )
            }
            // A microphone-only session must not reuse the previous screen
            // recording's origin from this long-lived controller.
            let origin = captureScreen ? (screen.timelineOrigin ?? Date()) : Date()
            if captureMicrophone {
                narrationURL = try await voice.start(timelineOrigin: origin)
            }
            interactions.start(timelineOrigin: origin)
            if interactions.permissionMissing {
                message = captureScreen
                    ? "Screen recording will continue, but Accessibility is needed to capture clicks and typing precisely. Qwen can still draft actions from the video."
                    : "Voice recording will continue, but Accessibility is needed to capture clicks, typing, and replay actions."
            }
            phase = .recording
            await activateTeachingTargetIfNeeded()
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
        let shouldFinalizeNarration = voice.isListening
        if shouldFinalizeNarration { narrationURL = voice.beginFinalization() }
        if screen.isRecording { screenURL = await screen.stop() }
        if shouldFinalizeNarration { await voice.awaitFinalization() }

        var workflow = WorkflowCompiler.compile(
            events: events,
            transcript: voice.transcript,
            narrationSegments: voice.narrationSegments
        )
        workflow.name = suggestedName(from: voice.transcript)
        workflow.recordingPath = screenURL?.path
        workflow.narrationPath = narrationURL?.path
        draft = await agent.learnWorkflow(
            candidate: workflow,
            recordingURL: screenURL,
            captureFrame: screen.captureFrame
        )
        if let templateGuide {
            draft?.name = templateGuide.title
        }
        if captureScreen,
           draft?.steps.contains(where: { [.openURL, .click, .typeText, .keyPress].contains($0.kind) }) != true {
            message = "Qwen could not ground any repeatable actions in this recording. Play it back to confirm the correct app was visible, then teach the task again."
        } else {
            message = nil
        }
        phase = .review
    }

    func reset(preserveTemplate: Bool = false) {
        let preservedTemplate = preserveTemplate ? templateGuide : nil
        draft = nil
        screenURL = nil
        narrationURL = nil
        message = nil
        requiredPermission = nil
        phase = .ready
        templateGuide = preservedTemplate
    }

    var canPrepareTemplate: Bool {
        phase == .ready
    }

    @discardableResult
    func prepare(template: AutomationTemplate) -> Bool {
        guard canPrepareTemplate else { return false }
        reset()
        templateGuide = template
        return true
    }

    func clearTemplateGuide() {
        guard phase == .ready else { return }
        templateGuide = nil
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

    func setTeachingTarget(_ bundleIdentifier: String?) {
        targetApplicationBundleIdentifier = Self.resolvedTeachingTarget(bundleIdentifier)
    }

    func setScreenCaptureTarget(_ target: ScreenCaptureTarget) {
        screenCaptureTarget = target
    }

    nonisolated static func resolvedTeachingTarget(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return bundleIdentifier
    }

    private func activateTeachingTargetIfNeeded() async {
        guard let bundleIdentifier = targetApplicationBundleIdentifier,
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              !PrivacyShield.excludes(bundleIdentifier) else { return }
        if !application.activate(options: [.activateAllWindows]) {
            message = "Recording started, but macOS could not bring the selected app forward. Switch to it to continue teaching."
        }
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
