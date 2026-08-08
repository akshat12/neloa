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
        var evidenceImage: Int?
        var imageX: Double?
        var imageY: Double?
    }

    static let instructions = """
    You are Neloa's private workflow-learning engine. Infer what the person did from ordered screenshots, captured actions, OCR, and narration. Never invent an executable action. Use only supplied step IDs for action annotations. Return one JSON object and no markdown.
    """

    static func prompt(candidate: Workflow, frames: [WorkflowEvidenceFrame]) throws -> String {
        let promptSteps = candidate.steps.map { step in
            let visualLocation = evidenceLocation(for: step, frames: frames)
            return PromptStep(
                id: step.id.uuidString,
                time: step.time,
                kind: step.kind.rawValue,
                currentTitle: step.title,
                currentDetail: step.detail,
                application: step.application,
                text: step.text,
                keyCode: step.keyCode,
                evidenceImage: visualLocation?.image,
                imageX: visualLocation.map { Double($0.point.x) },
                imageY: visualLocation.map { Double($0.point.y) }
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
        - evidenceImage is one-based. imageX/imageY are pixels in that image with a top-left origin; use them to identify a clicked target.
        - Prefer labels such as “Click Download report” over “Click”.
        - Treat typed values, dates, people, files, amounts, and thresholds as details that may vary later.
        - Do not add decisions. Captured narration has already been compiled into supplied decision or approval steps; annotate those supplied IDs instead.
        - Return an empty decisions array. It remains in the response shape only for compatibility with older local-model responses.
        - Use confidence from 0 to 1. Omit uncertain guesses by excluding them.
        """
    }

    static func evidenceLocation(
        for step: WorkflowStep,
        frames: [WorkflowEvidenceFrame]
    ) -> (image: Int, point: CGPoint)? {
        guard let x = step.x, let y = step.y,
              let match = frames.enumerated().min(by: {
                  abs($0.element.time - step.time) < abs($1.element.time - step.time)
              }),
              let width = match.element.imageWidth,
              let height = match.element.imageHeight,
              let captureFrame = match.element.captureFrame,
              width > 0, height > 0, captureFrame.width > 0, captureFrame.height > 0 else { return nil }

        let normalizedX = (x - captureFrame.minX) / captureFrame.width
        let normalizedY = (y - captureFrame.minY) / captureFrame.height
        guard (0...1).contains(normalizedX), (0...1).contains(normalizedY) else { return nil }
        return (
            match.offset + 1,
            CGPoint(x: normalizedX * Double(width), y: normalizedY * Double(height))
        )
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

    static func groundsGenericClicks(_ response: LearnedWorkflowResponse, in candidate: Workflow) -> Bool {
        let genericClickIDs = Set(candidate.steps.compactMap { step -> String? in
            guard step.kind == .click, isGenericClickTitle(step.title) else { return nil }
            return step.id.uuidString.lowercased()
        })
        guard !genericClickIDs.isEmpty else { return true }

        let groundedIDs = Set(response.annotations.compactMap { annotation -> String? in
            guard (annotation.confidence ?? 0) >= 0.55,
                  !isGenericClickTitle(annotation.title) else { return nil }
            return annotation.stepID.lowercased()
        })
        return genericClickIDs.isSubset(of: groundedIDs)
    }

    private static func cleaned(_ value: String, maximumLength: Int) -> String {
        let singleLine = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(singleLine.prefix(maximumLength))
    }

    private static func isGenericClickTitle(_ title: String) -> Bool {
        let normalized = title
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: " ")
        return normalized == "click" || normalized == "right click"
    }

    private static func clock(_ time: TimeInterval) -> String {
        String(format: "%.2f seconds", time)
    }
}
