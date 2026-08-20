import Foundation

struct AutomationTemplateStep: Codable, Equatable, Sendable {
    var kind: WorkflowStepKind
    var isFlexibleInput: Bool
    var requiresApproval: Bool

    nonisolated var label: String {
        switch kind {
        case .openApp: "Open an app"
        case .openURL: "Open a web page"
        case .click: requiresApproval ? "Choose a control after approval" : "Choose a control"
        case .typeText: isFlexibleInput ? "Enter a value that can change" : "Enter a fixed value"
        case .keyPress: "Use a keyboard shortcut"
        case .selectSpreadsheetCell: "Choose a spreadsheet cell"
        case .decision: "Apply a judgment rule"
        case .approval: "Pause for approval"
        case .wait: "Wait for the next screen"
        }
    }

    nonisolated var icon: String {
        switch kind {
        case .openApp: "macwindow"
        case .openURL: "globe"
        case .click: "cursorarrow.click"
        case .typeText: "text.cursor"
        case .keyPress: "keyboard"
        case .selectSpreadsheetCell: "tablecells"
        case .decision: "sparkles"
        case .approval: "hand.raised.fill"
        case .wait: "hourglass"
        }
    }
}

struct AutomationTemplate: Codable, Equatable, Sendable {
    static let fileFormat = "neloa-template"
    static let formatVersion = 1
    static let maximumFileSize = 256 * 1_024
    static let maximumStepCount = 80

    var format = Self.fileFormat
    var schemaVersion = Self.formatVersion
    var title: String
    var steps: [AutomationTemplateStep]

    nonisolated var flexibleInputCount: Int {
        steps.filter(\.isFlexibleInput).count
    }

    nonisolated var approvalCount: Int {
        steps.filter(\.requiresApproval).count
    }

    nonisolated func jsonData() throws -> Data {
        try AutomationTemplateCodec.encode(self)
    }

    nonisolated func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}

enum AutomationTemplateError: Error, LocalizedError, Equatable {
    case tooLarge
    case invalidJSON
    case unsupportedFormat
    case unsupportedVersion
    case unexpectedFields(String)
    case invalidTitle
    case invalidStepCount
    case noDemonstrableActions
    case invalidStep(Int)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            "This template is larger than Neloa’s safe import limit."
        case .invalidJSON:
            "This file is not a valid Neloa template."
        case .unsupportedFormat:
            "This file is not a Neloa reusable template."
        case .unsupportedVersion:
            "This template was created by an unsupported Neloa version."
        case .unexpectedFields(let scope):
            "This template contains unexpected fields in \(scope). Neloa did not import it."
        case .invalidTitle:
            "Use a public title between 1 and 80 visible characters without line breaks or hidden formatting."
        case .invalidStepCount:
            "A reusable template must contain between 1 and \(AutomationTemplate.maximumStepCount) guide steps."
        case .noDemonstrableActions:
            "This template does not contain a task that can be demonstrated."
        case .invalidStep(let number):
            "Guide step \(number) has an invalid template configuration."
        }
    }
}

enum AutomationTemplateCodec {
    private static let topLevelKeys: Set<String> = ["format", "schemaVersion", "title", "steps"]
    private static let stepKeys: Set<String> = ["kind", "isFlexibleInput", "requiresApproval"]
    private static let demonstrableKinds: Set<WorkflowStepKind> = [
        .openApp, .openURL, .click, .typeText, .keyPress, .selectSpreadsheetCell
    ]

    nonisolated static func make(workflow: Workflow, publicTitle: String) throws -> AutomationTemplate {
        let title = publicTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let template = AutomationTemplate(
            title: title,
            steps: workflow.steps.map { step in
                AutomationTemplateStep(
                    kind: step.kind,
                    isFlexibleInput: step.kind == .typeText && step.isRunVariable,
                    requiresApproval: step.kind == .approval || step.requiresApproval
                )
            }
        )
        try validate(template)
        return template
    }

    nonisolated static func encode(_ template: AutomationTemplate) throws -> Data {
        try validate(template)
        return try JSONEncoder.neloa.encode(template)
    }

    nonisolated static func read(from url: URL) throws -> AutomationTemplate {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else {
            throw AutomationTemplateError.invalidJSON
        }
        guard (values.fileSize ?? AutomationTemplate.maximumFileSize + 1) <= AutomationTemplate.maximumFileSize else {
            throw AutomationTemplateError.tooLarge
        }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    nonisolated static func decode(_ data: Data) throws -> AutomationTemplate {
        guard data.count <= AutomationTemplate.maximumFileSize else {
            throw AutomationTemplateError.tooLarge
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AutomationTemplateError.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw AutomationTemplateError.invalidJSON
        }
        guard Set(root.keys) == topLevelKeys else {
            throw AutomationTemplateError.unexpectedFields("the file")
        }
        guard let stepObjects = root["steps"] as? [[String: Any]] else {
            throw AutomationTemplateError.invalidJSON
        }
        for (offset, step) in stepObjects.enumerated() where Set(step.keys) != stepKeys {
            throw AutomationTemplateError.unexpectedFields("guide step \(offset + 1)")
        }
        let template: AutomationTemplate
        do {
            template = try JSONDecoder.neloa.decode(AutomationTemplate.self, from: data)
        } catch {
            throw AutomationTemplateError.invalidJSON
        }
        try validate(template)
        return template
    }

    nonisolated static func sanitizedSlug(_ title: String) -> String {
        let value = title.lowercased().map { character -> Character in
            character.isLetter || character.isNumber ? character : "-"
        }
        let pieces = String(value).split(separator: "-").filter { !$0.isEmpty }
        let slug = pieces.prefix(8).joined(separator: "-")
        return slug.isEmpty ? "neloa-template" : slug
    }

    nonisolated static func validate(_ template: AutomationTemplate) throws {
        guard template.format == AutomationTemplate.fileFormat else {
            throw AutomationTemplateError.unsupportedFormat
        }
        guard template.schemaVersion == AutomationTemplate.formatVersion else {
            throw AutomationTemplateError.unsupportedVersion
        }
        guard isValidTitle(template.title) else {
            throw AutomationTemplateError.invalidTitle
        }
        guard (1...AutomationTemplate.maximumStepCount).contains(template.steps.count) else {
            throw AutomationTemplateError.invalidStepCount
        }
        guard template.steps.contains(where: { demonstrableKinds.contains($0.kind) }) else {
            throw AutomationTemplateError.noDemonstrableActions
        }
        for (offset, step) in template.steps.enumerated() {
            if step.isFlexibleInput && step.kind != .typeText {
                throw AutomationTemplateError.invalidStep(offset + 1)
            }
            if step.kind == .approval && !step.requiresApproval {
                throw AutomationTemplateError.invalidStep(offset + 1)
            }
        }
    }

    private nonisolated static func isValidTitle(_ title: String) -> Bool {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean == title, (1...80).contains(title.count) else { return false }
        return title.unicodeScalars.allSatisfy { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .privateUse, .unassigned:
                false
            default:
                true
            }
        }
    }
}
