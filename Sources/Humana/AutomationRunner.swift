import AppKit
import CoreGraphics
import Foundation

@MainActor
final class AutomationRunner: ObservableObject {
    enum State: Equatable {
        case idle
        case countdown(Int)
        case running(Int)
        case waitingForApproval(String)
        case completed
        case stopped
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var currentStepID: UUID?

    private var runTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?

    func run(_ plan: RunPlan) {
        stop()
        runTask = Task { [weak self] in
            guard let self else { return }
            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                self.state = .countdown(value)
                try? await Task.sleep(for: .seconds(1))
            }

            for (index, step) in plan.steps.enumerated() {
                guard !Task.isCancelled else { return }
                self.state = .running(index)
                self.currentStepID = step.id

                if step.requiresApproval || step.kind == .approval {
                    self.state = .waitingForApproval(step.title)
                    let approved = await withCheckedContinuation { continuation in
                        self.approvalContinuation = continuation
                    }
                    guard approved else {
                        self.state = .stopped
                        return
                    }
                }

                do {
                    try await self.perform(step)
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
