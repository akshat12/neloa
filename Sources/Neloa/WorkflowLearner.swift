import Foundation

struct LearnedWorkflowResponse: Decodable, Sendable {
    struct Annotation: Decodable, Sendable {
        var stepID: String
        var title: String
        var detail: String?
        var confidence: Double?
    }

    struct Decision: Decodable, Sendable {
        var title: String
        var detail: String?
        var time: TimeInterval?
        var requiresApproval: Bool?
        var confidence: Double?
    }

    var name: String?
    var annotations: [Annotation]
    var decisions: [Decision]
}

enum WorkflowLearner {
    private struct PromptStep: Encodable {
        var id: String
        var time: TimeInterval
        var kind: String
        var currentTitle: String
        var currentDetail: String
        var application: String?
        var text: String?
        var keyCode: Int?
        var x: Double?
        var y: Double?
    }

    static let instructions = """
    You are Neloa's private workflow-learning engine. Infer what the person did from ordered screenshots, captured actions, OCR, and narration. Never invent an executable action. Use only supplied step IDs for action annotations. Return one JSON object and no markdown.
    """

    static func prompt(candidate: Workflow, frames: [WorkflowEvidenceFrame]) throws -> String {
        let promptSteps = candidate.steps.map {
            PromptStep(
                id: $0.id.uuidString,
                time: $0.time,
                kind: $0.kind.rawValue,
                currentTitle: $0.title,
                currentDetail: $0.detail,
                application: $0.application,
                text: $0.text,
                keyCode: $0.keyCode,
                x: $0.x,
                y: $0.y
            )
        }
        let stepsData = try JSONEncoder().encode(promptSteps)
        let stepsJSON = String(decoding: stepsData, as: UTF8.self)
        let evidence = frames.enumerated().map { index, frame in
            let text = frame.recognizedText.joined(separator: " | ")
            return "Image \(index + 1): \(clock(frame.time)); visible text: \(text.isEmpty ? "none recognized" : text)"
        }.joined(separator: "\n")

        return """
        Learn this demonstrated workflow.

        Narration:
        \(candidate.transcript.isEmpty ? "No narration was captured." : candidate.transcript)

        Captured executable steps (JSON):
        \(stepsJSON)

        Ordered screenshots:
        \(evidence.isEmpty ? "No screenshots were available." : evidence)

        Return exactly this JSON shape:
        {
          "name": "short verb-first workflow name",
          "annotations": [
            {"stepID":"an exact supplied UUID","title":"specific human-readable action","detail":"what target or value was used","confidence":0.0}
          ],
          "decisions": [
            {"title":"a narrated conditional rule only","detail":"how to apply it","time":0.0,"requiresApproval":false,"confidence":0.0}
          ]
        }

        Rules:
        - Keep actions in the captured order and annotate only supplied IDs.
        - Prefer labels such as “Click Download report” over “Click”.
        - Treat typed values, dates, people, files, amounts, and thresholds as details that may vary later.
        - Do not add decisions. Captured narration has already been compiled into supplied decision or approval steps; annotate those supplied IDs instead.
        - Return an empty decisions array. It remains in the response shape only for compatibility with older local-model responses.
        - Use confidence from 0 to 1. Omit uncertain guesses by excluding them.
        """
    }

    static func decode(_ content: String) throws -> LearnedWorkflowResponse {
        guard let data = QwenResponseSupport.jsonData(
            from: content,
            topLevelKeys: ["name", "annotations", "decisions"]
        ) else { throw QwenRuntimeError.invalidResponse }
        return try JSONDecoder().decode(LearnedWorkflowResponse.self, from: data)
    }

    static func apply(_ response: LearnedWorkflowResponse, to candidate: Workflow) -> Workflow {
        var workflow = candidate
        let stepIndices = Dictionary(uniqueKeysWithValues: workflow.steps.indices.map {
            (workflow.steps[$0].id.uuidString.lowercased(), $0)
        })

        for annotation in response.annotations where (annotation.confidence ?? 0) >= 0.55 {
            guard let index = stepIndices[annotation.stepID.lowercased()] else { continue }
            let title = cleaned(annotation.title, maximumLength: 90)
            guard !title.isEmpty else { continue }
            workflow.steps[index].title = title
            if let detail = annotation.detail {
                let cleanedDetail = cleaned(detail, maximumLength: 180)
                if !cleanedDetail.isEmpty { workflow.steps[index].detail = cleanedDetail }
            }
        }

        if let name = response.name {
            let cleanedName = cleaned(name, maximumLength: 60)
            if !cleanedName.isEmpty { workflow.name = cleanedName }
        }
        workflow.steps.sort { lhs, rhs in
            if lhs.time == rhs.time { return lhs.kind == .approval && rhs.kind != .approval }
            return lhs.time < rhs.time
        }
        return workflow
    }

    private static func cleaned(_ value: String, maximumLength: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(singleLine.prefix(maximumLength))
    }

    private static func clock(_ time: TimeInterval) -> String {
        String(format: "%.2f seconds", time)
    }
}
