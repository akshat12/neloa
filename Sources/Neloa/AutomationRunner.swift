import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class AutomationRunner: ObservableObject {
    typealias StepExecutor = @MainActor (WorkflowStep) async throws -> Void

    enum State: Equatable {
        case idle
        case countdown(Int)
        case running(Int)
        case waitingForApproval(String)
        case waitingForInstruction(String)
        case completed
        case stopped
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentStepID: UUID?
    @Published private(set) var completedStepIDs: Set<UUID> = []

    private var runTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private let countdownSeconds: Int
    private let stepExecutor: StepExecutor?

    init(countdownSeconds: Int = 3, stepExecutor: StepExecutor? = nil) {
        self.countdownSeconds = max(0, countdownSeconds)
        self.stepExecutor = stepExecutor
    }

    func run(_ plan: RunPlan) {
        stop()
        completedStepIDs = []
        guard stepExecutor != nil || AXIsProcessTrusted() else {
            state = .failed("Accessibility permission is required to replay this automation. Open System Settings → Privacy & Security → Accessibility and enable Neloa.")
            return
        }
        runTask = Task { [weak self] in
            guard let self else { return }
            if self.countdownSeconds > 0 {
                for value in stride(from: self.countdownSeconds, through: 1, by: -1) {
                    guard !Task.isCancelled else { return }
                    self.state = .countdown(value)
                    try? await Task.sleep(for: .seconds(1))
                }
            }

            for (index, step) in plan.steps.enumerated() {
                guard !Task.isCancelled else { return }
                self.state = .running(index)
                self.currentStepID = step.id

                if Self.requiresInstructionReview(step) {
                    self.state = .waitingForInstruction(step.text ?? step.title)
                    let approved = await withCheckedContinuation { continuation in
                        self.approvalContinuation = continuation
                    }
                    guard approved else {
                        self.state = .stopped
                        return
                    }
                } else if let approvalPrompt = Self.approvalPrompt(for: step) {
                    self.state = .waitingForApproval(approvalPrompt)
                    let approved = await withCheckedContinuation { continuation in
                        self.approvalContinuation = continuation
                    }
                    guard approved else {
                        self.state = .stopped
                        return
                    }
                }

                do {
                    if let stepExecutor = self.stepExecutor {
                        try await stepExecutor(step)
                    } else {
                        try await self.perform(step)
                    }
                    self.completedStepIDs.insert(step.id)
                } catch {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                try? await Task.sleep(for: .milliseconds(350))
            }
            self.currentStepID = nil
            self.state = .completed
        }
    }

    func approve() {
        approvalContinuation?.resume(returning: true)
        approvalContinuation = nil
    }

    func deny() {
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
    }

    func stop() {
        approvalContinuation?.resume(returning: false)
        approvalContinuation = nil
        runTask?.cancel()
        runTask = nil
        if state != .idle { state = .stopped }
    }

    func reset(preservingCompletedSteps: Bool = false) {
        stop()
        currentStepID = nil
        if !preservingCompletedSteps { completedStepIDs = [] }
        state = .idle
    }

    nonisolated static func approvalPrompt(for step: WorkflowStep) -> String? {
        if step.isUserInstruction, step.requiresApproval || step.kind == .approval { return step.text ?? step.title }
        return step.requiresApproval || step.kind == .approval ? step.title : nil
    }

    nonisolated static func requiresInstructionReview(_ step: WorkflowStep) -> Bool {
        step.isUserInstruction && !step.requiresApproval && step.kind != .approval
    }

    private func perform(_ step: WorkflowStep) async throws {
        switch step.kind {
        case .openApp:
            guard let name = step.application ?? step.title.components(separatedBy: "Open ").last else { return }
            if let running = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) {
                running.activate()
            } else if let identifier = step.bundleIdentifier,
                      let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                let configuration = NSWorkspace.OpenConfiguration()
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            try? await Task.sleep(for: .milliseconds(700))
        case .click:
            guard let x = step.x, let y = step.y else { return }
            let point = CGPoint(x: x, y: y)
            CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
            CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        case .typeText:
            guard let text = step.text else { return }
            if let x = step.x, let y = step.y {
                let point = CGPoint(x: x, y: y)
                CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(120))
            }
            let utf16 = Array(text.utf16)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            down?.post(tap: .cghidEventTap)
            CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)?.post(tap: .cghidEventTap)
        case .keyPress:
            guard let code = step.keyCode else { return }
            let flags = CGEventFlags(rawValue: step.flags ?? 0)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)
            down?.flags = flags
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: false)
            up?.flags = flags
            up?.post(tap: .cghidEventTap)
        case .wait:
            try? await Task.sleep(for: .seconds(1))
        case .decision, .approval:
            break
        }
    }
}
