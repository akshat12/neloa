import Foundation

enum WorkflowInstructionSupport {
    nonisolated static func makeStep(
        text: String,
        time: TimeInterval,
        scope: WorkflowInstructionScope,
        existingSteps: [WorkflowStep],
        id: UUID = UUID()
    ) -> WorkflowStep? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return nil }
        let linkedStep = scope == .thisAction ? nearestCapturedAction(at: time, in: existingSteps) : nil
        let asksForApproval = isApprovalInstruction(cleanText)
        return WorkflowStep(
            id: id,
            kind: asksForApproval ? .approval : .decision,
            title: short(cleanText),
            detail: detail(scope: scope, linkedStep: linkedStep),
            time: max(0, time),
            text: cleanText,
            requiresApproval: asksForApproval,
            origin: .user,
            instructionScope: scope,
            linkedStepID: linkedStep?.id
        )
    }

    nonisolated static func inserting(_ instruction: WorkflowStep, into steps: [WorkflowStep]) -> [WorkflowStep] {
        var result = steps.filter { $0.id != instruction.id }
        let insertionIndex: Array<WorkflowStep>.Index
        switch instruction.instructionScope {
        case .entireWorkflow:
            insertionIndex = result.startIndex
        case .thisAction:
            if let linkedStepID = instruction.linkedStepID,
               let linkedIndex = result.firstIndex(where: { $0.id == linkedStepID }) {
                insertionIndex = linkedIndex
            } else {
                insertionIndex = result.firstIndex { $0.time >= instruction.time } ?? result.endIndex
            }
        case .fromHere, nil:
            insertionIndex = result.firstIndex { $0.time >= instruction.time } ?? result.endIndex
        }
        result.insert(instruction, at: insertionIndex)
        return result
    }

    nonisolated static func removing(stepID: UUID, from steps: [WorkflowStep]) -> [WorkflowStep] {
        steps.compactMap { step in
            guard step.id != stepID else { return nil }
            guard step.linkedStepID == stepID else { return step }
            var unlinked = step
            unlinked.linkedStepID = nil
            unlinked.detail = "Linked action removed · Edit this instruction to choose a new action"
            return unlinked
        }
    }

    nonisolated static func nearestCapturedAction(at time: TimeInterval, in steps: [WorkflowStep]) -> WorkflowStep? {
        let captured = steps.filter { !$0.isUserInstruction && isCapturedAction($0.kind) }
        return captured.min { lhs, rhs in
            let leftDistance = abs(lhs.time - time)
            let rightDistance = abs(rhs.time - time)
            if leftDistance == rightDistance { return lhs.time >= time && rhs.time < time }
            return leftDistance < rightDistance
        }
    }

    nonisolated static func promptDescription(for step: WorkflowStep, in workflow: Workflow) -> String {
        let scope = step.instructionScope ?? .thisAction
        let target = step.linkedStepID.flatMap { id in workflow.steps.first(where: { $0.id == id })?.title }
        let targetDescription = target.map { "; target=\"\($0)\"" } ?? ""
        return "time=\(step.time.clockString); scope=\"\(scope.label)\"\(targetDescription); instruction=\"\(step.text ?? step.title)\""
    }

    private nonisolated static func isCapturedAction(_ kind: WorkflowStepKind) -> Bool {
        switch kind {
        case .openApp, .openURL, .click, .typeText, .keyPress, .wait: true
        case .decision, .approval: false
        }
    }

    private nonisolated static func isApprovalInstruction(_ text: String) -> Bool {
        let lower = text.lowercased()
        let explicitBefore = lower.contains("before") || lower.contains("prior to")
        let approvalTerms = ["ask", "confirm", "confirmation", "approve", "approval", "permission"]
        let hasApprovalLanguage = approvalTerms.contains { lower.contains($0) }
        let withoutApproval = lower.contains("without") && hasApprovalLanguage
        return (explicitBefore && hasApprovalLanguage) || withoutApproval
    }

    private nonisolated static func detail(scope: WorkflowInstructionScope, linkedStep: WorkflowStep?) -> String {
        if scope == .thisAction, let linkedStep {
            return "Applies to \"\(linkedStep.title)\""
        }
        return scope.explanation
    }

    private nonisolated static func short(_ text: String) -> String {
        text.count > 72 ? "\(text.prefix(72))…" : text
    }
}
