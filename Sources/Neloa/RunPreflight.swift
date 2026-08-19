import AppKit
import Foundation

enum RunReadinessSeverity: String, Equatable, Sendable {
    case blocker
    case warning
}

enum RunReadinessIssueKind: String, Equatable, Sendable {
    case accessibility
    case missingApplication
    case invalidStep
    case coordinateFallback
    case focusDependency
}

struct RunReadinessIssue: Identifiable, Equatable, Sendable {
    var id: String
    var kind: RunReadinessIssueKind
    var severity: RunReadinessSeverity
    var title: String
    var detail: String
    var stepID: UUID?
}

struct RunReadinessReport: Equatable, Sendable {
    var applications: [String]
    var approvalCount: Int
    var issues: [RunReadinessIssue]

    var blockingIssues: [RunReadinessIssue] { issues.filter { $0.severity == .blocker } }
    var warnings: [RunReadinessIssue] { issues.filter { $0.severity == .warning } }
    var canRun: Bool { blockingIssues.isEmpty }

    var failureMessage: String {
        let details = blockingIssues.prefix(3).map(\.title).joined(separator: " ")
        return details.isEmpty ? "This automation is not ready to run." : "Before this can run: \(details)"
    }
}

enum RunPreflight {
    typealias ApplicationAvailability = (WorkflowStep) -> Bool

    static func evaluate(
        plan: RunPlan,
        accessibilityGranted: Bool,
        applicationAvailable: ApplicationAvailability = { _ in true }
    ) -> RunReadinessReport {
        var issues: [RunReadinessIssue] = []
        var checkedApplications: Set<String> = []
        var coordinateFallbackCount = 0
        var focusDependencyCount = 0

        if !accessibilityGranted {
            issues.append(RunReadinessIssue(
                id: "accessibility",
                kind: .accessibility,
                severity: .blocker,
                title: "Control permission is required.",
                detail: "Enable Neloa in System Settings → Privacy & Security → Accessibility before replay.",
                stepID: nil
            ))
        }

        if plan.steps.isEmpty {
            issues.append(RunReadinessIssue(
                id: "empty-workflow",
                kind: .invalidStep,
                severity: .blocker,
                title: "This automation has no actions.",
                detail: "Teach the workflow again so Neloa has reviewed actions to replay.",
                stepID: nil
            ))
        }

        for (index, step) in plan.steps.enumerated() {
            let number = index + 1
            if let applicationKey = applicationKey(for: step),
               checkedApplications.insert(applicationKey).inserted,
               !applicationAvailable(step) {
                let name = clean(step.application) ?? clean(step.bundleIdentifier) ?? "the captured application"
                issues.append(RunReadinessIssue(
                    id: "missing-app-\(applicationKey)",
                    kind: .missingApplication,
                    severity: .blocker,
                    title: "\(name) is not available.",
                    detail: "Install or restore \(name), then review this automation again.",
                    stepID: step.id
                ))
            }

            switch step.kind {
            case .openApp:
                if clean(step.application) == nil && clean(step.bundleIdentifier) == nil {
                    issues.append(invalidStep(number, step, "The app to open is missing."))
                }
            case .openURL:
                guard let rawURL = clean(step.text),
                      let url = URL(string: rawURL),
                      let scheme = url.scheme?.lowercased(),
                      ["https", "http"].contains(scheme) else {
                    issues.append(invalidStep(number, step, "The saved web address is invalid."))
                    continue
                }
            case .click:
                if clean(step.target) == nil {
                    if step.x == nil || step.y == nil {
                        issues.append(invalidStep(number, step, "The click has no control name or screen position."))
                    } else {
                        coordinateFallbackCount += 1
                    }
                }
            case .typeText:
                if clean(step.text) == nil {
                    issues.append(invalidStep(number, step, "The text to enter is missing."))
                } else if clean(step.target) == nil && (step.x == nil || step.y == nil) {
                    focusDependencyCount += 1
                }
            case .keyPress:
                if step.keyCode == nil {
                    issues.append(invalidStep(number, step, "The saved key is missing."))
                }
            case .selectSpreadsheetCell:
                if step.bundleIdentifier != "com.google.Chrome" {
                    issues.append(invalidStep(number, step, "Spreadsheet navigation requires the captured Google Chrome workflow."))
                }
                if !isSpreadsheetTarget(step.target) {
                    issues.append(invalidStep(number, step, "The spreadsheet cell address is invalid."))
                }
            case .decision, .approval, .wait:
                break
            }
        }

        if coordinateFallbackCount > 0 {
            issues.append(RunReadinessIssue(
                id: "coordinate-fallbacks",
                kind: .coordinateFallback,
                severity: .warning,
                title: "\(coordinateFallbackCount) click\(coordinateFallbackCount == 1 ? "" : "s") use saved screen positions.",
                detail: "Keep the same display arrangement and app layout. Review these steps after an interface redesign.",
                stepID: nil
            ))
        }

        if focusDependencyCount > 0 {
            issues.append(RunReadinessIssue(
                id: "focus-dependencies",
                kind: .focusDependency,
                severity: .warning,
                title: "\(focusDependencyCount) text step\(focusDependencyCount == 1 ? "" : "s") depend on the current field.",
                detail: "Neloa will type into whichever field the previous action focused.",
                stepID: nil
            ))
        }

        return RunReadinessReport(
            applications: Array(Set(plan.steps.compactMap(\.application).filter { !$0.isEmpty })).sorted(),
            approvalCount: plan.steps.filter { $0.kind == .approval || $0.requiresApproval }.count,
            issues: issues
        )
    }

    @MainActor
    static func live(plan: RunPlan, accessibilityGranted: Bool) -> RunReadinessReport {
        evaluate(plan: plan, accessibilityGranted: accessibilityGranted) { step in
            if let bundleIdentifier = clean(step.bundleIdentifier) {
                if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty {
                    return true
                }
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
            }
            guard let name = clean(step.application) else { return true }
            if NSWorkspace.shared.runningApplications.contains(where: {
                $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
            }) {
                return true
            }
            return false
        }
    }

    private static func invalidStep(_ number: Int, _ step: WorkflowStep, _ detail: String) -> RunReadinessIssue {
        RunReadinessIssue(
            id: "invalid-step-\(step.id.uuidString)-\(detail)",
            kind: .invalidStep,
            severity: .blocker,
            title: "Step \(number), “\(step.title),” is incomplete.",
            detail: detail,
            stepID: step.id
        )
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }

    private static func applicationKey(for step: WorkflowStep) -> String? {
        if let bundleIdentifier = clean(step.bundleIdentifier) {
            return "bundle-\(bundleIdentifier)"
        }
        if let application = clean(step.application) {
            return "name-\(application.lowercased())"
        }
        return nil
    }

    private static func isSpreadsheetTarget(_ target: String?) -> Bool {
        guard let value = clean(target)?.replacingOccurrences(of: " ", with: "") else { return false }
        return value.range(
            of: #"(?i)^(?:SHEET[0-9]+!)?[A-Z]{1,3}[1-9][0-9]{0,6}$"#,
            options: .regularExpression
        ) != nil
    }
}
