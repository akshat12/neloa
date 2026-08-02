import Foundation

enum SkillExporter {
    static func slug(_ value: String) -> String {
        let pieces = value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let result = pieces.joined(separator: "-").prefix(64).description
        return result.isEmpty ? "neloa-automation" : result
    }

    static func markdown(for workflow: Workflow) -> String {
        let inputs = workflow.steps.filter { $0.kind == .typeText }
        let approvals = workflow.steps.filter { $0.kind == .approval || $0.requiresApproval }
        let steps = workflow.steps.enumerated().map { index, step in
            "\(index + 1). **\(step.title)**\(step.detail.isEmpty ? "" : " — \(sanitized(step.detail))")"
        }.joined(separator: "\n")
        let inputList = inputs.isEmpty
            ? "- No variable inputs were identified."
            : inputs.map { "- `\(sanitized($0.text ?? "Input"))` — may be changed for an individual run." }.joined(separator: "\n")
        let approvalList = approvals.isEmpty
            ? "- Ask before any irreversible or external action."
            : approvals.map { "- \(sanitized($0.title))" }.joined(separator: "\n")

        return """
        ---
        name: \(slug(workflow.name))
        description: Follow the \(sanitized(workflow.name)) process taught in Neloa, adapting only user-specified inputs and preserving its approval rules.
        ---

        # \(workflow.name)

        This portable skill was taught by demonstration in Neloa. Prefer stable APIs, connectors, browser semantics, or accessibility elements over recorded screen coordinates.

        ## Flexible inputs

        \(inputList)

        ## Procedure

        \(steps)

        ## Approval rules

        \(approvalList)

        ## Runtime behavior

        - Ask a concise question when a required value is missing.
        - Show the user what differs from the taught workflow before execution.
        - Treat requested changes as one-time unless the user explicitly saves them.
        - Stop and ask for help when the interface or underlying state no longer matches the taught process.
        """
    }

    private static func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "---", with: "—")
    }
}
