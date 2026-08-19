import AppKit
import ApplicationServices
import Foundation

struct StepRepairDifference: Identifiable, Equatable, Sendable {
    var id: String { field }
    var field: String
    var before: String
    var after: String
}

enum StepRepairError: LocalizedError, Equatable {
    case unsupportedAction
    case noMatchingAction
    case wrongApplication(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedAction:
            "This kind of step cannot be re-taught yet. Re-teach a click, text entry, key press, or app switch."
        case .noMatchingAction:
            "Neloa did not capture the selected kind of action. Try again and perform only the action being replaced."
        case .wrongApplication(let expected, let actual):
            "The replacement was captured in \(actual), but this step belongs to \(expected). Try again in the original app."
        }
    }
}

enum StepRepairSupport {
    nonisolated static func isEligible(_ step: WorkflowStep) -> Bool {
        [.openApp, .click, .typeText, .keyPress].contains(step.kind) && !step.isUserInstruction
    }

    nonisolated static func isRecommended(_ step: WorkflowStep) -> Bool {
        guard isEligible(step) else { return false }
        if step.origin == .visual { return true }
        switch step.kind {
        case .click:
            return clean(step.target) == nil
        case .typeText:
            return clean(step.target) == nil && (step.x == nil || step.y == nil)
        default:
            return false
        }
    }

    nonisolated static func reliabilityLabel(for step: WorkflowStep) -> String? {
        guard isRecommended(step) else { return nil }
        if step.origin == .visual { return "Visual draft — review target" }
        if step.kind == .click { return "Position only — re-teach recommended" }
        return "Depends on current focus — re-teach recommended"
    }

    nonisolated static func candidate(
        replacing original: WorkflowStep,
        from events: [CaptureEvent]
    ) throws -> WorkflowStep {
        guard isEligible(original) else { throw StepRepairError.unsupportedAction }

        let compiled = WorkflowCompiler.compile(events: events, transcript: "").steps
        guard var replacement = compiled.first(where: { $0.kind == original.kind && !$0.isUserInstruction }) else {
            throw StepRepairError.noMatchingAction
        }

        try verifyApplication(original: original, replacement: replacement)

        if original.kind == .typeText,
           let focusClick = nearestFocusClick(before: replacement, in: events) {
            replacement.x = focusClick.x
            replacement.y = focusClick.y
            replacement.displayID = focusClick.displayID
            if clean(replacement.target) == nil {
                replacement.target = clean(focusClick.target)
            }
        }

        replacement.id = original.id
        replacement.time = original.time
        replacement.runVariable = original.runVariable
        replacement.requiresApproval = original.requiresApproval || replacement.requiresApproval
        replacement.origin = .repaired
        replacement.instructionScope = original.instructionScope
        replacement.linkedStepID = original.linkedStepID
        return replacement
    }

    nonisolated static func replacing(
        stepID: UUID,
        with replacement: WorkflowStep,
        in steps: [WorkflowStep]
    ) -> [WorkflowStep] {
        guard let index = steps.firstIndex(where: { $0.id == stepID }), replacement.id == stepID else {
            return steps
        }
        var result = steps
        result[index] = replacement
        return result
    }

    nonisolated static func differences(
        from original: WorkflowStep,
        to replacement: WorkflowStep
    ) -> [StepRepairDifference] {
        var result: [StepRepairDifference] = []
        appendDifference("Application", appDescription(original), appDescription(replacement), to: &result)
        appendDifference("Target", targetDescription(original), targetDescription(replacement), to: &result)

        switch original.kind {
        case .click, .typeText:
            appendDifference("Position", positionDescription(original), positionDescription(replacement), to: &result)
        default:
            break
        }
        if original.kind == .typeText {
            appendDifference("Value", clean(original.text) ?? "No value", clean(replacement.text) ?? "No value", to: &result)
        }
        if original.kind == .keyPress {
            appendDifference("Key", keyDescription(original), keyDescription(replacement), to: &result)
        }
        return result
    }

    private nonisolated static func verifyApplication(
        original: WorkflowStep,
        replacement: WorkflowStep
    ) throws {
        if let expectedIdentifier = clean(original.bundleIdentifier),
           clean(replacement.bundleIdentifier) != expectedIdentifier {
            throw StepRepairError.wrongApplication(
                expected: clean(original.application) ?? expectedIdentifier,
                actual: clean(replacement.application) ?? clean(replacement.bundleIdentifier) ?? "another app"
            )
        }
        if clean(original.bundleIdentifier) == nil,
           let expectedName = clean(original.application),
           let actualName = clean(replacement.application),
           expectedName.caseInsensitiveCompare(actualName) != .orderedSame {
            throw StepRepairError.wrongApplication(expected: expectedName, actual: actualName)
        }
    }

    private nonisolated static func nearestFocusClick(
        before input: WorkflowStep,
        in events: [CaptureEvent]
    ) -> CaptureEvent? {
        events
            .filter {
                [.click, .rightClick].contains($0.kind)
                    && $0.time <= input.time
                    && sameApplication($0, input)
            }
            .max(by: { $0.time < $1.time })
    }

    private nonisolated static func sameApplication(_ event: CaptureEvent, _ step: WorkflowStep) -> Bool {
        if let eventIdentifier = clean(event.bundleIdentifier),
           let stepIdentifier = clean(step.bundleIdentifier) {
            return eventIdentifier == stepIdentifier
        }
        guard let eventName = clean(event.application), let stepName = clean(step.application) else { return true }
        return eventName.caseInsensitiveCompare(stepName) == .orderedSame
    }

    private nonisolated static func appendDifference(
        _ field: String,
        _ before: String,
        _ after: String,
        to result: inout [StepRepairDifference]
    ) {
        guard before != after else { return }
        result.append(StepRepairDifference(field: field, before: before, after: after))
    }

    private nonisolated static func appDescription(_ step: WorkflowStep) -> String {
        clean(step.application) ?? clean(step.bundleIdentifier) ?? "No app identity"
    }

    private nonisolated static func targetDescription(_ step: WorkflowStep) -> String {
        clean(step.target) ?? "Saved position only"
    }

    private nonisolated static func positionDescription(_ step: WorkflowStep) -> String {
        guard let x = step.x, let y = step.y else { return "No fallback position" }
        return "\(Int(x)), \(Int(y))"
    }

    private nonisolated static func keyDescription(_ step: WorkflowStep) -> String {
        guard let keyCode = step.keyCode else { return "No key" }
        return "Key code \(keyCode) · modifiers \(step.flags ?? 0)"
    }

    private nonisolated static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

@MainActor
final class StepRepairController: ObservableObject {
    enum Phase: Equatable {
        case ready
        case recording
        case preview
        case failed(String)
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var candidate: WorkflowStep?
    @Published private(set) var capturedEventCount = 0

    private let recorder = InteractionRecorder()

    func start(for step: WorkflowStep) async {
        cancel()
        guard StepRepairSupport.isEligible(step) else {
            phase = .failed(StepRepairError.unsupportedAction.localizedDescription)
            return
        }
        guard AXIsProcessTrusted() else {
            phase = .failed("Accessibility permission is required to capture a replacement action.")
            return
        }

        recorder.start()
        guard !recorder.permissionMissing else {
            _ = recorder.stop()
            phase = .failed("macOS did not allow Neloa to observe the replacement action. Check Accessibility permission and try again.")
            return
        }
        phase = .recording

        do {
            try await activateOriginalApplication(for: step)
        } catch {
            _ = recorder.stop()
            phase = .failed(error.localizedDescription)
        }
    }

    func stop(for step: WorkflowStep) {
        let events = recorder.stop()
        capturedEventCount = events.filter { $0.kind != .appSwitch }.count
        do {
            candidate = try StepRepairSupport.candidate(replacing: step, from: events)
            phase = .preview
        } catch {
            candidate = nil
            phase = .failed(error.localizedDescription)
        }
    }

    func tryAgain() {
        if recorder.isRecording { _ = recorder.stop() }
        candidate = nil
        capturedEventCount = 0
        phase = .ready
    }

    func cancel() {
        if recorder.isRecording { _ = recorder.stop() }
        candidate = nil
        capturedEventCount = 0
        phase = .ready
    }

    private func activateOriginalApplication(for step: WorkflowStep) async throws {
        if let bundleIdentifier = step.bundleIdentifier,
           !bundleIdentifier.isEmpty,
           !PrivacyShield.excludes(bundleIdentifier) {
            if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
                guard running.activate(options: [.activateAllWindows]) else {
                    throw ActivationError.couldNotActivate(step.application ?? bundleIdentifier)
                }
                return
            }
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                return
            }
            throw ActivationError.notAvailable(step.application ?? bundleIdentifier)
        }
        // Older workflows may not contain a bundle identifier. Recording stays
        // active so the user can switch to the original app manually.
    }

    private enum ActivationError: LocalizedError {
        case couldNotActivate(String)
        case notAvailable(String)

        var errorDescription: String? {
            switch self {
            case .couldNotActivate(let app): "Neloa could not bring \(app) forward. Open it and try again."
            case .notAvailable(let app): "\(app) is not available on this Mac. Restore it before re-teaching this step."
            }
        }
    }
}

