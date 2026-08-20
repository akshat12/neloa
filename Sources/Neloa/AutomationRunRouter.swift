import Combine
import Foundation

enum AutomationRunSource: String, Equatable, Sendable {
    case reminder
    case shortcut
    case watchedFolder
}

struct AutomationRunRequest: Identifiable, Equatable, Sendable {
    var id = UUID()
    var workflowID: UUID
    var initialInstruction: String?
    var source: AutomationRunSource
}

struct AutomationRunQueue: Equatable, Sendable {
    private(set) var current: AutomationRunRequest?
    private(set) var queued: [AutomationRunRequest] = []

    mutating func enqueue(_ request: AutomationRunRequest) {
        if current == nil {
            current = request
        } else {
            queued.append(request)
        }
    }

    mutating func finishCurrent() {
        current = queued.isEmpty ? nil : queued.removeFirst()
    }

    mutating func removeRequests(for workflowID: UUID) {
        queued.removeAll { $0.workflowID == workflowID }
        if current?.workflowID == workflowID { finishCurrent() }
    }
}

/// Serializes every external entry point through the same reviewed run sheet.
/// A trigger may suggest an instruction, but it cannot plan or replay work.
@MainActor
final class AutomationRunRouter: ObservableObject {
    static let shared = AutomationRunRouter()

    @Published private(set) var currentRequest: AutomationRunRequest?
    @Published private(set) var queuedRequestCount = 0

    private var queue = AutomationRunQueue()

    func enqueue(_ request: AutomationRunRequest) {
        queue.enqueue(request)
        publishQueue()
    }

    func finishCurrent() {
        queue.finishCurrent()
        publishQueue()
    }

    func removeRequests(for workflowID: UUID) {
        queue.removeRequests(for: workflowID)
        publishQueue()
    }

    private func publishQueue() {
        currentRequest = queue.current
        queuedRequestCount = queue.queued.count
    }
}
