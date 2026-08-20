import Foundation

enum AutomationHealthLevel: String, Equatable, Sendable {
    case ready
    case caution
    case blocked
}

struct AutomationHealthSummary: Equatable, Sendable {
    var level: AutomationHealthLevel
    var title: String
    var detail: String
    var report: RunReadinessReport
}

enum AutomationHealth {
    typealias ApplicationAvailability = RunPreflight.ApplicationAvailability

    nonisolated static func evaluate(
        workflow: Workflow,
        accessibilityGranted: Bool,
        applicationAvailable: ApplicationAvailability = { _ in true }
    ) -> AutomationHealthSummary {
        summarize(RunPreflight.evaluate(
            plan: unchangedPlan(for: workflow),
            accessibilityGranted: accessibilityGranted,
            applicationAvailable: applicationAvailable
        ))
    }

    @MainActor
    static func live(workflow: Workflow, accessibilityGranted: Bool) -> AutomationHealthSummary {
        summarize(RunPreflight.live(
            plan: unchangedPlan(for: workflow),
            accessibilityGranted: accessibilityGranted
        ))
    }

    nonisolated static func summarize(_ report: RunReadinessReport) -> AutomationHealthSummary {
        if let first = report.blockingIssues.first {
            return AutomationHealthSummary(
                level: .blocked,
                title: "Needs attention",
                detail: first.title,
                report: report
            )
        }
        if let first = report.warnings.first {
            return AutomationHealthSummary(
                level: .caution,
                title: "Review recommended",
                detail: first.title,
                report: report
            )
        }
        return AutomationHealthSummary(
            level: .ready,
            title: "Ready",
            detail: "Permissions, apps, and saved actions are ready for review.",
            report: report
        )
    }

    private nonisolated static func unchangedPlan(for workflow: Workflow) -> RunPlan {
        RunPlan(
            instruction: "Run the saved automation",
            steps: workflow.steps,
            changes: [],
            summary: "Run the saved workflow without changes"
        )
    }
}
