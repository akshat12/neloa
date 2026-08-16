import CoreGraphics
import Foundation

/// Converts the recorder's literal input stream into the task vocabulary the
/// user used while teaching. The raw coordinates and key codes remain on the
/// steps for replay; the semantic title, target, and variable role are what the
/// review and one-off run planner expose.
enum WorkflowSemanticEnricher {
    static let currentVersion = 3

    static func enrich(_ source: Workflow) -> Workflow {
        var workflow = source
        let narration = workflow.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedNarration = narration.lowercased()

        stabilizeBrowserURLs(in: &workflow)
        if lowercasedNarration.contains("google drive") {
            replaceChromeNavigation(in: &workflow)
        }
        if lowercasedNarration.contains("spreadsheet") || lowercasedNarration.contains("sheet") {
            enrichSpreadsheetActions(in: &workflow, narration: narration)
        }

        workflow.semanticVersion = currentVersion
        return workflow
    }

    private static func stabilizeBrowserURLs(in workflow: inout Workflow) {
        var index = workflow.steps.startIndex
        while index < workflow.steps.endIndex {
            let shortcut = workflow.steps[index]
            guard isBrowserAddressShortcut(shortcut),
                  workflow.steps.indices.contains(index + 2),
                  workflow.steps[index + 1].kind == .typeText,
                  workflow.steps[index + 2].kind == .keyPress,
                  workflow.steps[index + 2].keyCode == 36,
                  let typed = workflow.steps[index + 1].text,
                  let address = normalizedWebAddress(typed) else {
                index += 1
                continue
            }

            var replacement = WorkflowStep(
                kind: .openURL,
                title: "Open \(URL(string: address)?.host() ?? address)",
                detail: "Go to \(address)",
                time: shortcut.time,
                text: address,
                application: shortcut.application,
                bundleIdentifier: shortcut.bundleIdentifier,
                displayID: shortcut.displayID
            )
            replacement.runVariable = false
            workflow.steps.replaceSubrange(index...(index + 2), with: [replacement])
            index += 1
        }
    }

    private static func isBrowserAddressShortcut(_ step: WorkflowStep) -> Bool {
        guard step.kind == .keyPress,
              let flags = step.flags,
              CGEventFlags(rawValue: flags).contains(.maskCommand) else { return false }
        return step.keyCode == 37 || step.keyCode == 17
    }

    private static func normalizedWebAddress(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }
        let candidate = trimmed.range(of: #"(?i)^https?://"#, options: .regularExpression) != nil
            ? trimmed
            : "https://\(trimmed)"
        guard let components = URLComponents(string: candidate),
              let host = components.host,
              host == "localhost" || host.contains(".") else { return nil }
        return components.url?.absoluteString
    }

    private static func replaceChromeNavigation(in workflow: inout Workflow) {
        guard !workflow.steps.contains(where: { $0.kind == .openURL }) else { return }
        guard let shortcutIndex = workflow.steps.firstIndex(where: isNewTabShortcut),
              let textIndex = workflow.steps.indices.dropFirst(shortcutIndex + 1).first(where: {
                  workflow.steps[$0].kind == .typeText
              }),
              textIndex - shortcutIndex <= 2,
              let returnIndex = workflow.steps.indices.dropFirst(textIndex + 1).first(where: {
                  workflow.steps[$0].kind == .keyPress && workflow.steps[$0].keyCode == 36
              }),
              returnIndex - textIndex <= 2 else { return }

        let shortcut = workflow.steps[shortcutIndex]
        var replacement = WorkflowStep(
            kind: .openURL,
            title: "Open Google Drive",
            detail: "Go to drive.google.com",
            time: shortcut.time,
            text: "https://drive.google.com",
            application: shortcut.application ?? "Google Chrome",
            bundleIdentifier: shortcut.bundleIdentifier ?? "com.google.Chrome",
            displayID: shortcut.displayID
        )
        replacement.runVariable = false

        var lowerBound = shortcutIndex
        if shortcutIndex > workflow.steps.startIndex {
            let previousIndex = workflow.steps.index(before: shortcutIndex)
            let previous = workflow.steps[previousIndex]
            if previous.kind == .click,
               previous.application == shortcut.application,
               shortcut.time - previous.time < 2.25 {
                // A click immediately before Command-T only focused Chrome; the
                // existing open-app step already does that during replay.
                lowerBound = previousIndex
            }
        }
        workflow.steps.replaceSubrange(lowerBound...returnIndex, with: [replacement])
    }

    private static func enrichSpreadsheetActions(in workflow: inout Workflow, narration: String) {
        let fileName = spreadsheetName(in: narration)
        let sheetName = namedSheet(in: narration)
        let cellReferences = spreadsheetCellReferences(in: narration)
        let utterances = NarrationTimeline.utterances(from: workflow.narrationSegments ?? [])

        let navigationIndex = workflow.steps.lastIndex(where: { $0.kind == .openURL })
            ?? workflow.steps.lastIndex(where: { $0.kind == .openApp })
            ?? workflow.steps.startIndex
        let clickIndices = workflow.steps.indices.filter {
            $0 > navigationIndex && workflow.steps[$0].kind == .click
        }

        let fileNarrationTime = utterances.first(where: {
            $0.text.localizedCaseInsensitiveContains("spreadsheet")
                && $0.text.localizedCaseInsensitiveContains("click")
        }).map { ($0.time + $0.endTime) / 2 }
        let fileClick = fileNarrationTime.flatMap { nearestIndex(to: $0, among: clickIndices, in: workflow) }
            ?? clickIndices.first
        if let fileClick, let fileName {
            workflow.steps[fileClick].title = "Open \(fileName)"
            workflow.steps[fileClick].detail = "Google Drive file"
            workflow.steps[fileClick].target = fileName
        }

        let sheetPattern = #"(?i)\b(?:creat(?:e|ed|ing)|add(?:ed|ing)?|mak(?:e|ing))\b.{0,32}\b(?:new\s+)?sheet\b"#
        let sheetNarrationTime = utterances.first(where: {
            $0.text.range(of: sheetPattern, options: .regularExpression) != nil
        }).map { ($0.time + $0.endTime) / 2 }
        let sheetCandidates = clickIndices.filter { $0 != fileClick }
        let sheetClick = sheetNarrationTime.flatMap { nearestIndex(to: $0, among: sheetCandidates, in: workflow) }
            ?? sheetCandidates.first
        if narration.range(of: sheetPattern, options: .regularExpression) != nil,
           let sheetClick {
            let capturedTarget = workflow.steps[sheetClick].target
            if let capturedTarget,
               capturedTarget.range(of: #"(?i)^sheet\s*[0-9]+$"#, options: .regularExpression) != nil {
                workflow.steps[sheetClick].title = "Open \(capturedTarget)"
                workflow.steps[sheetClick].detail = "Select the named spreadsheet tab"
            } else {
                let destination = sheetName ?? "the new sheet"
                workflow.steps[sheetClick].title = "Create \(destination)"
                workflow.steps[sheetClick].detail = "Add a new sheet to the spreadsheet"
                workflow.steps[sheetClick].target = "Add sheet"
            }
        }

        let allTextIndices = workflow.steps.indices.filter { workflow.steps[$0].kind == .typeText }
        guard !cellReferences.isEmpty, allTextIndices.count >= cellReferences.count else {
            markNonCellInputsAsFixed(in: &workflow, cellInputIndices: [])
            applySpreadsheetName(&workflow, fileName: fileName, sheetName: sheetName)
            return
        }

        let timedCells = utterances.flatMap { utterance in
            spreadsheetCellReferences(in: utterance.text).map {
                (cell: $0, time: (utterance.time + utterance.endTime) / 2)
            }
        }
        let assignments: [(index: Int, cell: String)]
        if !timedCells.isEmpty,
           timedCells.count == cellReferences.count,
           timedCells.count <= allTextIndices.count {
            assignments = timedCellAssignments(timedCells, inputIndices: allTextIndices, in: workflow)
        } else {
            assignments = Array(zip(allTextIndices.suffix(cellReferences.count), cellReferences)).map {
                (index: $0.0, cell: $0.1)
            }
        }
        let cellInputIndices = assignments.map(\.index)
        markNonCellInputsAsFixed(in: &workflow, cellInputIndices: Set(cellInputIndices))

        for (position, assignment) in assignments.enumerated() {
            let inputIndex = assignment.index
            let cell = assignment.cell
            let target = sheetName.map { "\($0)!\(cell)" } ?? cell
            let value = workflow.steps[inputIndex].text ?? "value"
            workflow.steps[inputIndex].title = "Set \(target) to \(short(value))"
            workflow.steps[inputIndex].detail = "Spreadsheet cell \(target) · Value can change each run"
            workflow.steps[inputIndex].target = target
            workflow.steps[inputIndex].runVariable = true

            if position + 1 < cellInputIndices.count {
                let nextInputIndex = assignments[position + 1].index
                if let movementIndex = workflow.steps.indices.dropFirst(inputIndex + 1).first(where: {
                    $0 < nextInputIndex && workflow.steps[$0].kind == .keyPress
                }) {
                    let destinationCell = assignments[position + 1].cell
                    let destination = sheetName.map { "\($0)!\(destinationCell)" } ?? destinationCell
                    workflow.steps[movementIndex].title = "Move to \(destination)"
                    workflow.steps[movementIndex].detail = keyDescription(workflow.steps[movementIndex].keyCode)
                    workflow.steps[movementIndex].target = destination
                }
            } else if let commitIndex = workflow.steps.indices.dropFirst(inputIndex + 1).first(where: {
                workflow.steps[$0].kind == .keyPress && workflow.steps[$0].keyCode == 36
            }) {
                workflow.steps[commitIndex].title = "Finish editing \(target)"
                workflow.steps[commitIndex].detail = "Press Return to commit the value"
                workflow.steps[commitIndex].target = target
            }
        }

        applySpreadsheetName(&workflow, fileName: fileName, sheetName: sheetName)
    }

    private static func timedCellAssignments(
        _ cells: [(cell: String, time: TimeInterval)],
        inputIndices: [Int],
        in workflow: Workflow
    ) -> [(index: Int, cell: String)] {
        var available = inputIndices
        var result: [(index: Int, cell: String)] = []
        for mention in cells {
            guard let match = available.min(by: {
                abs(workflow.steps[$0].time - mention.time) < abs(workflow.steps[$1].time - mention.time)
            }) else { break }
            result.append((match, mention.cell))
            available.removeAll { $0 == match }
        }
        return result.sorted { $0.index < $1.index }
    }

    private static func nearestIndex(
        to time: TimeInterval,
        among indices: [Int],
        in workflow: Workflow
    ) -> Int? {
        indices.min {
            abs(workflow.steps[$0].time - time) < abs(workflow.steps[$1].time - time)
        }
    }

    private static func markNonCellInputsAsFixed(
        in workflow: inout Workflow,
        cellInputIndices: Set<Int>
    ) {
        for index in workflow.steps.indices where workflow.steps[index].kind == .typeText {
            if !cellInputIndices.contains(index) {
                workflow.steps[index].runVariable = false
            }
        }
    }

    private static func applySpreadsheetName(
        _ workflow: inout Workflow,
        fileName: String?,
        sheetName: String?
    ) {
        if let fileName, let sheetName {
            workflow.name = "Fill \(sheetName) in \(fileName)"
        } else if let fileName {
            workflow.name = "Update \(fileName)"
        } else if !spreadsheetCellReferences(in: workflow.transcript).isEmpty {
            workflow.name = "Fill spreadsheet cells"
        }
    }

    private static func isNewTabShortcut(_ step: WorkflowStep) -> Bool {
        guard step.kind == .keyPress, step.keyCode == 17, let flags = step.flags else { return false }
        return CGEventFlags(rawValue: flags).contains(.maskCommand)
    }

    private static func spreadsheetName(in narration: String) -> String? {
        firstCapture(
            pattern: #"(?i)\bclick(?:ed)?\s+on\s+(?:this\s+|the\s+)?([^,.]+?\bspreadsheet)\b"#,
            in: narration
        ).map(titleCase)
    }

    private static func namedSheet(in narration: String) -> String? {
        guard let raw = firstCapture(
            pattern: #"(?i)\bsheet\s*([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten)\b"#,
            in: narration
        )?.lowercased() else { return nil }
        let words = [
            "one": "1", "two": "2", "three": "3", "four": "4", "five": "5",
            "six": "6", "seven": "7", "eight": "8", "nine": "9", "ten": "10"
        ]
        return "Sheet\(words[raw] ?? raw)"
    }

    private static func spreadsheetCellReferences(in narration: String) -> [String] {
        // Require the column and row to be contiguous. Allowing arbitrary
        // whitespace made ordinary speech such as "put 3" look like cell PUT3.
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\b([A-Z]{1,3}[0-9]+)\b"#) else {
            return []
        }
        let range = NSRange(narration.startIndex..., in: narration)
        var seen: Set<String> = []
        return regex.matches(in: narration, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: narration) else { return nil }
            let value = narration[capture].replacingOccurrences(of: " ", with: "").uppercased()
            return seen.insert(value).inserted ? value : nil
        }
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleCase(_ value: String) -> String {
        value.split(separator: " ").map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private static func keyDescription(_ keyCode: Int?) -> String {
        switch keyCode {
        case 123: "Left Arrow"
        case 124: "Right Arrow"
        case 125: "Down Arrow"
        case 126: "Up Arrow"
        case 48: "Tab"
        default: "Recorded navigation key"
        }
    }

    private static func short(_ value: String) -> String {
        value.count > 28 ? "\(value.prefix(28))…" : value
    }
}
