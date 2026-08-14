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
    /// A human-readable accessibility label for the clicked control when the
    /// target application exposes one. Coordinates remain the replay fallback.
    var target: String?
    var keyCode: Int?
    var flags: UInt64?
    var application: String?
    var bundleIdentifier: String?
    var displayID: CGDirectDisplayID?
}

/// One on-device Speech transcription token aligned to the teaching session's
/// recording clock. Tokens are preserved so they can be regrouped without
/// losing the recognizer's original timing.
struct NarrationSegment: Codable, Equatable, Sendable {
    var text: String
    var time: TimeInterval
    var duration: TimeInterval
    var confidence: Double?

    var endTime: TimeInterval { time + max(0, duration) }
}

enum WorkflowStepKind: String, Codable, CaseIterable, Sendable {
    case openApp
    case openURL
    case click
    case typeText
    case keyPress
    case selectSpreadsheetCell
    case decision
    case approval
    case wait

    var label: String {
        switch self {
        case .openApp: "App"
        case .openURL: "Web"
        case .click: "Click"
        case .typeText: "Input"
        case .keyPress: "Key"
        case .selectSpreadsheetCell: "Navigation"
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
    /// A stable semantic destination such as `Sheet2!A1` when Neloa can
    /// identify one. Replay may still use captured input events, but review and
    /// run planning should describe the user's target instead of a coordinate.
    var target: String?
    /// `nil` preserves the behavior of workflows saved before semantic input
    /// roles were introduced. Navigation text explicitly opts out.
    var runVariable: Bool?
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
    var isRunVariable: Bool { kind == .typeText && runVariable != false }

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
    /// Optional so workflows saved before timed narration continue to decode.
    var narrationSegments: [NarrationSegment]? = nil
    var recordingPath: String?
    var narrationPath: String?
    var steps: [WorkflowStep]
    var defaultInstruction = "Run it the same way"
    /// Optional so existing on-disk workflows decode without a migration shim.
    var semanticVersion: Int? = nil
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
