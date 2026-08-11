import Foundation
import CoreGraphics

enum CaptureEventKind: String, Codable, Sendable {
    case click
    case rightClick
    case text
    case keyPress
    case appSwitch
}

struct CaptureEvent: Codable, Equatable, Sendable {
    var time: TimeInterval
    var kind: CaptureEventKind
    var x: Double?
    var y: Double?
    var text: String?
    var keyCode: Int?
    var flags: UInt64?
    var application: String?
    var bundleIdentifier: String?
    var displayID: CGDirectDisplayID?
}

enum WorkflowStepKind: String, Codable, CaseIterable, Sendable {
    case openApp
    case click
    case typeText
    case keyPress
    case decision
    case approval
    case wait

    var label: String {
        switch self {
        case .openApp: "App"
        case .click: "Click"
        case .typeText: "Input"
        case .keyPress: "Key"
        case .decision: "Agent"
        case .approval: "Approval"
        case .wait: "Wait"
        }
    }
}

enum WorkflowStepOrigin: String, Codable, Sendable {
    case inferred
    case visual
    case user
}

enum WorkflowInstructionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case thisAction
    case fromHere
    case entireWorkflow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .thisAction: "This action"
        case .fromHere: "From here onward"
        case .entireWorkflow: "Entire workflow"
        }
    }

    var explanation: String {
        switch self {
        case .thisAction: "Attach it to the nearest captured action and pause before that action."
        case .fromHere: "Add a review checkpoint here before the remaining actions."
        case .entireWorkflow: "Review this instruction before the automation starts."
        }
    }
}

struct WorkflowStep: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var kind: WorkflowStepKind
    var title: String
    var detail: String = ""
    var time: TimeInterval
    var x: Double?
    var y: Double?
    var text: String?
    var keyCode: Int?
    var flags: UInt64?
    var application: String?
    var bundleIdentifier: String?
    var displayID: CGDirectDisplayID?
    var requiresApproval = false
    var origin: WorkflowStepOrigin?
    var instructionScope: WorkflowInstructionScope?
    var linkedStepID: UUID?

    var isUserInstruction: Bool { origin == .user }

    var displayKindLabel: String {
        let base: String
        if isUserInstruction {
            base = "Your instruction"
        } else if origin == .visual {
            base = "\(kind.label) · Visual draft"
        } else {
            base = kind.label
        }
        guard !isUserInstruction, let application, !application.isEmpty else { return base }
        return "\(base) · \(application)"
    }
}

struct Workflow: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var updatedAt = Date()
    var transcript: String
    var recordingPath: String?
    var narrationPath: String?
    var steps: [WorkflowStep]
    var defaultInstruction = "Run it the same way"
}

struct PlannedChange: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var stepID: UUID
    var before: String
    var after: String
    var reason: String
}

struct RunPlan: Codable, Equatable, Sendable {
    var instruction: String
    var steps: [WorkflowStep]
    var changes: [PlannedChange]
    var summary: String
}

enum AutomationRunStatus: String, Codable, Sendable {
    case completed
    case stopped
    case failed
}

struct AutomationRunReceipt: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var workflowID: UUID
    var workflowName: String
    var startedAt: Date
    var finishedAt = Date()
    var instruction: String
    var summary: String
    var changes: [PlannedChange]
    var stepCount: Int
    var status: AutomationRunStatus
    var message: String?
}
