import Foundation

struct DiagnosticsAppSummary: Codable, Equatable, Sendable {
    var version: String
    var build: String
    var buildMode: String

    nonisolated static var current: DiagnosticsAppSummary {
        let info = Bundle.main.infoDictionary ?? [:]
        #if DEBUG
        let buildMode = "debug"
        #else
        let buildMode = "release"
        #endif
        return DiagnosticsAppSummary(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info["CFBundleVersion"] as? String ?? "unknown",
            buildMode: buildMode
        )
    }
}

struct DiagnosticsSystemSummary: Codable, Equatable, Sendable {
    var operatingSystem: String
    var architecture: String
    var memoryGB: Int

    nonisolated static var current: DiagnosticsSystemSummary {
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        let gibibyte = UInt64(1_024 * 1_024 * 1_024)
        let memory = ProcessInfo.processInfo.physicalMemory
        return DiagnosticsSystemSummary(
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architecture,
            memoryGB: Int((memory + gibibyte / 2) / gibibyte)
        )
    }
}

struct DiagnosticsPermissionSummary: Codable, Equatable, Sendable {
    var screenRecording: String
    var clicksAndTyping: String
    var microphone: String
    var speechRecognition: String
    var screenRestartNeeded: Bool

    @MainActor
    static func current(_ permissions: PermissionCenter) -> DiagnosticsPermissionSummary {
        DiagnosticsPermissionSummary(
            screenRecording: permissions.screen.diagnosticsCode,
            clicksAndTyping: permissions.accessibility.diagnosticsCode,
            microphone: permissions.microphone.diagnosticsCode,
            speechRecognition: permissions.speech.diagnosticsCode,
            screenRestartNeeded: permissions.screenRestartNeeded
        )
    }
}

struct DiagnosticsModelSummary: Codable, Equatable, Sendable {
    var family: String
    var tier: String
    var precision: String
    var revision: String
    var status: String
    var runtimeBundled: Bool
    var installed: Bool
    var eligible: Bool

    @MainActor
    static func current(_ agent: LocalAgentService) -> DiagnosticsModelSummary {
        sanitized(
            tier: agent.selectedTier,
            status: agent.modelStatus,
            runtimeBundled: LocalAgentService.isQwenRuntimeBundled,
            installed: LocalModelPaths.isInstalled(agent.selectedTier),
            eligible: agent.hardware.eligibilityIssue(for: agent.selectedTier) == nil
        )
    }

    nonisolated static func sanitized(
        tier: LocalModelTier,
        status: LocalModelStatus,
        runtimeBundled: Bool,
        installed: Bool,
        eligible: Bool
    ) -> DiagnosticsModelSummary {
        DiagnosticsModelSummary(
            family: LocalModelPaths.displayName,
            tier: tier.rawValue,
            precision: tier.precisionLabel,
            revision: tier.modelRevision,
            status: status.diagnosticsCode,
            runtimeBundled: runtimeBundled,
            installed: installed,
            eligible: eligible
        )
    }
}

struct DiagnosticsStorageSummary: Codable, Equatable, Sendable {
    var automationCount: Int
    var activityCount: Int
    var storeIssuePresent: Bool
}

struct DiagnosticsActivitySummary: Codable, Equatable, Sendable {
    var total: Int
    var completed: Int
    var stopped: Int
    var failed: Int
}

struct DiagnosticsReadinessSummary: Codable, Equatable, Sendable {
    var blockerCount: Int
    var warningCount: Int
    var issueKinds: [String: Int]
}

struct DiagnosticsWorkflowSummary: Codable, Equatable, Sendable {
    var number: Int
    var semanticVersion: Int?
    var stepCount: Int
    var stepKinds: [String: Int]
    var flexibleInputCount: Int
    var approvalCount: Int
    var userInstructionCount: Int
    var semanticTargetCount: Int
    var positionOnlyClickCount: Int
    var focusDependentInputCount: Int
    var repairedStepCount: Int
    var visualDraftStepCount: Int
    var hasScreenRecording: Bool
    var hasNarrationRecording: Bool
    var hasTranscript: Bool
    var narrationSegmentCount: Int
    var reminderEnabled: Bool
    var watchedFolderEnabled: Bool
    var watchedFileType: String?
    var readiness: DiagnosticsReadinessSummary
}

struct DiagnosticsPrivacySummary: Codable, Equatable, Sendable {
    var includes: [String]
    var excludes: [String]

    nonisolated static let standard = DiagnosticsPrivacySummary(
        includes: [
            "App, macOS, architecture, and memory versions",
            "Permission and local-model state",
            "Automation action-type and readiness counts",
            "Aggregate run outcomes"
        ],
        excludes: [
            "Screen or audio recordings and OCR",
            "Workflow names, transcripts, and spoken instructions",
            "Typed values, web addresses, file and folder paths",
            "Control labels, click positions, and display identifiers",
            "Application names and bundle identifiers",
            "Automation, action, and run identifiers",
            "Failure messages and storage paths"
        ]
    )
}

struct DiagnosticsReport: Codable, Equatable, Sendable, Identifiable {
    var id: Date { generatedAt }

    var schemaVersion: Int
    var generatedAt: Date
    var app: DiagnosticsAppSummary
    var system: DiagnosticsSystemSummary
    var permissions: DiagnosticsPermissionSummary
    var model: DiagnosticsModelSummary
    var storage: DiagnosticsStorageSummary
    var activity: DiagnosticsActivitySummary
    var workflows: [DiagnosticsWorkflowSummary]
    var privacy: DiagnosticsPrivacySummary

    nonisolated func jsonData() throws -> Data {
        try JSONEncoder.neloa.encode(self)
    }

    nonisolated func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}

enum DiagnosticsReportBuilder {
    typealias ReadinessProvider = (Workflow) -> RunReadinessReport

    @MainActor
    static func makeLive(
        store: WorkflowStore,
        permissions: PermissionCenter,
        agent: LocalAgentService,
        generatedAt: Date = Date()
    ) -> DiagnosticsReport {
        let accessibilityGranted = permissions.accessibility == .granted
        return make(
            workflows: store.workflows,
            activities: store.activities,
            storeIssuePresent: store.issue != nil,
            permissions: .current(permissions),
            model: .current(agent),
            generatedAt: generatedAt,
            readiness: { workflow in
                RunPreflight.live(
                    plan: RunPlan(
                        instruction: "",
                        steps: workflow.steps,
                        changes: [],
                        summary: ""
                    ),
                    accessibilityGranted: accessibilityGranted
                )
            }
        )
    }

    nonisolated static func make(
        workflows: [Workflow],
        activities: [AutomationRunReceipt],
        storeIssuePresent: Bool,
        permissions: DiagnosticsPermissionSummary,
        model: DiagnosticsModelSummary,
        generatedAt: Date,
        app: DiagnosticsAppSummary = .current,
        system: DiagnosticsSystemSummary = .current,
        readiness: ReadinessProvider
    ) -> DiagnosticsReport {
        let workflowSummaries = workflows.enumerated().map { offset, workflow in
            workflowSummary(
                number: offset + 1,
                workflow: workflow,
                readiness: readiness(workflow)
            )
        }
        return DiagnosticsReport(
            schemaVersion: 1,
            generatedAt: generatedAt,
            app: app,
            system: system,
            permissions: permissions,
            model: model,
            storage: DiagnosticsStorageSummary(
                automationCount: workflows.count,
                activityCount: activities.count,
                storeIssuePresent: storeIssuePresent
            ),
            activity: activitySummary(activities),
            workflows: workflowSummaries,
            privacy: .standard
        )
    }

    private nonisolated static func workflowSummary(
        number: Int,
        workflow: Workflow,
        readiness: RunReadinessReport
    ) -> DiagnosticsWorkflowSummary {
        DiagnosticsWorkflowSummary(
            number: number,
            semanticVersion: workflow.semanticVersion,
            stepCount: workflow.steps.count,
            stepKinds: counts(workflow.steps.map { $0.kind.rawValue }),
            flexibleInputCount: workflow.steps.filter(\.isRunVariable).count,
            approvalCount: workflow.steps.filter { $0.kind == .approval || $0.requiresApproval }.count,
            userInstructionCount: workflow.steps.filter(\.isUserInstruction).count,
            semanticTargetCount: workflow.steps.filter { clean($0.target) != nil }.count,
            positionOnlyClickCount: workflow.steps.filter {
                $0.kind == .click && clean($0.target) == nil && $0.x != nil && $0.y != nil
            }.count,
            focusDependentInputCount: workflow.steps.filter {
                $0.kind == .typeText && clean($0.target) == nil && ($0.x == nil || $0.y == nil)
            }.count,
            repairedStepCount: workflow.steps.filter { $0.origin == .repaired }.count,
            visualDraftStepCount: workflow.steps.filter { $0.origin == .visual }.count,
            hasScreenRecording: clean(workflow.recordingPath) != nil,
            hasNarrationRecording: clean(workflow.narrationPath) != nil,
            hasTranscript: !workflow.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            narrationSegmentCount: workflow.narrationSegments?.count ?? 0,
            reminderEnabled: workflow.schedule?.isEnabled == true,
            watchedFolderEnabled: workflow.fileTrigger?.isEnabled == true,
            watchedFileType: workflow.fileTrigger?.isEnabled == true ? workflow.fileTrigger?.kind.rawValue : nil,
            readiness: DiagnosticsReadinessSummary(
                blockerCount: readiness.blockingIssues.count,
                warningCount: readiness.warnings.count,
                issueKinds: counts(readiness.issues.map { $0.kind.rawValue })
            )
        )
    }

    private nonisolated static func activitySummary(
        _ activities: [AutomationRunReceipt]
    ) -> DiagnosticsActivitySummary {
        DiagnosticsActivitySummary(
            total: activities.count,
            completed: activities.filter { $0.status == .completed }.count,
            stopped: activities.filter { $0.status == .stopped }.count,
            failed: activities.filter { $0.status == .failed }.count
        )
    }

    private nonisolated static func counts(_ values: [String]) -> [String: Int] {
        Dictionary(grouping: values, by: { $0 }).mapValues(\.count)
    }

    private nonisolated static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}

private extension PermissionCenter.Status {
    nonisolated var diagnosticsCode: String {
        switch self {
        case .unknown: "unknown"
        case .granted: "granted"
        case .denied: "denied"
        }
    }
}

private extension LocalModelStatus {
    nonisolated var diagnosticsCode: String {
        switch self {
        case .checking: "checking"
        case .unavailable: "unavailable"
        case .notInstalled: "notInstalled"
        case .downloading: "downloading"
        case .loading: "loading"
        case .removing: "removing"
        case .ready: "ready"
        case .failed: "failed"
        }
    }
}
