import CoreGraphics
import Foundation

enum WorkflowCompiler {
    static func compile(
        events: [CaptureEvent],
        transcript: String,
        narrationSegments: [NarrationSegment] = [],
        name: String = "Untitled automation"
    ) -> Workflow {
        var steps: [WorkflowStep] = []
        var lastApp: String?
        var previousClick: CaptureEvent?

        for event in events.sorted(by: { $0.time < $1.time }) {
            if let app = event.application, app != lastApp {
                steps.append(WorkflowStep(
                    kind: .openApp,
                    title: "Open \(app)",
                    detail: "Bring \(app) to the front",
                    time: event.time,
                    application: app,
                    bundleIdentifier: event.bundleIdentifier,
                    displayID: event.displayID
                ))
                lastApp = app
            }

            switch event.kind {
            case .appSwitch:
                continue
            case .click, .rightClick:
                if let previousClick,
                   previousClick.kind == event.kind,
                   previousClick.bundleIdentifier == event.bundleIdentifier,
                   event.time - previousClick.time < 0.14,
                   abs((previousClick.x ?? 0) - (event.x ?? 0)) < 2,
                   abs((previousClick.y ?? 0) - (event.y ?? 0)) < 2 {
                    continue
                }
                steps.append(WorkflowStep(
                    kind: .click,
                    title: clickTitle(rightClick: event.kind == .rightClick, target: event.target),
                    detail: clickDetail(target: event.target, x: event.x, y: event.y),
                    time: event.time,
                    x: event.x,
                    y: event.y,
                    target: event.target,
                    application: event.application,
                    bundleIdentifier: event.bundleIdentifier,
                    displayID: event.displayID,
                    requiresApproval: requiresApproval(for: event.target)
                ))
                previousClick = event
            case .text:
                guard let text = event.text, !text.isEmpty else { continue }
                if let index = steps.indices.last,
                   steps[index].kind == .typeText,
                   steps[index].application == event.application,
                   event.time - steps[index].time < 2.0 {
                    steps[index].text = (steps[index].text ?? "") + text
                    steps[index].title = inputTitle(text: steps[index].text ?? "", target: steps[index].target)
                    steps[index].time = event.time
                } else {
                    steps.append(WorkflowStep(
                        kind: .typeText,
                        title: inputTitle(text: text, target: event.target),
                        detail: inputDetail(target: event.target),
                        time: event.time,
                        text: text,
                        target: event.target,
                        application: event.application,
                        bundleIdentifier: event.bundleIdentifier
                    ))
                }
            case .keyPress:
                steps.append(WorkflowStep(
                    kind: .keyPress,
                    title: keyTitle(event.keyCode, flags: event.flags),
                    time: event.time,
                    keyCode: event.keyCode,
                    flags: event.flags,
                    application: event.application,
                    bundleIdentifier: event.bundleIdentifier
                ))
            }
        }

        let timedUtterances = NarrationTimeline.utterances(from: narrationSegments)
        let timedDecisions = timedUtterances.map(\.text).filter(isDecisionSentence)
        let decisions = timedDecisions.isEmpty ? decisionSentences(in: transcript) : timedDecisions
        for sentence in decisions {
            let isApproval = sentence.lowercased().contains("ask") && sentence.lowercased().contains("before")
            let narrationTime = narrationTime(for: sentence, segments: narrationSegments)
            let rule = WorkflowStep(
                kind: isApproval ? .approval : .decision,
                title: sentence,
                detail: isApproval ? "The run pauses here for you" : "Neloa will interpret this rule at run time",
                time: narrationTime ?? steps.last?.time ?? 0,
                requiresApproval: isApproval
            )
            if let narrationTime,
               let nextAction = steps.firstIndex(where: {
                   [.click, .typeText, .keyPress].contains($0.kind) && $0.time >= narrationTime
               }) {
                if isApproval { steps[nextAction].requiresApproval = false }
                steps.insert(rule, at: nextAction)
            } else if isApproval,
               let finalAction = steps.lastIndex(where: { [.click, .typeText, .keyPress].contains($0.kind) }) {
                steps[finalAction].requiresApproval = false
                steps.insert(rule, at: finalAction)
            } else {
                let insertionIndex = steps.firstIndex { $0.time >= rule.time } ?? steps.endIndex
                steps.insert(rule, at: insertionIndex)
            }
        }

        if steps.isEmpty, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            steps.append(WorkflowStep(
                kind: .decision,
                title: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
                detail: "Spoken instruction",
                time: 0
            ))
        }

        return WorkflowSemanticEnricher.enrich(
            Workflow(
                name: name,
                transcript: transcript,
                narrationSegments: narrationSegments.isEmpty ? nil : narrationSegments,
                steps: steps
            )
        )
    }

    private static func decisionSentences(in transcript: String) -> [String] {
        transcript
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter(isDecisionSentence)
    }

    private static func isDecisionSentence(_ sentence: String) -> Bool {
        let value = sentence.lowercased()
        return value.contains("if ") || value.contains("when ") || value.contains("always ") || value.contains("before ")
    }

    private static func narrationTime(for sentence: String, segments: [NarrationSegment]) -> TimeInterval? {
        let tokens = sentenceTokens(sentence)
        guard !tokens.isEmpty else { return nil }
        let timedTokens = segments.flatMap { segment in
            sentenceTokens(segment.text).map { ($0, segment.time) }
        }
        guard !timedTokens.isEmpty else { return nil }

        let ruleCues = Set(["if", "when", "always", "before"].filter(tokens.contains))
        if let match = timedTokens.filter({ ruleCues.contains($0.0) }).min(by: { $0.1 < $1.1 }) {
            return match.1
        }

        let distinctive = tokens.filter { token in
            token.count > 3 && !["always", "before", "when", "then", "this", "that", "with"].contains(token)
        }
        for token in distinctive + tokens {
            if let match = timedTokens.first(where: { $0.0 == token }) { return match.1 }
        }
        return nil
    }

    private static func sentenceTokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static func coordinateDescription(x: Double?, y: Double?) -> String {
        guard let x, let y else { return "Recorded position" }
        return "At \(Int(x)), \(Int(y))"
    }

    private static func clickTitle(rightClick: Bool, target: String?) -> String {
        let action = rightClick ? "Right-click" : "Click"
        guard let target, !target.isEmpty else { return action }
        return "\(action) \(target.count > 48 ? "\(target.prefix(48))…" : target)"
    }

    private static func clickDetail(target: String?, x: Double?, y: Double?) -> String {
        guard let target else { return coordinateDescription(x: x, y: y) }
        return requiresApproval(for: target)
            ? "Captured control: \(target) · Neloa will ask before this action"
            : "Captured control: \(target)"
    }

    private static func inputTitle(text: String, target: String?) -> String {
        guard let target else { return "Type \(displayText(text))" }
        return "Enter \(displayText(text)) in \(displayText(target))"
    }

    private static func inputDetail(target: String?) -> String {
        target.map { "Field: \($0) · Value can change each run" }
            ?? "Text can be changed for each run"
    }

    nonisolated static func requiresApproval(for target: String?) -> Bool {
        guard let target = target?.lowercased() else { return false }
        let consequentialWords = [
            "send", "share", "submit", "publish", "post", "purchase",
            "buy", "pay", "delete", "remove", "upload"
        ]
        return consequentialWords.contains { word in
            target.range(of: #"\b"# + NSRegularExpression.escapedPattern(for: word) + #"\b"#, options: .regularExpression) != nil
        }
    }

    private static func displayText(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ↵ ")
        return cleaned.count > 28 ? "\(cleaned.prefix(28))…" : cleaned
    }

    private static func keyTitle(_ keyCode: Int?, flags: UInt64?) -> String {
        if let flags, CGEventFlags(rawValue: flags).contains(.maskCommand) {
            return switch keyCode {
            case 0: "Select all"
            case 1: "Save"
            case 7: "Cut selected content"
            case 8: "Copy selected content"
            case 9: "Paste copied content"
            case 17: "Open a new tab"
            case 37: "Focus the address bar"
            default: "Use a keyboard shortcut"
            }
        }
        return switch keyCode {
        case 36: "Press Return"
        case 48: "Press Tab"
        case 51: "Press Delete"
        case 53: "Press Escape"
        case 123: "Press Left Arrow"
        case 124: "Press Right Arrow"
        case 125: "Press Down Arrow"
        case 126: "Press Up Arrow"
        default: "Press a key"
        }
    }
}
