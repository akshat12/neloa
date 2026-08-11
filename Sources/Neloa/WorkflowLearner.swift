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

    struct ProposedAction: Decodable, Sendable {
        var kind: String
        var title: String
        var detail: String?
        var time: TimeInterval
        var image: Int?
        var x: Double?
        var y: Double?
        var text: String?
        var key: String?
        var confidence: Double?

        private enum CodingKeys: String, CodingKey {
            case kind, title, detail, time, image, x, y, text, key, confidence
        }

        init(
            kind: String,
            title: String,
            detail: String? = nil,
            time: TimeInterval,
            image: Int? = nil,
            x: Double? = nil,
            y: Double? = nil,
            text: String? = nil,
            key: String? = nil,
            confidence: Double? = nil
        ) {
            self.kind = kind
            self.title = title
            self.detail = detail
            self.time = time
            self.image = image
            self.x = x
            self.y = y
            self.text = text
            self.key = key
            self.confidence = confidence
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            kind = try container.decode(String.self, forKey: .kind)
            title = try container.decode(String.self, forKey: .title)
            time = try container.decode(TimeInterval.self, forKey: .time)
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
            image = try container.decodeIfPresent(Int.self, forKey: .image)
            x = try container.decodeIfPresent(Double.self, forKey: .x)
            y = try container.decodeIfPresent(Double.self, forKey: .y)
            text = try container.decodeIfPresent(String.self, forKey: .text)
            key = try container.decodeIfPresent(String.self, forKey: .key)

            if let plainDetail = try? container.decodeIfPresent(String.self, forKey: .detail) {
                detail = plainDetail
            } else if let nested = try? container.nestedContainer(keyedBy: CodingKeys.self, forKey: .detail) {
                detail = nil
                let nestedImage = try nested.decodeIfPresent(Int.self, forKey: .image)
                let nestedX = try nested.decodeIfPresent(Double.self, forKey: .x)
                let nestedY = try nested.decodeIfPresent(Double.self, forKey: .y)
                let nestedText = try nested.decodeIfPresent(String.self, forKey: .text)
                let nestedKey = try nested.decodeIfPresent(String.self, forKey: .key)
                image = image ?? nestedImage
                x = x ?? nestedX
                y = y ?? nestedY
                text = text ?? nestedText
                key = key ?? nestedKey
            } else {
                detail = nil
            }
        }
    }

    var name: String?
    var application: String?
    var annotations: [Annotation]
    var decisions: [Decision]
    var proposedActions: [ProposedAction]?
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
    You are Neloa's private visual workflow-learning engine. Reconstruct the demonstrated task from ordered screenshots, captured actions, OCR, and narration. Ground every action in visible evidence. Return one JSON object and no markdown.
    """

    static func prompt(candidate: Workflow, frames: [WorkflowEvidenceFrame]) throws -> String {
        let replayKinds: Set<WorkflowStepKind> = [.click, .typeText, .keyPress]
        let replaySteps = candidate.steps.filter { replayKinds.contains($0.kind) }
        let promptSteps = replaySteps.map { step in
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
            let focus = frame.focusStepID.map { "; close-up centered on step \($0.uuidString)" } ?? ""
            let dimensions = frame.imageWidth.flatMap { width in frame.imageHeight.map { "\(width)x\($0) pixels" } } ?? "unknown size"
            return "Image \(index + 1): \(clock(frame.time)); \(dimensions)\(focus); visible text: \(text.isEmpty ? "none recognized" : text)"
        }.joined(separator: "\n")
        let applicationContext = candidate.steps
            .filter { $0.kind == .openApp }
            .compactMap(\.application)
            .joined(separator: ", ")
        let reconstructionRule = replaySteps.isEmpty
            ? "There are ZERO captured replay actions. This is a recorder limitation, not evidence that nothing happened. Reconstruct the demonstrated clicks, typed values, and allowed navigation keys in proposedActions. Every explicitly narrated typed value must become a typeText action with image/x/y grounding."
            : "Captured replay actions are present. Return an empty proposedActions array and annotate only their exact IDs."

        return """
        Learn this demonstrated workflow.

        Narration:
        \(candidate.transcript.isEmpty ? "No narration was captured." : candidate.transcript)

        Captured executable steps (JSON):
        \(stepsJSON)
        Captured replay-action count: \(replaySteps.count)
        Recorded application context: \(applicationContext.isEmpty ? "Unknown" : applicationContext)

        Recovery mode:
        \(reconstructionRule)

        Ordered screenshots:
        \(evidence.isEmpty ? "No screenshots were available." : evidence)

        Return exactly this JSON shape:
        {
          "name": "short verb-first workflow name",
          "application": "visible Mac app name (use Google Chrome for a webpage in Chrome), or null",
          "annotations": [
            {"stepID":"an exact supplied UUID","title":"specific human-readable action","detail":"what target or value was used","confidence":0.0}
          ],
          "proposedActions": [
            {"kind":"click or typeText or keyPress","title":"specific visible action","detail":"target or value","time":0.0,"image":1,"x":0.0,"y":0.0,"text":"typed text","key":"Tab or Return","confidence":0.0}
          ],
          "decisions": [
            {"title":"a narrated conditional rule only","detail":"how to apply it","time":0.0,"requiresApproval":false,"confidence":0.0}
          ]
        }

        Rules:
        - Keep actions in demonstrated order. Annotate supplied actions using only their exact IDs.
        - evidenceImage is one-based. imageX/imageY are pixels in that image with a top-left origin; use them to identify a clicked target.
        - Prefer labels such as “Click Download report” over “Click”.
        - Treat typed values, dates, people, files, amounts, and thresholds as details that may vary later.
        - Application context is not a replay action. Never put an app-context item in annotations.
        - Follow Recovery mode exactly. If replay-action count is zero, proposedActions must contain the visibly demonstrated workflow; otherwise proposedActions must be empty.
        - For a proposed click, image is one-based and x/y are exact pixel coordinates in that image using a top-left origin. Choose the center of the visible target.
        - For every proposed typeText, include the exact demonstrated text plus image and x/y at the center of the field that receives it. Neloa will focus that field before typing. For keyPress, key may only be Tab, Return, Escape, or Delete.
        - Do not propose sending, sharing, purchasing, deletion, permission changes, password entry, or any other consequential action. Omit uncertain actions instead of guessing.
        - Proposed actions are a draft the user will review. Use confidence from 0 to 1 and include only actions at 0.72 or higher.
        - Do not add decisions. Captured narration has already been compiled into supplied decision or approval steps; annotate those supplied IDs instead.
        - Return an empty decisions array. It remains in the response shape only for compatibility with older local-model responses.
        - Use confidence from 0 to 1. Omit uncertain guesses by excluding them.
        """
    }

    static func evidenceLocation(
        for step: WorkflowStep,
        frames: [WorkflowEvidenceFrame]
    ) -> (image: Int, point: CGPoint)? {
        let focused = frames.enumerated().filter { $0.element.focusStepID == step.id }
        let candidates = focused.isEmpty ? Array(frames.enumerated()) : focused
        guard let x = step.x, let y = step.y,
              let match = candidates.min(by: {
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
            topLevelKeys: ["name", "application", "annotations", "proposedActions", "decisions"]
        ) else { throw QwenRuntimeError.invalidResponse }
        return try JSONDecoder().decode(LearnedWorkflowResponse.self, from: data)
    }

    static func apply(
        _ response: LearnedWorkflowResponse,
        to candidate: Workflow,
        frames: [WorkflowEvidenceFrame] = []
    ) -> Workflow {
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

        appendVisuallyProposedActions(from: response, frames: frames, to: &workflow)

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

    private static func appendVisuallyProposedActions(
        from response: LearnedWorkflowResponse,
        frames: [WorkflowEvidenceFrame],
        to workflow: inout Workflow
    ) {
        let executableKinds: Set<WorkflowStepKind> = [.click, .typeText, .keyPress]
        guard !workflow.steps.contains(where: { executableKinds.contains($0.kind) }),
              !frames.isEmpty else { return }

        let responseApplication = response.application.map { cleaned($0, maximumLength: 80) }
            .flatMap { value in
                ["", "null", "none", "n/a"].contains(value.lowercased()) ? nil : value
            }
        let application = responseApplication
            ?? workflow.steps.first(where: { $0.kind == .openApp })?.application
        let maximumEvidenceTime = frames.map(\.time).max() ?? 0
        var proposedSteps = (response.proposedActions ?? []).compactMap { action -> WorkflowStep? in
            guard (action.confidence ?? 0) >= 0.72,
                  action.time.isFinite,
                  action.time >= 0 else { return nil }
            let title = cleaned(action.title, maximumLength: 90)
            guard !title.isEmpty else { return nil }
            let detail = action.detail.map { cleaned($0, maximumLength: 180) } ?? ""
            let time = min(action.time, maximumEvidenceTime)

            switch action.kind.lowercased() {
            case "click":
                guard let point = proposedScreenPoint(for: action, frames: frames) else { return nil }
                return WorkflowStep(
                    kind: .click,
                    title: title,
                    detail: detail,
                    time: time,
                    x: Double(point.x),
                    y: Double(point.y),
                    application: application,
                    bundleIdentifier: application.flatMap(applicationBundleIdentifier),
                    origin: .visual
                )
            case "typetext", "type_text", "type":
                let proposedText = action.text ?? (detail.count <= 80 ? detail : nil)
                guard let proposedText,
                      let safeText = safeProposedText(proposedText) else { return nil }
                let point = proposedScreenPoint(for: action, frames: frames)
                return WorkflowStep(
                    kind: .typeText,
                    title: title,
                    detail: detail.isEmpty ? "Text can be changed for each run" : detail,
                    time: time,
                    x: point.map { Double($0.x) },
                    y: point.map { Double($0.y) },
                    text: safeText,
                    application: application,
                    bundleIdentifier: application.flatMap(applicationBundleIdentifier),
                    origin: .visual
                )
            case "keypress", "key_press", "key":
                guard let keyCode = allowedKeyCode(action.key) else { return nil }
                return WorkflowStep(
                    kind: .keyPress,
                    title: title,
                    detail: detail,
                    time: time,
                    keyCode: keyCode,
                    application: application,
                    bundleIdentifier: application.flatMap(applicationBundleIdentifier),
                    origin: .visual
                )
            default:
                return nil
            }
        }

        guard !proposedSteps.isEmpty else { return }
        proposedSteps.sort { $0.time < $1.time }
        if let application,
           !workflow.steps.contains(where: { $0.kind == .openApp }) {
            proposedSteps.insert(WorkflowStep(
                kind: .openApp,
                title: "Open \(application)",
                detail: "Bring \(application) to the front",
                time: max(0, (proposedSteps.first?.time ?? 0) - 0.2),
                application: application,
                bundleIdentifier: applicationBundleIdentifier(application),
                origin: .visual
            ), at: 0)
        }
        workflow.steps.append(contentsOf: proposedSteps)
    }

    private static func safeProposedText(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= 500 else { return nil }
        let disallowed = text.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }
        return disallowed ? nil : text
    }

    private static func proposedScreenPoint(
        for action: LearnedWorkflowResponse.ProposedAction,
        frames: [WorkflowEvidenceFrame]
    ) -> CGPoint? {
        guard let image = action.image,
              frames.indices.contains(image - 1),
              let imageX = action.x,
              let imageY = action.y,
              let width = frames[image - 1].imageWidth,
              let height = frames[image - 1].imageHeight,
              let captureFrame = frames[image - 1].captureFrame,
              width > 0, height > 0,
              imageX >= 0, imageX <= Double(width),
              imageY >= 0, imageY <= Double(height) else { return nil }
        return CGPoint(
            x: captureFrame.minX + imageX / Double(width) * captureFrame.width,
            y: captureFrame.minY + imageY / Double(height) * captureFrame.height
        )
    }

    private static func allowedKeyCode(_ key: String?) -> Int? {
        switch key?.lowercased() {
        case "tab": 48
        case "return", "enter": 36
        case "escape", "esc": 53
        case "delete", "backspace": 51
        default: nil
        }
    }

    private static func applicationBundleIdentifier(_ application: String) -> String? {
        switch application.lowercased() {
        case "google chrome", "chrome": "com.google.Chrome"
        case "safari": "com.apple.Safari"
        case "numbers": "com.apple.Numbers"
        case "microsoft excel", "excel": "com.microsoft.Excel"
        case "textedit": "com.apple.TextEdit"
        default: nil
        }
    }

    static func groundsGenericClicks(_ response: LearnedWorkflowResponse, in candidate: Workflow) -> Bool {
        let genericClickIDs = genericClickIDs(in: candidate)
        guard !genericClickIDs.isEmpty else { return true }

        let groundedIDs = Set(response.annotations.compactMap { annotation -> String? in
            guard (annotation.confidence ?? 0) >= 0.55,
                  !isGenericClickTitle(annotation.title) else { return nil }
            return annotation.stepID.lowercased()
        })
        return genericClickIDs.isSubset(of: groundedIDs)
    }

    static func needsClickConsensus(_ candidate: Workflow) -> Bool {
        !genericClickIDs(in: candidate).isEmpty
    }

    static func isGenericCapturedClick(_ step: WorkflowStep) -> Bool {
        step.kind == .click && isGenericClickTitle(step.title)
    }

    static func consensusResponse(
        from responses: [LearnedWorkflowResponse],
        candidate: Workflow
    ) -> LearnedWorkflowResponse? {
        guard responses.count >= 2 else { return nil }
        for rightIndex in stride(from: responses.count - 1, through: 1, by: -1) {
            for leftIndex in stride(from: rightIndex - 1, through: 0, by: -1) {
                if clickAnnotationsAgree(responses[leftIndex], responses[rightIndex], candidate: candidate) {
                    return responses[rightIndex]
                }
            }
        }
        return nil
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

    private static func genericClickIDs(in candidate: Workflow) -> Set<String> {
        Set(candidate.steps.compactMap { step -> String? in
            guard isGenericCapturedClick(step) else { return nil }
            return step.id.uuidString.lowercased()
        })
    }

    private static func clickAnnotationsAgree(
        _ lhs: LearnedWorkflowResponse,
        _ rhs: LearnedWorkflowResponse,
        candidate: Workflow
    ) -> Bool {
        let requiredIDs = genericClickIDs(in: candidate)
        guard !requiredIDs.isEmpty else { return true }
        let left = concreteClickLabels(lhs, requiredIDs: requiredIDs)
        let right = concreteClickLabels(rhs, requiredIDs: requiredIDs)
        return requiredIDs.allSatisfy { id in
            guard let leftTitle = left[id], let rightTitle = right[id] else { return false }
            return titlesAgree(leftTitle, rightTitle)
        }
    }

    private static func concreteClickLabels(
        _ response: LearnedWorkflowResponse,
        requiredIDs: Set<String>
    ) -> [String: String] {
        response.annotations.reduce(into: [:]) { result, annotation in
            let id = annotation.stepID.lowercased()
            guard requiredIDs.contains(id),
                  (annotation.confidence ?? 0) >= 0.55,
                  !isGenericClickTitle(annotation.title) else { return }
            result[id] = annotation.title
        }
    }

    private static func titlesAgree(_ lhs: String, _ rhs: String) -> Bool {
        let ignored = Set(["click", "press", "choose", "select", "button", "field", "selector", "the", "a", "an"])
        func terms(_ value: String) -> Set<String> {
            Set(value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
                .subtracting(ignored)
        }
        let left = terms(lhs)
        let right = terms(rhs)
        return !left.isEmpty && !right.isEmpty && !left.isDisjoint(with: right)
    }

    private static func clock(_ time: TimeInterval) -> String {
        String(format: "%.2f seconds", time)
    }
}
