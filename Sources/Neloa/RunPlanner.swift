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
    private struct SpreadsheetCellRequest {
        var target: String
        var value: String
    }

    private struct PromptInput: Encodable {
        var order: Int
        var stepID: String
        var title: String
        var detail: String
        var target: String?
        var currentText: String
        var application: String?

        enum CodingKeys: String, CodingKey {
            case order
            case stepID = "step_id"
            case title
            case detail
            case target
            case currentText = "current_text"
            case application
        }
    }

    static func plan(workflow: Workflow, instruction: String, agentResponse: AgentPlanResponse? = nil) -> RunPlan {
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isUnchangedInstruction(cleanInstruction) else {
            return RunPlan(instruction: cleanInstruction, steps: workflow.steps, changes: [], summary: "Run the saved workflow without changes")
        }

        if let spreadsheetPlan = spreadsheetCellPlan(workflow: workflow, instruction: cleanInstruction) {
            return spreadsheetPlan
        }

        var steps = workflow.steps
        var changes: [PlannedChange] = []

        if let agentResponse {
            var replacedStepIDs: Set<UUID> = []
            for replacement in agentResponse.replacements {
                guard let id = UUID(uuidString: replacement.stepID),
                      replacedStepIDs.insert(id).inserted,
                      let index = steps.firstIndex(where: { $0.id == id }),
                      let before = steps[index].text,
                      steps[index].isRunVariable else { continue }
                guard let safeText = safeAgentText(replacement.text), safeText != before else { continue }
                guard !isStructuralSpreadsheetReference(safeText, for: steps[index]) else { continue }
                steps[index].text = safeText
                steps[index].title = "Type \(short(safeText))"
                changes.append(PlannedChange(
                    stepID: id,
                    before: before,
                    after: safeText,
                    reason: String(replacement.reason.prefix(240))
                ))
            }
            return RunPlan(
                instruction: cleanInstruction,
                steps: steps,
                changes: changes,
                summary: String(agentResponse.summary.prefix(240))
            )
        }

        if let replacement = explicitReplacement(in: cleanInstruction) {
            for index in steps.indices where steps[index].isRunVariable {
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

    static func isUnchangedInstruction(_ instruction: String) -> Bool {
        let clean = instruction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return clean.isEmpty || clean == "run it the same way" || clean == "run the original"
    }

    static func prompt(workflow: Workflow, instruction: String) -> String {
        let promptInputs = workflow.steps.enumerated().compactMap { index, step -> PromptInput? in
            guard step.isRunVariable else { return nil }
            return PromptInput(
                order: index + 1,
                stepID: step.id.uuidString,
                title: step.title,
                detail: step.detail,
                target: step.target,
                currentText: step.text ?? "",
                application: step.application
            )
        }
        let inputData = (try? JSONEncoder().encode(promptInputs)) ?? Data("[]".utf8)
        let inputs = String(decoding: inputData, as: UTF8.self)
        let savedInstructions = workflow.steps.filter(\.isUserInstruction).map {
            "- \(WorkflowInstructionSupport.promptDescription(for: $0, in: workflow))"
        }.joined(separator: "\n")
        return """
        You customize a saved desktop automation for one run. Change only typed input values explicitly requested by the user. A request may contain several values; map every requested value to the matching typed-input role using title, detail, current text, and demonstrated order. Never add clicks, sending, purchasing, deletion, or other side effects. Explicit saved user instructions take priority over inferred workflow details and must not be silently discarded. Return only JSON matching {"summary":"...","replacements":[{"step_id":"...","text":"...","reason":"..."}]}. Use each exact step_id at most once. If the request cannot be satisfied only by replacing typed values, return an empty replacements array and explain why in summary.

        Workflow: \(workflow.name)
        Typed inputs: \(inputs)
        Explicit saved user instructions:
        \(savedInstructions.isEmpty ? "- None" : savedInstructions)
        User instruction: \(instruction)
        """
    }

    /// Builds a narrowly scoped structural variation for spreadsheet workflows.
    /// Unlike an arbitrary model-generated click, this uses Google Sheets' own
    /// Go to range command and accepts only a validated cell address and text.
    static func spreadsheetCellPlan(workflow: Workflow, instruction: String) -> RunPlan? {
        guard let request = spreadsheetCellRequest(in: instruction),
              let safeValue = safeAgentText(request.value) else { return nil }

        let isGoogleSheetsWorkflow = workflow.steps.contains {
            $0.bundleIdentifier == "com.google.Chrome"
                && ($0.kind == .openURL || $0.kind == .typeText || $0.kind == .keyPress)
        } && (workflow.name.localizedCaseInsensitiveContains("spreadsheet")
            || workflow.transcript.localizedCaseInsensitiveContains("sheet"))
        guard isGoogleSheetsWorkflow else { return nil }

        var steps = workflow.steps
        let candidates = steps.indices.filter {
            steps[$0].isRunVariable && spreadsheetAddress(from: steps[$0].target) != nil
        }
        guard !candidates.isEmpty else { return nil }

        // A value change for an already demonstrated cell remains ordinary
        // model planning. This path is only for the new, structured capability:
        // safely navigating to a different cell without inventing a click.
        let requestedCell = request.target.split(separator: "!").last.map(String.init) ?? request.target
        if candidates.contains(where: {
            let existing = spreadsheetAddress(from: steps[$0].target) ?? ""
            return existing.split(separator: "!").last.map(String.init) == requestedCell
        }) {
            return nil
        }

        let wantsNumber = safeValue.rangeOfCharacter(from: .decimalDigits) != nil
        let matchingValueKind = candidates.first {
            wantsNumber && steps[$0].text?.rangeOfCharacter(from: .decimalDigits) != nil
        }
        guard let originalIndex = matchingValueKind ?? candidates.first else { return nil }

        let originalStep = steps[originalIndex]
        let oldTarget = originalStep.target ?? "Current cell"
        let target = resolvedSpreadsheetTarget(request.target, preservingSheetFrom: originalStep.target)

        var updatedInput = originalStep
        updatedInput.target = target
        updatedInput.text = safeValue
        updatedInput.title = "Set \(target) to \(short(safeValue))"
        updatedInput.detail = "Spreadsheet cell \(target) · Changed for this run"

        var selection = WorkflowStep(
            kind: .selectSpreadsheetCell,
            title: "Go to \(target)",
            detail: "Use Google Sheets’ Go to range command",
            time: max(0, originalStep.time - 0.2),
            target: target,
            application: originalStep.application,
            bundleIdentifier: originalStep.bundleIdentifier,
            displayID: originalStep.displayID
        )
        selection.runVariable = false

        var inputIndex = originalIndex
        if originalIndex > steps.startIndex {
            let previousIndex = steps.index(before: originalIndex)
            let previous = steps[previousIndex]
            if previous.kind == .keyPress, previous.target == originalStep.target {
                steps[previousIndex] = selection
            } else {
                steps.insert(selection, at: originalIndex)
                inputIndex += 1
            }
        } else {
            steps.insert(selection, at: originalIndex)
            inputIndex += 1
        }
        steps[inputIndex] = updatedInput

        for index in steps.indices where index != inputIndex && steps[index].target == originalStep.target {
            if steps[index].kind == .keyPress {
                steps[index].target = target
                if steps[index].keyCode == 36 {
                    steps[index].title = "Finish editing \(target)"
                }
            }
        }

        var changes: [PlannedChange] = []
        if oldTarget.caseInsensitiveCompare(target) != .orderedSame {
            changes.append(PlannedChange(
                stepID: originalStep.id,
                before: oldTarget,
                after: target,
                reason: "Use the requested spreadsheet cell"
            ))
        }
        let oldValue = originalStep.text ?? ""
        if oldValue != safeValue {
            changes.append(PlannedChange(
                stepID: originalStep.id,
                before: oldValue,
                after: safeValue,
                reason: "Use the requested value in \(target)"
            ))
        }
        guard !changes.isEmpty else { return nil }

        return RunPlan(
            instruction: instruction.trimmingCharacters(in: .whitespacesAndNewlines),
            steps: steps,
            changes: changes,
            summary: "Set \(target) to \(short(safeValue)) for this run"
        )
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

    private static func spreadsheetCellRequest(in instruction: String) -> SpreadsheetCellRequest? {
        let cell = #"((?:sheet\s*[0-9]+\s*!)?[A-Z]{1,3}\s*[1-9][0-9]{0,6})"#
        let patterns = [
            #"(?i)\b(?:set|put|enter|type|write)\s+(?:(?:cell|column)\s+)?"# + cell + #"\s+(?:to|as|=|with)\s+(.+?)\s*$"#,
            #"(?i)\b(?:put|enter|type|write)\s+(.+?)\s+(?:in|into|at)\s+(?:(?:cell|column)\s+)?"# + cell + #"\s*$"#
        ]
        for (position, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: instruction, range: NSRange(instruction.startIndex..., in: instruction)) else {
                continue
            }
            let targetGroup = position == 0 ? 1 : 2
            let valueGroup = position == 0 ? 2 : 1
            guard let targetRange = Range(match.range(at: targetGroup), in: instruction),
                  let valueRange = Range(match.range(at: valueGroup), in: instruction) else { continue }
            let target = normalizeSpreadsheetTarget(String(instruction[targetRange]))
            let value = unquoted(String(instruction[valueRange]))
            guard !target.isEmpty, !value.isEmpty else { continue }
            return SpreadsheetCellRequest(target: target, value: value)
        }
        return nil
    }

    private static func resolvedSpreadsheetTarget(_ requested: String, preservingSheetFrom original: String?) -> String {
        guard !requested.contains("!"), let original, let separator = original.lastIndex(of: "!") else {
            return requested
        }
        return "\(original[...separator])\(requested)"
    }

    private static func spreadsheetAddress(from target: String?) -> String? {
        guard let target else { return nil }
        let normalized = normalizeSpreadsheetTarget(target)
        guard normalized.range(
            of: #"(?i)^(?:SHEET[0-9]+!)?[A-Z]{1,3}[1-9][0-9]{0,6}$"#,
            options: .regularExpression
        ) != nil else { return nil }
        return normalized
    }

    private static func normalizeSpreadsheetTarget(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "").uppercased()
    }

    private static func unquoted(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.count >= 2,
           let first = result.first,
           let last = result.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            result.removeFirst()
            result.removeLast()
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requestedValue(in instruction: String) -> String? {
        let quoted = #"[\"']([^\"']+)[\"']"#
        if let regex = try? NSRegularExpression(pattern: quoted),
           let match = regex.firstMatch(in: instruction, range: NSRange(instruction.startIndex..., in: instruction)),
           let range = Range(match.range(at: 1), in: instruction) {
            return String(instruction[range])
        }

        let patterns = [
            #"(?i)\b(?:for|using|use|amount|date|threshold)\s+(?:of\s+)?(\$?[0-9][0-9,]*(?:\.[0-9]+)?%?|(?:january|february|march|april|may|june|july|august|september|october|november|december)\s*[0-9]{0,2}(?:,?\s+[0-9]{4})?)\b"#,
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
        if wantsNumber, let index = steps.firstIndex(where: { $0.isRunVariable && ($0.text?.rangeOfCharacter(from: .decimalDigits) != nil) }) {
            return index
        }
        return steps.firstIndex { $0.isRunVariable }
    }

    private static func short(_ text: String) -> String {
        text.count > 28 ? "\(text.prefix(28))…" : text
    }

    private static func safeAgentText(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= 500 else { return nil }
        let disallowed = text.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }
        return disallowed ? nil : text
    }

    private static func isStructuralSpreadsheetReference(_ text: String, for step: WorkflowStep) -> Bool {
        guard step.target?.range(
            of: #"(?i)^(?:sheet\s*\d+!)?[A-Z]{1,3}\d+$"#,
            options: .regularExpression
        ) != nil else { return false }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.range(
            of: #"(?i)^(?:sheet\s*\d+|(?:sheet\s*\d+!)?[A-Z]{1,3}\d+)$"#,
            options: .regularExpression
        ) != nil
    }

}
