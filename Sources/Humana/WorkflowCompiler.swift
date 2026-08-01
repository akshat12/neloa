import Foundation

enum WorkflowCompiler {
    static func compile(events: [CaptureEvent], transcript: String, name: String = "Untitled automation") -> Workflow {
        var steps: [WorkflowStep] = []
        var lastApp: String?

        for event in events.sorted(by: { $0.time < $1.time }) {
            if let app = event.application, app != lastApp {
                steps.append(WorkflowStep(
                    kind: .openApp,
                    title: "Open \(app)",
                    detail: "Bring \(app) to the front",
                    time: event.time,
                    application: app,
                    bundleIdentifier: event.bundleIdentifier
                ))
                lastApp = app
            }

            switch event.kind {
            case .appSwitch:
                continue
            case .click, .rightClick:
                steps.append(WorkflowStep(
                    kind: .click,
                    title: event.kind == .rightClick ? "Right-click" : "Click",
                    detail: coordinateDescription(x: event.x, y: event.y),
                    time: event.time,
                    x: event.x,
                    y: event.y,
                    application: event.application,
                    bundleIdentifier: event.bundleIdentifier
                ))
            case .text:
                guard let text = event.text, !text.isEmpty else { continue }
                if let index = steps.indices.last,
                   steps[index].kind == .typeText,
                   steps[index].application == event.application,
                   event.time - steps[index].time < 2.0 {
                    steps[index].text = (steps[index].text ?? "") + text
                    steps[index].title = "Type \(displayText(steps[index].text ?? ""))"
                    steps[index].time = event.time
                } else {
                    steps.append(WorkflowStep(
                        kind: .typeText,
                        title: "Type \(displayText(text))",
                        detail: "Text can be changed for each run",
                        time: event.time,
                        text: text,
                        application: event.application,
                        bundleIdentifier: event.bundleIdentifier
                    ))
                }
            case .keyPress:
                steps.append(WorkflowStep(
                    kind: .keyPress,
                    title: keyTitle(event.keyCode),
                    time: event.time,
                    keyCode: event.keyCode,
                    flags: event.flags,
                    application: event.application,
                    bundleIdentifier: event.bundleIdentifier
                ))
            }
        }

        let decisions = decisionSentences(in: transcript)
        for sentence in decisions {
            let isApproval = sentence.lowercased().contains("ask") && sentence.lowercased().contains("before")
            let rule = WorkflowStep(
                kind: isApproval ? .approval : .decision,
                title: sentence,
                detail: isApproval ? "The run pauses here for you" : "Humana will interpret this rule at run time",
                time: steps.last?.time ?? 0,
                requiresApproval: isApproval
            )
            if isApproval,
               let finalAction = steps.lastIndex(where: { [.click, .typeText, .keyPress].contains($0.kind) }) {
                steps.insert(rule, at: finalAction)
            } else {
                steps.append(rule)
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

        return Workflow(name: name, transcript: transcript, steps: steps)
    }

    private static func decisionSentences(in transcript: String) -> [String] {
        transcript
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { sentence in
                let value = sentence.lowercased()
                return value.contains("if ") || value.contains("when ") || value.contains("always ") || value.contains("before ")
            }
    }

    private static func coordinateDescription(x: Double?, y: Double?) -> String {
        guard let x, let y else { return "Recorded position" }
        return "At \(Int(x)), \(Int(y))"
    }

    private static func displayText(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\n", with: " ↵ ")
        return cleaned.count > 28 ? "\(cleaned.prefix(28))…" : cleaned
    }

    private static func keyTitle(_ keyCode: Int?) -> String {
        switch keyCode {
        case 36: "Press Return"
        case 48: "Press Tab"
        case 51: "Press Delete"
        case 53: "Press Escape"
        default: "Press a key"
        }
    }
}
