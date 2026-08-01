import Foundation

struct AgentReplacement: Codable, Sendable {
    var stepID: String
    var text: String
    var reason: String

    enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case text
        case reason
    }
}

struct AgentPlanResponse: Codable, Sendable {
    var summary: String
    var replacements: [AgentReplacement]
}

enum RunPlanner {
    static func plan(workflow: Workflow, instruction: String, agentResponse: AgentPlanResponse? = nil) -> RunPlan {
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInstruction.isEmpty, cleanInstruction.lowercased() != "run it the same way" else {
            return RunPlan(instruction: cleanInstruction, steps: workflow.steps, changes: [], summary: "Run the saved workflow without changes")
        }

        var steps = workflow.steps
        var changes: [PlannedChange] = []

        if let agentResponse {
            for replacement in agentResponse.replacements {
                guard let id = UUID(uuidString: replacement.stepID),
                      let index = steps.firstIndex(where: { $0.id == id }),
                      let before = steps[index].text,
                      steps[index].kind == .typeText else { continue }
                steps[index].text = replacement.text
                steps[index].title = "Type \(short(replacement.text))"
                changes.append(PlannedChange(stepID: id, before: before, after: replacement.text, reason: replacement.reason))
            }
            return RunPlan(instruction: cleanInstruction, steps: steps, changes: changes, summary: agentResponse.summary)
        }

        if let replacement = explicitReplacement(in: cleanInstruction) {
            for index in steps.indices where steps[index].kind == .typeText {
                guard let before = steps[index].text, before.localizedCaseInsensitiveContains(replacement.from) else { continue }
                let after = before.replacingOccurrences(of: replacement.from, with: replacement.to, options: .caseInsensitive)
                steps[index].text = after
                steps[index].title = "Type \(short(after))"
                changes.append(PlannedChange(stepID: steps[index].id, before: before, after: after, reason: cleanInstruction))
            }
        } else if let value = requestedValue(in: cleanInstruction),
                  let index = bestInputStep(in: steps, for: value) {
            let before = steps[index].text ?? ""
            steps[index].text = value
            steps[index].title = "Type \(short(value))"
            changes.append(PlannedChange(stepID: steps[index].id, before: before, after: value, reason: cleanInstruction))
        }

        let summary = changes.isEmpty
            ? "No safe value change was inferred; review the unchanged workflow"
            : "Apply \(changes.count) one-time change\(changes.count == 1 ? "" : "s")"
        return RunPlan(instruction: cleanInstruction, steps: steps, changes: changes, summary: summary)
    }

    static func prompt(workflow: Workflow, instruction: String) -> String {
        let inputs = workflow.steps.filter { $0.kind == .typeText }.map {
            "{\"step_id\":\"\($0.id.uuidString)\",\"current_text\":\"\(jsonEscape($0.text ?? ""))\"}"
        }.joined(separator: ",")
        return """
        You customize a saved desktop automation for one run. Change only typed input values explicitly requested by the user. Never add clicks, sending, purchasing, deletion, or other side effects. Return only JSON matching {"summary":"...","replacements":[{"step_id":"...","text":"...","reason":"..."}]}. If the request cannot be satisfied only by replacing typed values, return an empty replacements array and explain why in summary.

        Workflow: \(workflow.name)
        Typed inputs: [\(inputs)]
        User instruction: \(instruction)
        """
    }

    private static func explicitReplacement(in instruction: String) -> (from: String, to: String)? {
        let pattern = #"(?i)(?:replace|change)\s+[\"']?(.+?)[\"']?\s+(?:with|to)\s+[\"']?(.+?)[\"']?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: instruction, range: NSRange(instruction.startIndex..., in: instruction)),
              let fromRange = Range(match.range(at: 1), in: instruction),
              let toRange = Range(match.range(at: 2), in: instruction) else { return nil }
        return (String(instruction[fromRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(instruction[toRange]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func requestedValue(in instruction: String) -> String? {
        let quoted = #"[\"']([^\"']+)[\"']"#
        if let regex = try? NSRegularExpression(pattern: quoted),
           let match = regex.firstMatch(in: instruction, range: NSRange(instruction.startIndex..., in: instruction)),
           let range = Range(match.range(at: 1), in: instruction) {
            return String(instruction[range])
        }

        let patterns = [
            #"(?i)\b(?:for|using|amount|date|threshold)\s+(?:of\s+)?(\$?[0-9][0-9,]*(?:\.[0-9]+)?%?|(?:january|february|march|april|may|june|july|august|september|october|november|december)\s+[0-9]{0,2}(?:,?\s+[0-9]{4})?)\b"#,
            #"\b(\$[0-9][0-9,]*(?:\.[0-9]+)?|[0-9]+(?:\.[0-9]+)?%)\b"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: instruction, range: NSRange(instruction.startIndex..., in: instruction)),
               let range = Range(match.range(at: 1), in: instruction) {
                return String(instruction[range])
            }
        }
        return nil
    }

    private static func bestInputStep(in steps: [WorkflowStep], for value: String) -> Int? {
        let wantsNumber = value.rangeOfCharacter(from: .decimalDigits) != nil
        if wantsNumber, let index = steps.firstIndex(where: { $0.kind == .typeText && ($0.text?.rangeOfCharacter(from: .decimalDigits) != nil) }) {
            return index
        }
        return steps.firstIndex { $0.kind == .typeText }
    }

    private static func short(_ text: String) -> String {
        text.count > 28 ? "\(text.prefix(28))…" : text
    }

    private static func jsonEscape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
