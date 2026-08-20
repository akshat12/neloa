import AppKit
import Foundation
import ScreenCaptureKit

enum SelfTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        try compilationCheck()
        try supportedUseCaseScenarioCheck()
        try googleDriveSpreadsheetSemanticCompilationCheck()
        try timedNarrationCorrelationCheck()
        try spokenOnlyCheck()
        try replacementCheck()
        try amountCheck()
        try spreadsheetCellRetargetingCheck()
        try serializationCheck()
        try receiptSerializationCheck()
        try skillExportCheck()
        try brandMigrationCheck()
        try localModelEligibilityCheck()
        try localModelCacheValidationCheck()
        try workflowLearningCheck()
        try permissionStateCheck()
        try appearanceCheck()
        try recordingErrorCopyCheck()
        try displaySelectionCheck()
        try clickTargetMetadataCheck()
        try captureOptionCheck()
        try teachingTargetCheck()
        try screenPermissionBranchCheck()
        try appTourStructureCheck()
        try reviewFixtureLaunchCheck()
        try reviewDraftLifetimeCheck()
        try reviewFixtureIsolationCheck()
        try runPresentationCheck()
        try runPreflightCheck()
        try stepRepairCheck()
        try automationScheduleCheck()
        try deepLinkCheck()
        try automationRunQueueCheck()
        try fileTriggerCheck()
        try diagnosticsPrivacyCheck()
        try automationTemplateCheck()
        try reviewTimelineSelectionCheck()
        try workflowInstructionCheck()
        try agentResponseSafetyCheck()
        try staleEvidenceCleanupCheck()
        try denseEvidenceSamplingCheck()
        try recoveryEvidenceRoutingCheck()
        try evidenceCoordinateMappingCheck()
        try qwenResponseRepairCheck()
        try modelEvaluationScoringCheck()
        try modelEvaluationComparisonCheck()
    }

    private static func modelEvaluationScoringCheck() throws {
        let softFailure = ModelEvaluationAssertion(
            name: "wording quality",
            passed: false,
            critical: false,
            weight: 1,
            expected: "specific wording",
            actual: "generic wording"
        )
        let structuralPass = ModelEvaluationAssertion(
            name: "preserve replay graph",
            passed: true,
            critical: true,
            weight: 4,
            expected: "unchanged",
            actual: "unchanged"
        )
        let acceptable = ModelEvaluationCase(
            id: "scoring-fixture",
            category: "self-test",
            durationSeconds: 0,
            assertions: [softFailure, structuralPass]
        )
        try expect(acceptable.passed && acceptable.score == 0.8, "a noncritical wording miss may pass at the case threshold")

        let criticalFailure = ModelEvaluationAssertion(
            name: "unsafe action",
            passed: false,
            critical: true,
            weight: 1,
            expected: "none",
            actual: "send"
        )
        let rejected = ModelEvaluationCase(
            id: "critical-fixture",
            category: "self-test",
            durationSeconds: 0,
            assertions: [criticalFailure, structuralPass]
        )
        try expect(!rejected.passed, "a critical model regression must fail regardless of aggregate score")

        let report = ModelEvaluationReport(
            generatedAt: Date(timeIntervalSince1970: 0),
            gitCommit: "fixture",
            modelID: "fixture/model",
            modelRevision: "fixture-revision",
            precision: "4-bit",
            operatingSystem: "fixture macOS",
            physicalMemoryBytes: 16,
            minimumScore: 0.9,
            durationSeconds: 1,
            cases: [acceptable]
        )
        let encoded = try JSONEncoder().encode(report)
        let object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        let encodedCases = object?["cases"] as? [[String: Any]]
        try expect(object?["score"] != nil && object?["passed"] != nil, "machine-readable model reports should include aggregate outcome fields")
        try expect(encodedCases?.first?["score"] != nil && encodedCases?.first?["passed"] != nil, "machine-readable model reports should include per-case outcome fields")
    }

    private static func modelEvaluationComparisonCheck() throws {
        let structuralPass = ModelEvaluationAssertion(
            name: "preserve replay graph",
            passed: true,
            critical: true,
            weight: 4,
            expected: "unchanged",
            actual: "unchanged"
        )
        let groundingPass = ModelEvaluationAssertion(
            name: "ground the target",
            passed: true,
            critical: false,
            weight: 1,
            expected: "semantic target",
            actual: "semantic target"
        )
        let groundingFailure = ModelEvaluationAssertion(
            name: "ground the target",
            passed: false,
            critical: false,
            weight: 1,
            expected: "semantic target",
            actual: "coordinate only"
        )

        func report(
            commit: String,
            model: String = "fixture/model",
            precision: String = "4-bit",
            duration: Double,
            assertions: [ModelEvaluationAssertion],
            caseID: String = "comparison-fixture"
        ) -> ModelEvaluationReport {
            ModelEvaluationReport(
                generatedAt: Date(timeIntervalSince1970: duration),
                gitCommit: commit,
                modelID: model,
                modelRevision: "fixture-revision",
                precision: precision,
                operatingSystem: "fixture macOS",
                physicalMemoryBytes: 16,
                minimumScore: 0.80,
                durationSeconds: duration,
                cases: [ModelEvaluationCase(
                    id: caseID,
                    category: "self-test",
                    durationSeconds: duration,
                    assertions: assertions
                )]
            )
        }

        let baseline = report(
            commit: "baseline",
            duration: 10,
            assertions: [structuralPass, groundingPass]
        )
        let otherTier = report(
            commit: "candidate",
            model: "fixture/other-quantization",
            precision: "8-bit",
            duration: 12,
            assertions: [structuralPass, groundingPass]
        )
        let tierComparison = ModelEvaluationComparison.compare(
            baseline: baseline,
            candidate: otherTier,
            generatedAt: Date(timeIntervalSince1970: 100)
        )
        try expect(tierComparison.compatible, "different commits and quantization tiers should remain comparable when the evaluation contract is identical")
        try expect(tierComparison.passed && tierComparison.regressions.isEmpty, "an equally accurate candidate tier should pass comparison")
        try expect(tierComparison.durationDeltaSeconds == 2, "comparison should report runtime changes without treating them as quality failures")

        let regressed = report(
            commit: "regressed",
            duration: 9,
            assertions: [structuralPass, groundingFailure]
        )
        let regression = ModelEvaluationComparison.compare(
            baseline: baseline,
            candidate: regressed,
            generatedAt: Date(timeIntervalSince1970: 101)
        )
        try expect(regression.compatible && !regression.passed, "a comparable candidate with a newly failing assertion should fail")
        try expect(
            regression.regressions.contains { $0.kind == .assertionRegressed && $0.assertionName == "ground the target" },
            "comparison should identify the exact newly failing assertion"
        )
        try expect(
            regression.regressions.contains { $0.kind == .overallScoreDropped },
            "comparison should report an aggregate score drop"
        )

        let previouslySoftFailure = report(
            commit: "soft-failure",
            duration: 14,
            assertions: [structuralPass, groundingFailure]
        )
        let improved = ModelEvaluationComparison.compare(
            baseline: previouslySoftFailure,
            candidate: baseline,
            generatedAt: Date(timeIntervalSince1970: 102)
        )
        try expect(improved.passed, "resolving a noncritical miss without adding regressions should pass")
        try expect(
            improved.cases.first?.improvedAssertions == ["ground the target"],
            "comparison should preserve the exact resolved assertion"
        )

        var changedExpected = groundingPass
        changedExpected.expected = "different contract"
        let changedDefinition = report(
            commit: "changed-definition",
            duration: 10,
            assertions: [structuralPass, changedExpected]
        )
        let incompatible = ModelEvaluationComparison.compare(
            baseline: baseline,
            candidate: changedDefinition,
            generatedAt: Date(timeIntervalSince1970: 103)
        )
        try expect(!incompatible.compatible && !incompatible.passed, "changed assertion definitions must not produce a misleading historical comparison")
        try expect(
            incompatible.regressions.contains { $0.kind == .incompatibleReports },
            "incompatible reports should explain that both runs need the same evaluation contract"
        )

        var tampered = baseline
        tampered.score = 0.99
        let inconsistent = ModelEvaluationComparison.compare(
            baseline: baseline,
            candidate: tampered,
            generatedAt: Date(timeIntervalSince1970: 104)
        )
        try expect(
            !inconsistent.compatible && !inconsistent.passed,
            "comparison must reject reports whose stored totals disagree with their assertions"
        )

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("Neloa-model-comparison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let baselineURL = temporary.appendingPathComponent("baseline.json")
        let candidateURL = temporary.appendingPathComponent("candidate.json")
        let comparisonURL = temporary.appendingPathComponent("comparison.json")
        try JSONEncoder.neloa.encode(baseline).write(to: baselineURL, options: .atomic)
        try JSONEncoder.neloa.encode(otherTier).write(to: candidateURL, options: .atomic)
        let written = try ModelEvaluationComparison.run(environment: [
            "NELOA_MODEL_EVAL_BASELINE": baselineURL.path,
            "NELOA_MODEL_EVAL_CANDIDATE": candidateURL.path,
            "NELOA_MODEL_EVAL_COMPARISON_REPORT": comparisonURL.path
        ])
        try expect(written.report.passed, "the file-based comparison command should preserve a passing comparison")
        try expect(FileManager.default.fileExists(atPath: comparisonURL.path), "comparison should write machine-readable JSON")
        try expect(
            FileManager.default.fileExists(atPath: comparisonURL.deletingPathExtension().appendingPathExtension("md").path),
            "comparison should write a human-readable Markdown report"
        )
        let decoded = try JSONDecoder.neloa.decode(
            ModelEvaluationComparisonReport.self,
            from: Data(contentsOf: comparisonURL)
        )
        try expect(decoded == written.report, "the comparison report should round-trip through its public JSON format")
        try expect(
            ModelEvaluationComparison.markdown(regression).contains("ground the target"),
            "the Markdown report should identify assertion regressions"
        )
    }

    private static func appearanceCheck() throws {
        try expect(AppAppearance.resolve("system") == .system, "system appearance should round-trip")
        try expect(AppAppearance.resolve("light") == .light, "light appearance should round-trip")
        try expect(AppAppearance.resolve("dark") == .dark, "dark appearance should round-trip")
        try expect(AppAppearance.resolve("unexpected") == .system, "unknown appearance should safely follow the system")
        try expect(AppAppearance.system.colorScheme(system: .light) == .light, "system appearance should follow light macOS")
        try expect(AppAppearance.system.colorScheme(system: .dark) == .dark, "system appearance should follow dark macOS")
        try expect(AppAppearance.light.colorScheme(system: .dark) == .light, "light appearance should override dark macOS")
        try expect(AppAppearance.dark.colorScheme(system: .light) == .dark, "dark appearance should override light macOS")
    }

    @MainActor
    static func agentSmokeTest() async throws {
        let reviewMovie = "/System/Library/CoreServices/ControlCenter.app/Contents/Resources/BentoGalleryIntroduction.mov"
        let reviewPlayback = ReviewPlaybackModel(recordingPath: reviewMovie)
        for _ in 0..<100 where reviewPlayback.duration <= 0 {
            try? await Task.sleep(for: .milliseconds(20))
        }
        try expect(
            reviewPlayback.duration > 1,
            "review should load the recording duration before playback starts; got \(reviewPlayback.duration)"
        )

        let input = WorkflowStep(kind: .typeText, title: "Type June", time: 0, text: "June")
        let workflow = Workflow(name: "Monthly report", transcript: "", steps: [input])
        let agent = LocalAgentService()
        let plan = await agent.makePlan(workflow: workflow, instruction: "Replace June with August")
        try expect(agent.status.contains("Apple on-device"), "Apple on-device fallback should handle the test plan; status was: \(agent.status)")
        try expect(plan.steps.first?.text == "August", "on-device agent should replace June with August; got text=\(plan.steps.first?.text ?? "nil"), summary=\(plan.summary), changes=\(plan.changes.map { "\($0.before)->\($0.after)" })")
        try expect(plan.changes.count == 1, "on-device agent should report one reviewed change; got \(plan.changes.count)")

        let teacher = TeachController()
        teacher.setScreenCaptureEnabled(false)
        try expect(!teacher.captureScreen && !teacher.captureSystemAudio, "turning off screen capture should also turn off computer audio")

        let completedStep = WorkflowStep(kind: .decision, title: "Prepare values", time: 0)
        let failedStep = WorkflowStep(kind: .decision, title: "Fail safely", time: 1)
        let failureRunner = AutomationRunner(countdownSeconds: 0) { step in
            if step.id == failedStep.id {
                throw Failure(description: "Simulated replay failure")
            }
        }
        failureRunner.run(RunPlan(
            instruction: "Test recovery",
            steps: [completedStep, failedStep],
            changes: [],
            summary: "Test recovery"
        ))
        for _ in 0..<60 {
            if case .failed = failureRunner.state { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard case .failed = failureRunner.state else {
            throw Failure(description: "the simulated replay should reach the failed state")
        }
        try expect(
            failureRunner.completedStepIDs == [completedStep.id],
            "failed-run recovery should identify exactly which actions already completed"
        )
        failureRunner.reset(preservingCompletedSteps: true)
        try expect(
            failureRunner.completedStepIDs == [completedStep.id],
            "reviewing a restart should preserve the completed-work warning"
        )

        var invalidStepExecuted = false
        let invalidRunner = AutomationRunner(countdownSeconds: 0) { _ in
            invalidStepExecuted = true
        }
        let invalidReplayStep = WorkflowStep(kind: .click, title: "Missing replay target", time: 0)
        invalidRunner.run(RunPlan(
            instruction: "Run",
            steps: [invalidReplayStep],
            changes: [],
            summary: "Invalid replay fixture"
        ))
        guard case .failed(let preflightMessage) = invalidRunner.state else {
            throw Failure(description: "an invalid replay should fail before execution")
        }
        try expect(!invalidStepExecuted, "preflight blockers must prevent the executor from receiving an invalid step")
        try expect(preflightMessage.contains("Step 1"), "the runner should explain which captured step needs repair")

        let failingStore = WorkflowStore(fileURL: URL(fileURLWithPath: "/dev/null/NeloaSelfTests/workflows.json"))
        failingStore.save(workflow)
        try expect(
            failingStore.issue?.canRetry == true,
            "storage failures should become visible and offer recovery"
        )
        failingStore.dismissIssue()
    }

    @MainActor
    static func fileTriggerSmokeTest() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaFileTriggerSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let fileInput = WorkflowStep(
            kind: .typeText,
            title: "Choose source file",
            detail: "Upload document path",
            time: 1,
            text: "/tmp/old.pdf",
            target: "Source file"
        )
        let workflow = Workflow(
            name: "Import new PDF",
            transcript: "",
            steps: [fileInput],
            fileTrigger: AutomationFileTrigger(
                folderPath: folder.path,
                kind: .pdf,
                inputStepID: fileInput.id
            )
        )
        let router = AutomationRunRouter()
        let center = FileTriggerCenter(runRouter: router)
        center.reconcile(workflows: [workflow])
        try expect(center.watchingWorkflowIDs == [workflow.id], "the file-trigger smoke fixture should begin watching its selected folder")

        let ignored = folder.appendingPathComponent("ignore.csv")
        try Data("ignored".utf8).write(to: ignored)
        try? await Task.sleep(for: .seconds(2))
        try expect(router.currentRequest == nil, "a watched-folder trigger should ignore files outside its selected type")

        let arriving = folder.appendingPathComponent("August report.pdf")
        try Data("first chunk".utf8).write(to: arriving)
        try? await Task.sleep(for: .milliseconds(350))
        if let handle = try? FileHandle(forWritingTo: arriving) {
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(" second chunk".utf8))
            try handle.close()
        }

        for _ in 0..<80 where router.currentRequest == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let request = router.currentRequest else {
            throw Failure(description: "a settled matching file should prepare a reviewed run")
        }
        try expect(request.workflowID == workflow.id && request.source == .watchedFolder, "the folder event should route to the correct saved automation")
        try expect(request.initialInstruction == FileTriggerSupport.instruction(for: arriving), "the prepared run should carry the exact arrived file path")

        let plan = RunPlanner.plan(workflow: workflow, instruction: request.initialInstruction ?? "")
        try expect(plan.changes.count == 1 && plan.changes[0].after == arriving.path, "the event-level trigger should produce one reviewable file change")
        try expect(plan.steps.map(\.id) == workflow.steps.map(\.id), "the event-level trigger must not add replay actions")

        let agent = LocalAgentService()
        let servicePlan = await agent.makePlan(
            workflow: workflow,
            instruction: request.initialInstruction ?? ""
        )
        try expect(
            agent.status == "Planned with watched-folder safety checks",
            "an exact watched-folder event should not load Qwen or the Apple fallback"
        )
        try expect(
            servicePlan.steps == plan.steps
                && servicePlan.changes.map { ($0.stepID, $0.before, $0.after, $0.reason) }
                    .elementsEqual(
                        plan.changes.map { ($0.stepID, $0.before, $0.after, $0.reason) },
                        by: ==
                    )
                && servicePlan.summary == plan.summary,
            "the model service should preserve the deterministic watched-folder plan"
        )

        try Data("replacement file".utf8).write(to: arriving, options: .atomic)
        for _ in 0..<40 where router.queuedRequestCount == 0 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        try expect(
            router.queuedRequestCount == 1,
            "replacing a settled file under the same name should prepare one new reviewed run"
        )
        router.finishCurrent()
        try expect(
            router.currentRequest?.initialInstruction == FileTriggerSupport.instruction(for: arriving),
            "a replacement should preserve the same exact, reviewable path"
        )

        center.remove(workflowID: workflow.id)
        try expect(center.watchingWorkflowIDs.isEmpty && router.currentRequest == nil, "removing a watched folder should stop monitoring and clear its queued run")
    }

    @MainActor
    static func automationTemplateSmokeTest() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaTemplateSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let source = Workflow(
            name: "PRIVATE source workflow",
            transcript: "PRIVATE narration",
            recordingPath: "/Users/private/recording.mp4",
            steps: [
                WorkflowStep(
                    kind: .openURL,
                    title: "Open private portal",
                    time: 0,
                    text: "https://private.example/account"
                ),
                WorkflowStep(
                    kind: .typeText,
                    title: "Enter private amount",
                    time: 1,
                    text: "$12,345",
                    runVariable: true
                ),
                WorkflowStep(
                    kind: .approval,
                    title: "Confirm private submission",
                    time: 2,
                    requiresApproval: true
                )
            ]
        )
        let exported = try AutomationTemplateCodec.make(
            workflow: source,
            publicTitle: "Monthly portal update"
        )
        let file = folder.appendingPathComponent("monthly-portal-update.neloa-template.json")
        try exported.jsonData().write(to: file, options: .atomic)
        let imported = try AutomationTemplateCodec.read(from: file)
        try expect(imported == exported, "a saved reusable template should import without changing its safe guide")

        let defaultsName = "NeloaTemplateSmoke.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsName) else {
            throw Failure(description: "could not create isolated defaults for the reusable-template smoke test")
        }
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let teacher = TeachController(arguments: [], defaults: defaults, environment: [:])
        try expect(teacher.prepare(template: imported), "an idle teaching session should accept an imported guide")
        try expect(teacher.templateGuide == imported, "the imported guide should appear in teaching setup")
        try expect(teacher.draft == nil, "importing a guide must not create an executable workflow or replay actions")

        teacher.reset(preserveTemplate: true)
        try expect(teacher.templateGuide == imported, "Teach again should preserve the imported guide")
        try expect(teacher.draft == nil, "resetting with a guide must still require a fresh local demonstration")

        teacher.reset()
        try expect(teacher.templateGuide == nil, "leaving the guided session should discard imported template state")
        try expect(teacher.draft == nil, "discarding a guide must not leave an executable draft behind")
    }

    @MainActor
    static func qwenSmokeTest(tier: LocalModelTier = .balanced4Bit) async throws {
        guard LocalAgentService.isQwenRuntimeBundled else {
            throw Failure(description: "Qwen smoke test requires NELOA_ENABLE_MLX=1")
        }
        let agent = LocalAgentService(selectedTier: tier)
        print("Preparing \(LocalModelPaths.displayName) \(tier.precisionLabel); the first run downloads \(tier.downloadSizeLabel)…")
        await agent.setupModel()
        try expect(agent.modelStatus == .ready, "Qwen should load successfully; status was: \(agent.modelStatus)")

        let input = WorkflowStep(kind: .typeText, title: "Type June", time: 0, text: "June")
        let workflow = Workflow(name: "Monthly report", transcript: "", steps: [input])
        let plan = await agent.makePlan(workflow: workflow, instruction: "Replace June with August")
        try expect(agent.status.contains("Qwen"), "Qwen should be the primary run planner; status was: \(agent.status)")
        try expect(plan.steps.first?.text == "August", "Qwen plan should preserve the verified June to August replacement")

        let evidenceURL = try makeQwenVisualSmokeImage()
        defer { try? FileManager.default.removeItem(at: evidenceURL.deletingLastPathComponent()) }
        // CGEvent locations use a top-left screen origin. The button is drawn at
        // y 140...198 in the 500-point AppKit image, so its screen-space center is 331.
        let click = WorkflowStep(kind: .click, title: "Click", time: 0.5, x: 168, y: 331)
        let month = WorkflowStep(kind: .typeText, title: "Type June", time: 1, text: "June")
        let visualWorkflow = Workflow(
            name: "My automation",
            transcript: "Use June as the month.",
            steps: [click, month]
        )
        let learned = await agent.learnWorkflow(
            candidate: visualWorkflow,
            evidenceFrames: [WorkflowEvidenceFrame(
                time: 0.5,
                imageURL: evidenceURL,
                recognizedText: [],
                imageWidth: 800,
                imageHeight: 500,
                captureFrame: CGRect(x: 0, y: 0, width: 800, height: 500)
            )]
        )
        try expect(agent.status.contains("Learned privately with Qwen"), "Qwen should complete visual workflow learning; status was: \(agent.status)")
        try expect(learned.steps.count == visualWorkflow.steps.count, "visual learning must not add executable actions")
        try expect(learned.steps[0].x == click.x && learned.steps[0].y == click.y, "visual learning must preserve replay coordinates")

        let spreadsheetURLs = try makeQwenSpreadsheetSmokeImages()
        defer { try? FileManager.default.removeItem(at: spreadsheetURLs[0].deletingLastPathComponent()) }
        let spreadsheetFrames = spreadsheetURLs.enumerated().map { index, url in
            WorkflowEvidenceFrame(
                time: TimeInterval(index),
                imageURL: url,
                recognizedText: index == 0 ? ["Testing Spreadsheet", "A", "B"] : ["Testing Spreadsheet", "A", "B", "X", "2"],
                imageWidth: 1_000,
                imageHeight: 600,
                captureFrame: CGRect(x: 0, y: 0, width: 1_000, height: 600)
            )
        }
        let videoOnly = Workflow(
            name: "My automation",
            transcript: "",
            steps: [WorkflowStep(
                kind: .openApp,
                title: "Open Google Chrome",
                time: 0,
                application: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            )]
        )
        let drafted = await agent.learnWorkflow(candidate: videoOnly, evidenceFrames: spreadsheetFrames)
        let draftedInputs = drafted.steps.filter { $0.kind == .typeText }.compactMap(\.text)
        try expect(agent.status.contains("drafted"), "Qwen should explicitly report when it reconstructed actions from video; status was: \(agent.status)")
        try expect(draftedInputs.contains("X") && draftedInputs.contains("2"), "Qwen should reconstruct both demonstrated spreadsheet values from video; got \(draftedInputs)")
        try expect(drafted.steps.filter { $0.kind == .typeText }.allSatisfy { $0.x != nil && $0.y != nil }, "Qwen's video-drafted inputs should be grounded to spreadsheet-cell coordinates")

        let pairPlan = await agent.makePlan(workflow: drafted, instruction: "Use Z as the label and put 7 in the cell next to it")
        let changedValues = Set(pairPlan.changes.map(\.after))
        try expect(changedValues == Set(["Z", "7"]), "Qwen should customize both spreadsheet fields in one run; got \(changedValues)")
    }

    @MainActor
    static func qwenRecordingTest(recordingPath: String) async throws {
        let url = URL(fileURLWithPath: recordingPath)
        try expect(FileManager.default.fileExists(atPath: url.path), "recording test input must exist")
        let agent = LocalAgentService()
        let candidate = Workflow(name: "Recorded workflow", transcript: "", steps: [])
        let frames = try await WorkflowEvidenceExtractor.extract(
            recordingURL: url,
            steps: [],
            captureFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        )
        for (index, frame) in frames.enumerated() {
            let focus = frame.focusReason ?? "overview"
            let selection = WorkflowLearner.selectedSpreadsheetImagePoint(at: frame.imageURL)
            fputs(
                "Evidence \(index + 1): t=\(frame.time), size=\(frame.imageWidth ?? 0)x\(frame.imageHeight ?? 0), focus=\(focus), selection=\(String(describing: selection)), path=\(frame.imageURL.path), OCR=\(frame.recognizedText)\n",
                stderr
            )
        }
        let learned = await agent.learnWorkflow(
            candidate: candidate,
            evidenceFrames: frames
        )
        let actions = learned.steps.filter { [.click, .typeText, .keyPress].contains($0.kind) }
        let actionDescriptions = actions.map { step in
            "\(step.kind.rawValue):\(step.text ?? step.title)"
        }
        fputs("Neloa learned recording actions: \(actionDescriptions)\n", stderr)
        try expect(actions.contains(where: { $0.kind == .typeText && $0.text == "X" }), "Qwen should recover the demonstrated X input")
        try expect(actions.contains(where: { $0.kind == .typeText && $0.text == "2" }), "Qwen should recover the demonstrated 2 input")
    }

    @MainActor
    private static func makeQwenVisualSmokeImage() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaQwenSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let image = NSImage(size: NSSize(width: 800, height: 500))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 800, height: 500).fill()
        ("Monthly Report" as NSString).draw(
            at: NSPoint(x: 48, y: 410),
            withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.black]
        )
        ("Month" as NSString).draw(
            at: NSPoint(x: 48, y: 315),
            withAttributes: [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: NSColor.darkGray]
        )
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 250, width: 300, height: 52), xRadius: 10, yRadius: 10).fill()
        ("June" as NSString).draw(
            at: NSPoint(x: 66, y: 265),
            withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor.black]
        )
        NSColor.systemBlue.setFill()
        NSBezierPath(roundedRect: NSRect(x: 48, y: 140, width: 240, height: 58), xRadius: 14, yRadius: 14).fill()
        ("Download report" as NSString).draw(
            at: NSPoint(x: 82, y: 157),
            withAttributes: [.font: NSFont.systemFont(ofSize: 19, weight: .semibold), .foregroundColor: NSColor.white]
        )
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            throw Failure(description: "could not create the Qwen visual smoke-test image")
        }
        let url = directory.appendingPathComponent("monthly-report.png")
        try png.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    @MainActor
    private static func makeQwenSpreadsheetSmokeImages() throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaQwenSpreadsheet-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        func render(name: String, label: String?, number: String?) throws -> URL {
            let image = NSImage(size: NSSize(width: 1_000, height: 600))
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: 1_000, height: 600).fill()
            ("Testing Spreadsheet" as NSString).draw(
                at: NSPoint(x: 35, y: 535),
                withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .semibold), .foregroundColor: NSColor.black]
            )
            NSColor(calibratedWhite: 0.92, alpha: 1).setStroke()
            let grid = NSBezierPath()
            for x in stride(from: 35.0, through: 735.0, by: 175.0) {
                grid.move(to: NSPoint(x: x, y: 300))
                grid.line(to: NSPoint(x: x, y: 500))
            }
            for y in stride(from: 300.0, through: 500.0, by: 50.0) {
                grid.move(to: NSPoint(x: 35, y: y))
                grid.line(to: NSPoint(x: 735, y: y))
            }
            grid.lineWidth = 1
            grid.stroke()
            ("A" as NSString).draw(at: NSPoint(x: 115, y: 507), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
            ("B" as NSString).draw(at: NSPoint(x: 290, y: 507), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
            if let label {
                (label as NSString).draw(at: NSPoint(x: 48, y: 458), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
            }
            if let number {
                (number as NSString).draw(at: NSPoint(x: 223, y: 458), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
            }
            image.unlockFocus()

            guard let tiff = image.tiffRepresentation,
                  let representation = NSBitmapImageRep(data: tiff),
                  let png = representation.representation(using: .png, properties: [:]) else {
                throw Failure(description: "could not create the Qwen spreadsheet smoke-test image")
            }
            let url = directory.appendingPathComponent(name)
            try png.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return url
        }

        return [
            try render(name: "01-empty.png", label: nil, number: nil),
            try render(name: "02-label.png", label: "X", number: nil),
            try render(name: "03-number.png", label: "X", number: "2")
        ]
    }

    private static func compilationCheck() throws {
        let events = [
            CaptureEvent(time: 0.5, kind: .click, x: 120, y: 240, application: "Safari", bundleIdentifier: "com.apple.Safari"),
            CaptureEvent(time: 1.0, kind: .text, text: "June", application: "Safari"),
            CaptureEvent(time: 1.2, kind: .text, text: " report", application: "Safari"),
            CaptureEvent(time: 2.0, kind: .keyPress, keyCode: 36, application: "Safari")
        ]
        let workflow = WorkflowCompiler.compile(events: events, transcript: "Always ask me before sending.", name: "Weekly report")
        try expect(workflow.steps.map(\.kind) == [.openApp, .click, .typeText, .approval, .keyPress], "approval should be inserted before the final action")
        try expect(workflow.steps[2].text == "June report", "adjacent typing should merge")
        try expect(workflow.steps[3].requiresApproval, "spoken approval rule should become a gate")
    }

    private static func supportedUseCaseScenarioCheck() throws {
        let command = CGEventFlags.maskCommand.rawValue
        let reportEvents = [
            CaptureEvent(time: 0.2, kind: .keyPress, keyCode: 37, flags: command, application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 0.5, kind: .text, text: "reports.example.com/monthly", target: "Address and search bar", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 0.8, kind: .keyPress, keyCode: 36, application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 1.5, kind: .click, x: 300, y: 220, target: "Report month", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 1.8, kind: .text, text: "July 2026", target: "Report month", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 2.1, kind: .keyPress, keyCode: 48, application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 2.4, kind: .text, text: "$2,500", target: "Amount", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 3.0, kind: .click, x: 440, y: 410, target: "Download report", application: "Google Chrome", bundleIdentifier: "com.google.Chrome")
        ]
        let report = WorkflowCompiler.compile(
            events: reportEvents,
            transcript: "Open the monthly report, use July 2026 and $2,500, then download it.",
            name: "Download monthly report"
        )
        try expect(
            report.steps.first(where: { $0.kind == .openURL })?.text == "https://reports.example.com/monthly",
            "a demonstrated report URL should become stable navigation instead of a flexible input"
        )
        try expect(
            report.steps.filter(\.isRunVariable).compactMap(\.target) == ["Report month", "Amount"],
            "report inputs should retain their focused field roles"
        )
        try expect(
            report.steps.first(where: { $0.target == "Download report" })?.requiresApproval == false,
            "an ordinary report download should not create a consequential-action pause"
        )

        let formEvents = [
            CaptureEvent(time: 0.4, kind: .text, text: "Acme", target: "Client name", application: "Safari", bundleIdentifier: "com.apple.Safari"),
            CaptureEvent(time: 0.8, kind: .keyPress, keyCode: 48, application: "Safari", bundleIdentifier: "com.apple.Safari"),
            CaptureEvent(time: 1.2, kind: .text, text: "$500", target: "Invoice amount", application: "Safari", bundleIdentifier: "com.apple.Safari"),
            CaptureEvent(time: 1.6, kind: .keyPress, keyCode: 48, application: "Safari", bundleIdentifier: "com.apple.Safari"),
            CaptureEvent(time: 2.0, kind: .text, text: "August 31", target: "Due date", application: "Safari", bundleIdentifier: "com.apple.Safari"),
            CaptureEvent(time: 2.8, kind: .click, x: 500, y: 600, target: "Submit invoice", application: "Safari", bundleIdentifier: "com.apple.Safari")
        ]
        let form = WorkflowCompiler.compile(
            events: formEvents,
            transcript: "Enter Acme, invoice amount $500, and due date August 31, then submit the invoice.",
            name: "Submit client invoice"
        )
        try expect(
            form.steps.filter(\.isRunVariable).compactMap(\.target) == ["Client name", "Invoice amount", "Due date"],
            "client and invoice forms should expose distinct named inputs"
        )
        let formInputs = form.steps.filter(\.isRunVariable)
        let response = AgentPlanResponse(
            summary: "Use Bluebird, $750, and September 15",
            replacements: [
                AgentReplacement(stepID: formInputs[0].id.uuidString, text: "Bluebird", reason: "Requested client"),
                AgentReplacement(stepID: formInputs[1].id.uuidString, text: "$750", reason: "Requested amount"),
                AgentReplacement(stepID: formInputs[2].id.uuidString, text: "September 15", reason: "Requested due date")
            ]
        )
        let formPlan = RunPlanner.plan(
            workflow: form,
            instruction: "Use Bluebird, $750, and September 15",
            agentResponse: response
        )
        try expect(
            formPlan.changes.map(\.after) == ["Bluebird", "$750", "September 15"],
            "one instruction should safely customize all named form values"
        )
        guard let submit = formPlan.steps.first(where: { $0.target == "Submit invoice" }) else {
            throw Failure(description: "the form scenario should retain its captured submit action")
        }
        try expect(
            AutomationRunner.approvalPrompt(for: submit) != nil,
            "captured Submit actions should pause for approval even when the user did not narrate a gate"
        )

        let transfer = WorkflowCompiler.compile(events: [
            CaptureEvent(time: 0.5, kind: .keyPress, keyCode: 8, flags: command, application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 1.0, kind: .appSwitch, application: "TextEdit", bundleIdentifier: "com.apple.TextEdit"),
            CaptureEvent(time: 1.5, kind: .keyPress, keyCode: 9, flags: command, application: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
        ], transcript: "Copy the known account number into TextEdit.", name: "Copy account number")
        try expect(
            transfer.steps.map(\.title) == ["Open Google Chrome", "Copy selected content", "Open TextEdit", "Paste copied content"],
            "cross-app copy and paste should be reviewable as meaningful actions"
        )

        let narratedApproval = WorkflowCompiler.compile(
            events: [CaptureEvent(time: 2, kind: .click, x: 10, y: 10, target: "Send", application: "Mail", bundleIdentifier: "com.apple.mail")],
            transcript: "Always ask before sending.",
            narrationSegments: [NarrationSegment(text: "Always ask before sending.", time: 1, duration: 0.8)]
        )
        let approvalPauses = narratedApproval.steps.filter {
            AutomationRunner.approvalPrompt(for: $0) != nil
        }
        try expect(approvalPauses.count == 1, "a narrated gate and automatic Send protection should produce one approval pause, not two")
    }

    private static func googleDriveSpreadsheetSemanticCompilationCheck() throws {
        let chrome = "Google Chrome"
        let bundle = "com.google.Chrome"
        let events = [
            CaptureEvent(time: 1.57, kind: .click, x: 2_144, y: 571, application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 3.11, kind: .keyPress, keyCode: 17, flags: CGEventFlags.maskCommand.rawValue, application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 3.74, kind: .text, text: "dr", application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 4.90, kind: .keyPress, keyCode: 36, application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 6.62, kind: .click, x: 2_147, y: 821, application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 9.24, kind: .click, x: 1_794, y: 1_092, application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 16.50, kind: .text, text: "X", application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 17.19, kind: .keyPress, keyCode: 124, application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 20.36, kind: .text, text: "3", application: chrome, bundleIdentifier: bundle, displayID: 2),
            CaptureEvent(time: 21.07, kind: .keyPress, keyCode: 36, application: chrome, bundleIdentifier: bundle, displayID: 2)
        ]
        let narration = "First we go on Google Drive then we click on this testing spreadsheet then we click on creating a new sheet so now we have one that's a sheet two in column A1 we put X and in column B1 I'm gonna put three"
        let workflow = WorkflowCompiler.compile(events: events, transcript: narration, name: "First we go on Google Drive")

        try expect(workflow.name == "Fill Sheet2 in Testing Spreadsheet", "spreadsheet narration should produce a task-level workflow name")
        try expect(
            workflow.steps.map(\.kind) == [.openApp, .openURL, .click, .click, .typeText, .keyPress, .typeText, .keyPress],
            "browser navigation and spreadsheet edits should compile into a concise replay graph; got \(workflow.steps.map(\.kind))"
        )
        try expect(workflow.steps[1].text == "https://drive.google.com", "typed browser shorthand should become a stable Google Drive URL")
        try expect(workflow.steps[2].title == "Open Testing Spreadsheet" && workflow.steps[2].target == "Testing Spreadsheet", "the Drive click should retain the narrated file target")
        try expect(workflow.steps[3].title == "Create Sheet2" && workflow.steps[3].target == "Add sheet", "the sheet-tab click should retain a layout-independent accessibility target")
        let inputs = workflow.steps.filter(\.isRunVariable)
        try expect(inputs.map(\.text) == ["X", "3"], "only demonstrated spreadsheet values should be flexible; got \(inputs.compactMap(\.text))")
        try expect(inputs.map(\.target) == ["Sheet2!A1", "Sheet2!B1"], "spreadsheet inputs should expose stable cell roles")
        try expect(!workflow.steps.contains(where: { $0.text == "dr" }), "browser navigation shorthand must not appear as a flexible input")
        try expect(workflow.steps[5].title == "Move to Sheet2!B1", "the captured arrow key should retain its cell destination")
        try expect(workflow.steps[7].title == "Finish editing Sheet2!B1", "the final Return should explain that it commits the edit")

        let prompt = RunPlanner.prompt(workflow: workflow, instruction: "Use Z in A1 and 7 in B1")
        try expect(prompt.contains("Sheet2!A1") && prompt.contains("Sheet2!B1"), "the local planner should receive semantic spreadsheet targets")
        try expect(!prompt.contains("\"current_text\":\"dr\""), "fixed browser navigation must not be offered to the run planner")
        try expect(AutomationRunner.replayDelay(after: workflow.steps[2], before: workflow.steps[3]) > 2.5, "web replay should preserve the demonstrated load time between actions")
        try expect(AutomationRunner.replayDelay(after: workflow.steps[3], before: workflow.steps[4]) == 4, "long recorded pauses should be retained up to the safe replay cap")
    }

    private static func timedNarrationCorrelationCheck() throws {
        let narration = [
            NarrationSegment(text: "Open", time: 1.00, duration: 0.30, confidence: 0.96),
            NarrationSegment(text: "the", time: 1.34, duration: 0.18, confidence: 0.99),
            NarrationSegment(text: "report.", time: 1.55, duration: 0.45, confidence: 0.94),
            NarrationSegment(text: "Always", time: 6.00, duration: 0.40, confidence: 0.98),
            NarrationSegment(text: "ask", time: 6.44, duration: 0.22, confidence: 0.97),
            NarrationSegment(text: "before", time: 6.70, duration: 0.35, confidence: 0.97),
            NarrationSegment(text: "sharing.", time: 7.08, duration: 0.48, confidence: 0.96)
        ]
        let utterances = NarrationTimeline.utterances(from: narration)
        try expect(utterances.count == 2, "timestamped words should group into two spoken utterances")
        try expect(utterances[1].text == "Always ask before sharing.", "utterance grouping should retain readable punctuation")

        let events = [
            CaptureEvent(time: 2, kind: .click, x: 10, y: 10, application: "Safari"),
            CaptureEvent(time: 7, kind: .click, x: 20, y: 20, application: "Safari"),
            CaptureEvent(time: 10, kind: .click, x: 30, y: 30, application: "Safari")
        ]
        let workflow = WorkflowCompiler.compile(
            events: events,
            transcript: "Open the report. Always ask before sharing.",
            narrationSegments: narration
        )
        guard let approvalIndex = workflow.steps.firstIndex(where: { $0.kind == .approval }) else {
            throw Failure(description: "timed approval narration should create an approval step")
        }
        try expect(workflow.steps[approvalIndex].time == 6, "spoken rules should retain their recording timestamp")
        try expect(
            approvalIndex + 1 < workflow.steps.count && workflow.steps[approvalIndex + 1].time == 7,
            "a timed approval should be placed before the next recorded action"
        )
        try expect(
            NarrationTimeline.context(around: 6.5, in: workflow) == "Always ask before sharing.",
            "a visual frame should receive narration spoken near its timestamp"
        )
        try expect(
            NarrationTimeline.promptLines(for: workflow).contains("[00:06.00"),
            "the model prompt should expose narration timestamps"
        )

        let spreadsheet = Workflow(
            name: "Timed cells",
            transcript: "In the spreadsheet, in B1 put X. In A1 put 3.",
            narrationSegments: [
                NarrationSegment(text: "In B1 put X.", time: 3.5, duration: 1),
                NarrationSegment(text: "In A1 put 3.", time: 9.5, duration: 1)
            ],
            steps: [
                WorkflowStep(kind: .typeText, title: "Type X", time: 4, text: "X"),
                WorkflowStep(kind: .typeText, title: "Type 3", time: 10, text: "3")
            ]
        )
        let correlatedSpreadsheet = WorkflowSemanticEnricher.enrich(spreadsheet)
        try expect(
            correlatedSpreadsheet.steps.map(\.target) == ["B1", "A1"],
            "spreadsheet values should inherit the cell narrated nearest their action rather than a fixed positional guess; got \(correlatedSpreadsheet.steps.map(\.target)), name \(correlatedSpreadsheet.name), variables \(correlatedSpreadsheet.steps.map(\.isRunVariable))"
        )
    }

    private static func spokenOnlyCheck() throws {
        let workflow = WorkflowCompiler.compile(events: [], transcript: "Download the latest report")
        try expect(workflow.steps.count == 1 && workflow.steps[0].kind == .decision, "spoken-only teaching should create a step")
    }

    private static func replacementCheck() throws {
        let first = WorkflowStep(kind: .typeText, title: "Type June", time: 0, text: "June")
        let second = WorkflowStep(kind: .typeText, title: "Type report", time: 1, text: "report")
        let workflow = Workflow(name: "Report", transcript: "", steps: [first, second])
        let plan = RunPlanner.plan(workflow: workflow, instruction: "Replace June with July")
        try expect(plan.changes.count == 1 && plan.steps[0].text == "July" && plan.steps[1].text == "report", "explicit replacement should be scoped")
    }

    private static func amountCheck() throws {
        let amount = WorkflowStep(kind: .typeText, title: "Type amount", time: 0, text: "$500")
        let note = WorkflowStep(kind: .typeText, title: "Type note", time: 1, text: "Supplies")
        let workflow = Workflow(name: "Expense", transcript: "", steps: [amount, note])
        let plan = RunPlanner.plan(workflow: workflow, instruction: "Run it using amount $750")
        try expect(plan.steps[0].text == "$750" && plan.changes.first?.before == "$500", "amount variation should target numeric input")
    }

    private static func spreadsheetCellRetargetingCheck() throws {
        var label = WorkflowStep(kind: .typeText, title: "Set A1 to X", time: 1, text: "X")
        label.target = "A1"
        label.runVariable = true
        var move = WorkflowStep(kind: .keyPress, title: "Move to B2", time: 2, target: "B2", keyCode: 48)
        move.runVariable = false
        var amount = WorkflowStep(kind: .typeText, title: "Set B2 to 2", time: 3, text: "2")
        amount.target = "B2"
        amount.runVariable = true
        let commit = WorkflowStep(kind: .keyPress, title: "Finish editing B2", time: 4, target: "B2", keyCode: 36)
        label.application = "Google Chrome"
        label.bundleIdentifier = "com.google.Chrome"
        move.application = "Google Chrome"
        move.bundleIdentifier = "com.google.Chrome"
        amount.application = "Google Chrome"
        amount.bundleIdentifier = "com.google.Chrome"
        let workflow = Workflow(name: "Update spreadsheet", transcript: "Google Sheets", steps: [label, move, amount, commit])

        let plan = RunPlanner.plan(workflow: workflow, instruction: "Set column C3 to 3")
        try expect(plan.summary == "Set C3 to 3 for this run", "a new spreadsheet target should produce a clear run summary")
        try expect(RunPresentation.summary(for: plan) == "For this run, Neloa will set C3 to 3.", "the preview should describe the cell/value pair as one action")
        try expect(plan.changes.map(\.after) == ["C3", "3"], "the preview should expose both the target and value change")
        try expect(plan.steps.contains(where: { $0.kind == .selectSpreadsheetCell && $0.target == "C3" }), "a new target should use safe Go to range navigation")
        try expect(plan.steps.first(where: { $0.kind == .typeText && $0.target == "C3" })?.text == "3", "the requested value should be typed only after selecting C3")
        try expect(plan.steps.first(where: { $0.target == "A1" })?.text == "X", "unmentioned spreadsheet inputs should stay unchanged")
        try expect(!plan.steps.contains(where: { $0.kind == .click && $0.target == "C3" }), "cell retargeting must not invent a coordinate click")

        try expect(
            RunPlanner.spreadsheetCellPlan(workflow: workflow, instruction: "Delete the sheet and send it") == nil,
            "unstructured or consequential requests must not enter the spreadsheet navigation path"
        )
    }

    private static func agentResponseSafetyCheck() throws {
        let input = WorkflowStep(kind: .typeText, title: "Type month", time: 0, text: "June")
        let workflow = Workflow(name: "Report", transcript: "", steps: [input])
        let injected = AgentPlanResponse(
            summary: String(repeating: "s", count: 400),
            replacements: [
                AgentReplacement(stepID: input.id.uuidString, text: "July\u{0}unsafe", reason: String(repeating: "r", count: 400))
            ]
        )
        let rejected = RunPlanner.plan(workflow: workflow, instruction: "Use a different month", agentResponse: injected)
        try expect(rejected.changes.isEmpty, "agent output containing hidden control characters must be rejected")
        try expect(rejected.summary.count == 240, "agent summaries should be capped before display")

        let valid = AgentPlanResponse(
            summary: "Use July",
            replacements: [AgentReplacement(stepID: input.id.uuidString, text: "July", reason: "Requested month")]
        )
        let accepted = RunPlanner.plan(workflow: workflow, instruction: "Use a different month", agentResponse: valid)
        try expect(accepted.steps.first?.text == "July", "a safe agent replacement should still be accepted for review")

        var spreadsheetInput = WorkflowStep(kind: .typeText, title: "Set Sheet2!A1", time: 0, text: "X")
        spreadsheetInput.target = "Sheet2!A1"
        spreadsheetInput.runVariable = true
        let spreadsheet = Workflow(name: "Fill spreadsheet", transcript: "", steps: [spreadsheetInput])
        let structural = AgentPlanResponse(
            summary: "Use another sheet",
            replacements: [AgentReplacement(stepID: spreadsheetInput.id.uuidString, text: "Sheet3!A1", reason: "Requested sheet")]
        )
        let structurallyRejected = RunPlanner.plan(
            workflow: spreadsheet,
            instruction: "Use Sheet3 instead of Sheet2",
            agentResponse: structural
        )
        try expect(structurallyRejected.changes.isEmpty, "a model must not smuggle a spreadsheet structure change into a cell value")
    }

    private static func staleEvidenceCleanupCheck() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaEvidence-SelfTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        WorkflowEvidenceExtractor.purgeStaleTemporaryEvidence(olderThan: 0)
        try expect(!FileManager.default.fileExists(atPath: directory.path), "stale temporary screenshots should be removed")
    }

    private static func denseEvidenceSamplingCheck() throws {
        let times = WorkflowEvidenceExtractor.candidateSampleTimes(
            steps: [WorkflowStep(kind: .typeText, title: "Late input", time: 30, text: "X")],
            duration: 18,
            maximumCount: 30
        )
        try expect(
            times.count > WorkflowEvidenceExtractor.maximumFrameCount,
            "visual learning should scan more frames than it sends to Qwen"
        )
        try expect(
            times.first == 0 && (times.last ?? 0) > 17,
            "dense evidence scanning should cover the whole recording"
        )
        let largestGap = zip(times, times.dropFirst()).map { $1 - $0 }.max() ?? .infinity
        try expect(largestGap < 1.1, "dense evidence scanning should catch brief visual edits")
        try expect((times.last ?? .infinity) <= 17.92, "event-adjacent evidence must be clamped to the recording duration")
    }

    private static func recoveryEvidenceRoutingCheck() throws {
        let root = FileManager.default.temporaryDirectory
        let context = WorkflowEvidenceFrame(time: 0, imageURL: root.appendingPathComponent("context.png"), recognizedText: ["Testing Spreadsheet"])
        let noise = WorkflowEvidenceFrame(time: 1, imageURL: root.appendingPathComponent("noise.png"), recognizedText: ["Share"], focusReason: "visual change")
        let firstCell = WorkflowEvidenceFrame(time: 2, imageURL: root.appendingPathComponent("a.png"), recognizedText: ["A15", "X"], focusReason: "visual change")
        let secondCell = WorkflowEvidenceFrame(time: 3, imageURL: root.appendingPathComponent("b.png"), recognizedText: ["B15", "2"], focusReason: "visual change")
        let routed = WorkflowEvidenceExtractor.prioritizedRecoveryFrames([context, noise, firstCell, secondCell])
        try expect(routed.count == 2, "spreadsheet recovery should send only grounded cell close-ups")
        try expect(routed.last?.recognizedText.contains("B15") == true, "the last recovery image should retain the latest edited cell")

        let firstResponse = LearnedWorkflowResponse(
            name: "Fill spreadsheet row",
            application: "Google Chrome",
            annotations: [],
            decisions: [],
            proposedActions: [LearnedWorkflowResponse.ProposedAction(
                kind: "typeText", title: "Enter X in cell A15", detail: "X",
                time: 0, image: 1, x: 50, y: 200, text: "X", confidence: 0.95
            )]
        )
        let secondResponse = LearnedWorkflowResponse(
            name: "Fill spreadsheet row",
            application: "Google Chrome",
            annotations: [],
            decisions: [],
            proposedActions: [LearnedWorkflowResponse.ProposedAction(
                kind: "typeText", title: "Enter 2 in cell B15", detail: "2",
                time: 0, image: 1, x: 120, y: 200, text: "2", confidence: 0.95
            )]
        )
        let merged = WorkflowLearner.mergingRecoveryResponses([
            (firstResponse, 0, 2), (secondResponse, 1, 3)
        ])
        try expect(merged.proposedActions?.map(\.text) == ["X", "2"], "per-frame recovery should preserve both demonstrated values")
        try expect(merged.proposedActions?.map(\.image) == [1, 2], "merged recovery actions should retain their evidence image")
    }

    private static func evidenceCoordinateMappingCheck() throws {
        let mapped = WorkflowEvidenceExtractor.mappedCaptureFrame(
            crop: CGRect(x: 10, y: 20, width: 100, height: 50),
            sourceWidth: 200,
            sourceHeight: 100,
            captureFrame: CGRect(x: 1_000, y: 500, width: 400, height: 200)
        )
        try expect(mapped == CGRect(x: 1_020, y: 540, width: 200, height: 100), "evidence crops must preserve top-origin screen coordinates")
    }

    private static func qwenResponseRepairCheck() throws {
        let stepID = UUID().uuidString
        let malformed = """
        {"summary:"Replaced June with August."
        replacements:[{"step_id":"\(stepID)","text":"August","reason":"Requested month"}]
        """
        guard let data = QwenResponseSupport.jsonData(
            from: malformed,
            topLevelKeys: ["summary", "replacements"]
        ) else {
            throw Failure(description: "Qwen's known top-level punctuation error should be repairable")
        }
        let response = try JSONDecoder().decode(AgentPlanResponse.self, from: data)
        try expect(response.replacements.first?.text == "August", "repaired Qwen output should preserve the requested value")

        let wrapped = "{ stray preface\n{\"name\":\"Download report\",\"annotations\":[],\"decisions\":[]}"
        guard let wrappedData = QwenResponseSupport.jsonData(
            from: wrapped,
            topLevelKeys: ["name", "annotations", "decisions"]
        ) else {
            throw Failure(description: "a valid Qwen object should be extracted from a stray preface")
        }
        let learned = try JSONDecoder().decode(LearnedWorkflowResponse.self, from: wrappedData)
        try expect(learned.name == "Download report", "visual response extraction should select the schema object")

        let nestedVisual = """
        {"name":"Spreadsheet entry","application":"Google Chrome","annotations":[],"proposedActions":[{"kind":"typeText","title":"Enter label","detail":{"image":2,"x":100,"y":150,"text":"X"},"time":1,"confidence":0.95}],"decisions":[]}
        """
        let nestedResponse = try WorkflowLearner.decode(nestedVisual)
        try expect(
            nestedResponse.proposedActions?.first?.text == "X"
                && nestedResponse.proposedActions?.first?.image == 2
                && nestedResponse.proposedActions?.first?.x == 100,
            "Qwen's compact nested visual-action payload should decode without discarding grounded coordinates"
        )

        let unrelated = "This is not a structured response"
        try expect(
            QwenResponseSupport.jsonData(from: unrelated, topLevelKeys: ["summary", "replacements"]) == nil,
            "unstructured model output must still be rejected"
        )
    }

    private static func serializationCheck() throws {
        let segment = NarrationSegment(text: "hello", time: 1.25, duration: 0.4, confidence: 0.95)
        let workflow = Workflow(name: "Serializable", transcript: "hello", narrationSegments: [segment], steps: [])
        let data = try JSONEncoder.neloa.encode(workflow)
        let decoded = try JSONDecoder.neloa.decode(Workflow.self, from: data)
        try expect(
            decoded.id == workflow.id
                && decoded.name == workflow.name
                && decoded.transcript == workflow.transcript
                && decoded.narrationSegments == [segment]
                && decoded.steps == workflow.steps,
            "saved workflows with timed narration should round-trip"
        )

        let legacyJSON = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy",
          "createdAt": "2026-01-01T00:00:00Z",
          "updatedAt": "2026-01-01T00:00:00Z",
          "transcript": "hello",
          "steps": [],
          "defaultInstruction": "Run it the same way"
        }
        """.data(using: .utf8)!
        let legacy = try JSONDecoder.neloa.decode(Workflow.self, from: legacyJSON)
        try expect(legacy.narrationSegments == nil, "workflows saved before timed narration should still decode")
    }

    private static func receiptSerializationCheck() throws {
        let receipt = AutomationRunReceipt(
            workflowID: UUID(),
            workflowName: "Monthly report",
            startedAt: Date(),
            instruction: "Use August",
            summary: "One verified change",
            changes: [],
            stepCount: 4,
            status: .completed
        )
        let data = try JSONEncoder.neloa.encode(receipt)
        let decoded = try JSONDecoder.neloa.decode(AutomationRunReceipt.self, from: data)
        try expect(decoded.id == receipt.id && decoded.workflowName == receipt.workflowName && decoded.status == .completed, "activity receipts should round-trip")
    }

    private static func skillExportCheck() throws {
        let input = WorkflowStep(kind: .typeText, title: "Type report month", time: 0, text: "June")
        let approval = WorkflowStep(kind: .approval, title: "Ask before sending", time: 1, requiresApproval: true)
        let workflow = Workflow(name: "Monthly Report", transcript: "", steps: [input, approval])
        let markdown = SkillExporter.markdown(for: workflow)
        try expect(markdown.contains("name: monthly-report"), "skill export should include portable frontmatter")
        try expect(markdown.contains("`June`"), "skill export should identify flexible inputs")
        try expect(markdown.contains("Ask before sending"), "skill export should preserve approval rules")
    }

    private static func brandMigrationCheck() throws {
        let legacy = BrandMigration.legacyApplicationSupportDirectory
            .appendingPathComponent("Recordings/example/teach.mp4").path
        let repaired = BrandMigration.repairedAssetPath(legacy)
        let expected = BrandMigration.applicationSupportDirectory
            .appendingPathComponent("Recordings/example/teach.mp4").path
        try expect(repaired == expected, "legacy Humana recording paths should migrate to Neloa")
    }

    private static func localModelEligibilityCheck() throws {
        let supported = LocalModelHardware(
            isAppleSilicon: true,
            physicalMemoryBytes: 16 * 1_024 * 1_024 * 1_024,
            freeDiskBytes: 8 * 1_024 * 1_024 * 1_024
        )
        try expect(supported.eligibilityIssue == nil, "an Apple silicon Mac with 16 GB should support the local model")
        try expect(supported.eligibilityIssue(for: .quality8Bit)?.contains("10 GB") == true, "the 8-bit tier should reserve enough download workspace")
        var unsupported = supported
        unsupported.physicalMemoryBytes = 8 * 1_024 * 1_024 * 1_024
        try expect(unsupported.eligibilityIssue?.contains("16 GB") == true, "lower-memory Macs should receive a clear model requirement")
        unsupported = supported
        unsupported.isAppleSilicon = false
        try expect(unsupported.eligibilityIssue?.contains("Apple silicon") == true, "Intel Macs should receive a clear model requirement")
        unsupported = supported
        unsupported.freeDiskBytes = 2 * 1_024 * 1_024 * 1_024
        try expect(unsupported.eligibilityIssue?.contains("6 GB") == true, "low-storage Macs should receive a clear model requirement")
    }

    private static func localModelCacheValidationCheck() throws {
        try expect(LocalModelTier.resolve(nil) == .balanced4Bit, "4-bit should remain the safe default")
        for tier in LocalModelTier.allCases {
            try expect(tier.modelRevision.count == 40, "every visual model tier should be pinned to an immutable revision")
            if !FileManager.default.fileExists(atPath: LocalModelPaths.installMarkerURL(for: tier).path) {
                try expect(!LocalModelPaths.isInstalled(tier), "a cache without its tier marker must not be treated as installed")
            }
        }
    }

    private static func workflowLearningCheck() throws {
        let click = WorkflowStep(kind: .click, title: "Click", time: 1, x: 30, y: 40)
        let input = WorkflowStep(kind: .typeText, title: "Type June", time: 2, text: "June")
        let workflow = Workflow(name: "My automation", transcript: "Use the monthly report", steps: [click, input])
        let response = LearnedWorkflowResponse(
            name: "Prepare monthly report",
            annotations: [
                .init(stepID: click.id.uuidString, title: "Click Download report", detail: "Download the monthly CSV", confidence: 0.92),
                .init(stepID: UUID().uuidString, title: "Invented action", detail: nil, confidence: 1)
            ],
            decisions: []
        )
        let learned = WorkflowLearner.apply(response, to: workflow)
        try expect(learned.name == "Prepare monthly report", "the visual model should improve the workflow name")
        try expect(learned.steps.count == workflow.steps.count, "the visual model must not invent executable steps")
        try expect(learned.steps[0].title == "Click Download report" && learned.steps[0].x == 30, "visual labels should preserve replay coordinates")
        try expect(WorkflowEvidenceExtractor.sampleTimes(steps: workflow.steps, maximumCount: 1).count == 1, "evidence sampling should stay within its memory budget")
        let postTypingTimes = WorkflowEvidenceExtractor.sampleTimes(
            steps: [WorkflowStep(kind: .typeText, title: "Type X", time: 2, text: "X")],
            maximumCount: 1
        )
        try expect((postTypingTimes.first ?? 0) > 2.2, "typed-input evidence should be sampled after the value becomes visible")
        let videoOnlyTimes = WorkflowEvidenceExtractor.sampleTimes(steps: [], duration: 12, maximumCount: 8)
        try expect(videoOnlyTimes.count == 8 && videoOnlyTimes.first == 0 && (videoOnlyTimes.last ?? 0) > 11, "video-only teaching should sample the full recording even with zero captured events")

        let location = WorkflowLearner.evidenceLocation(
            for: WorkflowStep(kind: .click, title: "Click", time: 1, x: 1_100, y: 350),
            frames: [WorkflowEvidenceFrame(
                time: 1,
                imageURL: URL(fileURLWithPath: "/tmp/not-read.png"),
                recognizedText: [],
                imageWidth: 1_000,
                imageHeight: 500,
                captureFrame: CGRect(x: 100, y: 100, width: 2_000, height: 1_000)
            )]
        )
        try expect(location?.image == 1 && location?.point == CGPoint(x: 500, y: 125), "global Retina-display clicks should normalize into evidence-image pixels")

        let videoFrame = WorkflowEvidenceFrame(
            time: 2,
            imageURL: URL(fileURLWithPath: "/tmp/not-read.png"),
            recognizedText: ["X", "2"],
            imageWidth: 1_000,
            imageHeight: 500,
            captureFrame: CGRect(x: 100, y: 50, width: 2_000, height: 1_000)
        )
        let videoOnlyResponse = LearnedWorkflowResponse(
            name: "Add spreadsheet row",
            application: "Google Chrome",
            annotations: [],
            decisions: [],
            proposedActions: [
                .init(kind: "click", title: "Select the label cell", time: 0.5, image: 1, x: 250, y: 100, confidence: 0.94),
                .init(kind: "typeText", title: "Enter the label", time: 0.8, text: "X", confidence: 0.96),
                .init(kind: "click", title: "Select the value cell", time: 1.2, image: 1, x: 500, y: 100, confidence: 0.93),
                .init(kind: "typeText", title: "Enter the number", time: 1.5, text: "2", confidence: 0.97)
            ]
        )
        let videoDraft = WorkflowLearner.apply(
            videoOnlyResponse,
            to: Workflow(name: "My automation", transcript: "", steps: []),
            frames: [videoFrame]
        )
        try expect(videoDraft.steps.map(\.kind) == [.openApp, .click, .typeText, .click, .typeText], "Qwen should be able to draft a complete reviewed workflow when native events are absent")
        try expect(videoDraft.steps.filter { $0.origin == .visual }.count == 5, "video-drafted actions should remain visibly attributable to Qwen")
        try expect(videoDraft.steps[1].x == 600 && videoDraft.steps[1].y == 250, "Qwen image coordinates should map back to global replay coordinates")
        try expect(videoDraft.steps[2].text == "X" && videoDraft.steps[4].text == "2", "video-drafted typed values should remain customizable")

        let partialResponse = LearnedWorkflowResponse(
            name: "Fill spreadsheet row",
            application: "Google Chrome",
            annotations: [],
            decisions: [],
            proposedActions: [
                .init(kind: "click", title: "Select the first cell", time: 1, image: 1, x: 15, y: 72.5, confidence: 0.96),
                .init(kind: "typeText", title: "Type X in cell A1", detail: "X", time: 2, image: 1, x: 250, y: 100, text: "X", confidence: 0.96)
            ]
        )
        let partiallyCaptured = Workflow(
            name: "My automation",
            transcript: "Put X in A1",
            steps: [WorkflowStep(kind: .click, title: "Click", time: 1, x: 130, y: 195)]
        )
        let repairedPartialCapture = WorkflowLearner.apply(partialResponse, to: partiallyCaptured, frames: [videoFrame])
        try expect(
            repairedPartialCapture.steps.filter { $0.kind == .click }.count == 1
                && repairedPartialCapture.steps.contains(where: { $0.kind == .typeText && $0.text == "X" }),
            "Qwen should fill a visibly missing action without duplicating the captured click"
        )

        let overlappingSpreadsheetResponse = LearnedWorkflowResponse(
            name: "Fill spreadsheet row",
            application: "Google Chrome",
            annotations: [],
            decisions: [],
            proposedActions: [
                .init(kind: "typeText", title: "Type X in cell A1", time: 1, image: 1, x: 50, y: 50, text: "X", confidence: 0.98),
                .init(kind: "typeText", title: "Type 2 in cell B1", time: 2, image: 1, x: 50, y: 50, text: "2", confidence: 0.98)
            ]
        )
        let repairedSpreadsheet = WorkflowLearner.apply(
            overlappingSpreadsheetResponse,
            to: Workflow(name: "My automation", transcript: "", steps: []),
            frames: [videoFrame]
        )
        try expect(
            repairedSpreadsheet.steps.map(\.kind) == [.openApp, .typeText, .keyPress, .typeText]
                && repairedSpreadsheet.steps[2].keyCode == 48
                && repairedSpreadsheet.steps[3].x == nil,
            "overlapping visual coordinates for distinct spreadsheet cells should become safe adjacent-cell navigation"
        )

        let lowConfidence = LearnedWorkflowResponse(
            name: nil,
            application: "Google Chrome",
            annotations: [],
            decisions: [],
            proposedActions: [.init(kind: "click", title: "Guess", time: 1, image: 1, x: 100, y: 100, confidence: 0.4)]
        )
        let rejectedDraft = WorkflowLearner.apply(lowConfidence, to: Workflow(name: "Empty", transcript: "", steps: []), frames: [videoFrame])
        try expect(rejectedDraft.steps.isEmpty, "low-confidence visual guesses must not become replay actions")

        let hallucinatedDecision = LearnedWorkflowResponse(
            name: nil,
            annotations: [],
            decisions: [.init(title: "Upload it publicly", detail: "Model-invented action", time: 1.5, requiresApproval: false, confidence: 1)]
        )
        let safelyLearned = WorkflowLearner.apply(hallucinatedDecision, to: workflow)
        try expect(safelyLearned.steps == workflow.steps, "visual learning must ignore model-invented decisions and preserve the captured action graph")

        let generic = LearnedWorkflowResponse(
            name: nil,
            annotations: [.init(stepID: click.id.uuidString, title: "Click", detail: nil, confidence: 1)],
            decisions: []
        )
        try expect(!WorkflowLearner.groundsGenericClicks(generic, in: workflow), "a generic Qwen click must trigger visual self-correction")
        try expect(WorkflowLearner.groundsGenericClicks(response, in: workflow), "a concrete visual click target should pass the grounding gate")

        let wrongTarget = LearnedWorkflowResponse(
            name: nil,
            annotations: [.init(stepID: click.id.uuidString, title: "Click Month selector", detail: nil, confidence: 1)],
            decisions: []
        )
        let confirmingTarget = LearnedWorkflowResponse(
            name: nil,
            annotations: [.init(stepID: click.id.uuidString, title: "Press the report download button", detail: nil, confidence: 1)],
            decisions: []
        )
        try expect(
            WorkflowLearner.consensusResponse(from: [wrongTarget, response], candidate: workflow) == nil,
            "two specific but conflicting click targets must not be trusted"
        )
        try expect(
            WorkflowLearner.consensusResponse(from: [wrongTarget, response, confirmingTarget], candidate: workflow) != nil,
            "an independently agreeing click description should establish visual consensus"
        )

        let label = WorkflowStep(kind: .typeText, title: "Enter the row label", detail: "Left spreadsheet column", time: 1, text: "X")
        let number = WorkflowStep(kind: .typeText, title: "Enter the row number", detail: "Adjacent numeric column", time: 2, text: "2")
        let pairWorkflow = Workflow(name: "Add spreadsheet row", transcript: "", steps: [label, number])
        let pairResponse = AgentPlanResponse(summary: "Use Z and 7 for this run", replacements: [
            AgentReplacement(stepID: label.id.uuidString, text: "Z", reason: "Requested label"),
            AgentReplacement(stepID: number.id.uuidString, text: "7", reason: "Requested number")
        ])
        let pairPlan = RunPlanner.plan(workflow: pairWorkflow, instruction: "Add Z and put 7 next to it", agentResponse: pairResponse)
        try expect(pairPlan.changes.count == 2 && pairPlan.steps[0].text == "Z" && pairPlan.steps[1].text == "7", "Qwen run planning should safely customize multiple typed values in one instruction")
    }

    private static func permissionStateCheck() throws {
        try expect(PermissionCenter.accessibilityStatus(isTrusted: false, hasRequested: false) == .unknown, "unrequested Accessibility should show Allow")
        try expect(PermissionCenter.accessibilityStatus(isTrusted: false, hasRequested: true) == .denied, "previously requested Accessibility should continue to show Open Settings")
        try expect(PermissionCenter.accessibilityStatus(isTrusted: true, hasRequested: true) == .granted, "trusted Accessibility should show Ready")
        try expect(PermissionCenter.Status.unknown.label == "Permission required", "unrequested permissions should explain why a feature is unavailable")
        try expect(PermissionCenter.Status.denied.label == "Permission needed", "denied permissions should remain actionable")

        let suiteName = "NeloaSelfTests.Permission.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw Failure(description: "could not create isolated permission defaults") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try expect(!PermissionCenter.hasRequestedAccessibility(in: defaults), "isolated Accessibility request state should start clear")
        PermissionCenter.markAccessibilityRequested(in: defaults)
        try expect(PermissionCenter.hasRequestedAccessibility(in: defaults), "Accessibility request state should persist using the same key read by refresh")
    }

    private static func recordingErrorCopyCheck() throws {
        let message = ScreenRecorder.RecordingError.screenPermissionRequired.localizedDescription
        try expect(message == "Neloa needs Screen Recording permission to see this workflow.", "screen recording denial should use actionable product language")
        try expect(!message.localizedCaseInsensitiveContains("TCC"), "screen recording denial should not expose macOS implementation jargon")
    }

    private static func displaySelectionCheck() throws {
        let displays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        ]
        try expect(
            ScreenRecorder.bestDisplayIndex(
                for: CGRect(x: 1500, y: 80, width: 1000, height: 700),
                displayFrames: displays
            ) == 1,
            "screen recording should follow the display containing the activated app"
        )
        try expect(
            ScreenRecorder.bestDisplayIndex(
                for: CGRect(x: 1300, y: 100, width: 600, height: 600),
                displayFrames: displays
            ) == 1,
            "screen recording should choose the display with the largest window overlap"
        )
        try expect(
            ScreenRecorder.bestDisplayIndex(
                for: CGRect(x: -900, y: -900, width: 200, height: 200),
                displayFrames: displays
            ) == nil,
            "offscreen windows should not retarget screen recording"
        )
    }

    private static func clickTargetMetadataCheck() throws {
        let candidates = [
            InteractionRecorder.WindowCandidate(
                frame: CGRect(x: 100, y: 100, width: 500, height: 400),
                layer: 0,
                processID: 101
            ),
            InteractionRecorder.WindowCandidate(
                frame: CGRect(x: 0, y: 0, width: 1200, height: 900),
                layer: 0,
                processID: 202
            )
        ]
        try expect(
            InteractionRecorder.topmostOwner(at: CGPoint(x: 250, y: 250), among: candidates) == 101,
            "click metadata should use the topmost window under the pointer instead of the previously active app"
        )
        try expect(
            InteractionRecorder.topmostOwner(at: CGPoint(x: 900, y: 700), among: candidates) == 202,
            "click metadata should fall through to the next visible window"
        )
        try expect(
            InteractionRecorder.topmostOwner(at: CGPoint(x: 1300, y: 900), among: candidates) == nil,
            "click metadata should not invent an app when the pointer is outside known windows"
        )

        let event = CaptureEvent(
            time: 1,
            kind: .click,
            x: 250,
            y: 250,
            target: "Sheet4",
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            displayID: 42
        )
        let workflow = WorkflowCompiler.compile(events: [event], transcript: "")
        try expect(workflow.steps.last?.bundleIdentifier == "com.google.Chrome", "compiled clicks should retain app identity")
        try expect(workflow.steps.last?.displayID == 42, "compiled clicks should retain monitor identity")
        try expect(workflow.steps.last?.target == "Sheet4", "compiled clicks should retain an accessibility target when the app exposes one")
        try expect(workflow.steps.last?.title == "Click Sheet4", "named controls should be shown instead of raw coordinates")
        try expect(workflow.steps.last?.displayKindLabel.contains("Google Chrome") == true, "review cards should show clicked app metadata")
    }

    private static func captureOptionCheck() throws {
        try expect(!TeachController.resolvedSystemAudio(screenEnabled: false, requested: true), "computer audio must be off without screen capture")
        try expect(TeachController.resolvedSystemAudio(screenEnabled: true, requested: true), "computer audio may be enabled with screen capture")
        try expect(!TeachController.resolvedSystemAudio(screenEnabled: true, requested: false), "computer audio should respect an explicit off choice")
    }

    private static func teachingTargetCheck() throws {
        try expect(
            TeachController.resolvedTeachingTarget("com.google.Chrome") == "com.google.Chrome",
            "teaching setup should preserve the selected target app"
        )
        try expect(TeachController.resolvedTeachingTarget("") == nil, "the manual app-switch choice should clear the target app")
    }

    private static func screenPermissionBranchCheck() throws {
        try expect(ScreenRecorder.hasScreenCaptureAccess(preflightGranted: true, requestGranted: false), "existing screen permission should allow recording")
        try expect(ScreenRecorder.hasScreenCaptureAccess(preflightGranted: false, requestGranted: true), "a newly granted screen request should continue recording")
        try expect(!ScreenRecorder.hasScreenCaptureAccess(preflightGranted: false, requestGranted: false), "a denied screen request should show recovery")
        let userDeclined = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        try expect(ScreenRecorder.isScreenPermissionError(userDeclined), "ScreenCaptureKit user-declined errors should map to product recovery")
        try expect(!ScreenRecorder.isScreenPermissionError(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)), "unrelated failures should keep their diagnostic meaning")
    }

    private static func appTourStructureCheck() throws {
        let steps = AppTourStep.all
        try expect(steps.count == 6, "the guided tour should cover all six core app areas")
        try expect(Set(steps.map(\.target)).count == steps.count, "each guided tour step should spotlight a unique control")
        try expect(steps.first?.target == .teachNavigation, "the guided tour should begin with Teach")
        try expect(steps.last?.target == .settingsNavigation, "the guided tour should finish with privacy and Settings")
    }

    private static func reviewFixtureLaunchCheck() throws {
        try expect(
            TeachController.shouldLoadReviewFixture(arguments: ["Neloa", "--ui-test-review"]),
            "the review fixture should be available to an explicitly launched UI test"
        )
        try expect(
            !TeachController.shouldLoadReviewFixture(arguments: ["Neloa"]),
            "a normal app launch must never substitute a canned movie for the user's recording"
        )
        try expect(
            TeachController.shouldLoadReviewFixture(
                arguments: ["Neloa"],
                environment: ["NELOA_UI_TEST_REVIEW": "1"]
            ),
            "a debug package should be able to opt into the review fixture without changing user defaults"
        )

        let suiteName = "NeloaSelfTests.ReviewFixture.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Failure(description: "could not create isolated defaults for the review fixture test")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "NeloaUITestReview")
        TeachController.clearLegacyReviewFixture(in: defaults)
        try expect(
            defaults.object(forKey: "NeloaUITestReview") == nil,
            "startup should remove the stale persistent review fixture preference"
        )
    }

    private static func reviewDraftLifetimeCheck() throws {
        let draft = Workflow(
            name: "Save transition fixture",
            transcript: "Type a value",
            steps: [WorkflowStep(kind: .typeText, title: "Enter value", time: 1, text: "Example")]
        )
        try expect(
            TeachReviewDraft.resolved(nil, fallback: draft) == draft,
            "the review binding should remain readable while a saved draft is cleared"
        )
        try expect(
            !TeachReviewDraft.acceptsUpdates(nil),
            "a departing review should ignore late child-view writes instead of recreating its draft"
        )
    }

    private static func reviewFixtureIsolationCheck() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaSaveTransitionTests")
            .appendingPathComponent("workflows.json")
            .path
        try expect(
            WorkflowStore.uiTestFileURL(environment: ["NELOA_UI_TEST_STORE_PATH": path])?.path == path,
            "the save-transition UI fixture should use an isolated workflow store"
        )
        try expect(
            WorkflowStore.uiTestFileURL(environment: [:]) == nil,
            "normal launches must not redirect the user's workflow store"
        )
    }

    private static func runPresentationCheck() throws {
        try expect(!RunPresentation.canPreview("   \n"), "blank rerun requests should not create an unchanged preview")
        try expect(RunPresentation.canPreview("Use August"), "a concrete rerun request should enable preview")

        let first = WorkflowStep(kind: .typeText, title: "Enter month", time: 1, text: "July", application: "Safari")
        let second = WorkflowStep(kind: .typeText, title: "Enter amount", time: 2, text: "$2,500", application: "Numbers")
        let plan = RunPlan(
            instruction: "Use August and $3,000",
            steps: [first, second],
            changes: [
                PlannedChange(stepID: first.id, before: "July", after: "August", reason: "Use August"),
                PlannedChange(stepID: second.id, before: "$2,500", after: "$3,000", reason: "Use $3,000")
            ],
            summary: "User requested explicit replacements"
        )
        try expect(
            RunPresentation.summary(for: plan) == "For this run, Neloa will use August and $3,000.",
            "the preview should use direct human copy instead of repeating model reasoning"
        )
        try expect(
            RunPresentation.apps(in: [first, second, first]) == ["Numbers", "Safari"],
            "the trust summary should show a sorted, deduplicated app list"
        )
        try expect(RunPlanner.isUnchangedInstruction("Run it the same way"), "the explicit original-run action should bypass model planning")
        try expect(RunPlanner.isUnchangedInstruction(" run the original \n"), "equivalent original-run copy should bypass model planning")
        try expect(!RunPlanner.isUnchangedInstruction("Use August"), "a real customization must still reach the planner")
    }

    private static func runPreflightCheck() throws {
        let open = WorkflowStep(
            kind: .openURL,
            title: "Open report",
            time: 0,
            text: "https://example.com/report",
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
        let coordinateClick = WorkflowStep(
            kind: .click,
            title: "Choose report",
            time: 1,
            x: 420,
            y: 260,
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
        let input = WorkflowStep(
            kind: .typeText,
            title: "Enter month",
            time: 2,
            text: "August",
            target: "Report month",
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
        let approval = WorkflowStep(
            kind: .approval,
            title: "Ask before downloading",
            time: 3,
            requiresApproval: true
        )
        let plan = RunPlan(
            instruction: "Use August",
            steps: [open, coordinateClick, input, approval],
            changes: [],
            summary: "Fixture"
        )

        let ready = RunPreflight.evaluate(
            plan: plan,
            accessibilityGranted: true,
            applicationAvailable: { _ in true }
        )
        try expect(ready.canRun, "a structurally valid workflow should pass preflight")
        try expect(ready.applications == ["Google Chrome"], "preflight should summarize required apps")
        try expect(ready.approvalCount == 1, "preflight should summarize approval pauses")
        try expect(
            ready.warnings.map(\.kind) == [.coordinateFallback],
            "coordinate-only actions should be visible warnings rather than hidden replay assumptions"
        )

        let denied = RunPreflight.evaluate(plan: plan, accessibilityGranted: false)
        try expect(
            denied.blockingIssues.contains(where: { $0.kind == .accessibility }),
            "missing control permission should block replay before the countdown"
        )

        let missingApp = RunPreflight.evaluate(
            plan: plan,
            accessibilityGranted: true,
            applicationAvailable: { _ in false }
        )
        try expect(
            missingApp.blockingIssues.contains(where: { $0.kind == .missingApplication }),
            "an unavailable captured app should block replay instead of sending events to the wrong app"
        )

        let invalidURL = WorkflowStep(kind: .openURL, title: "Open unsafe address", time: 0, text: "file:///tmp/report")
        let incompleteClick = WorkflowStep(kind: .click, title: "Unknown click", time: 1)
        let missingKey = WorkflowStep(kind: .keyPress, title: "Unknown key", time: 2)
        let emptyText = WorkflowStep(kind: .typeText, title: "Empty input", time: 3, text: "   ", target: "Amount")
        let invalidPlan = RunPlan(
            instruction: "Run",
            steps: [invalidURL, incompleteClick, missingKey, emptyText],
            changes: [],
            summary: "Invalid fixture"
        )
        let invalid = RunPreflight.evaluate(plan: invalidPlan, accessibilityGranted: true)
        try expect(!invalid.canRun, "malformed replay actions should fail preflight")
        try expect(invalid.blockingIssues.count == 4, "every malformed replay action should receive a specific blocker")

        let wrongSpreadsheet = WorkflowStep(
            kind: .selectSpreadsheetCell,
            title: "Go to a cell",
            time: 0,
            target: "row three",
            application: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )
        let spreadsheetReport = RunPreflight.evaluate(
            plan: RunPlan(instruction: "Run", steps: [wrongSpreadsheet], changes: [], summary: "Invalid cell"),
            accessibilityGranted: true
        )
        try expect(
            spreadsheetReport.blockingIssues.count == 2,
            "structured spreadsheet navigation should require both Chrome grounding and a valid cell address"
        )

        let empty = RunPreflight.evaluate(
            plan: RunPlan(instruction: "Run", steps: [], changes: [], summary: "Empty"),
            accessibilityGranted: true
        )
        try expect(!empty.canRun, "an empty automation should never appear runnable")
    }

    private static func reviewTimelineSelectionCheck() throws {
        let first = WorkflowStep(kind: .click, title: "Open report", time: 1)
        let second = WorkflowStep(kind: .typeText, title: "Enter amount", time: 3, text: "$500")
        let confirmation = WorkflowStep(kind: .approval, title: "Ask before sending", time: 3, requiresApproval: true)
        let steps = [first, second, confirmation]

        try expect(ReviewTimelineSelection.stepID(at: 0, in: steps) == first.id, "the review should begin with the first salient action selected")
        try expect(ReviewTimelineSelection.stepID(at: 2, in: steps) == first.id, "the selected action should remain active until the next timestamp")
        try expect(ReviewTimelineSelection.stepID(at: 3.1, in: steps) == confirmation.id, "equal timestamps should preserve the learned action order")
        try expect(ReviewTimelineSelection.stepID(at: 3, in: steps, preserving: second.id, at: 3) == second.id, "explicitly selecting an earlier action at a shared timestamp should keep that card highlighted")
        try expect(ReviewTimelineSelection.stepID(at: 2, in: steps, preserving: second.id, at: 2) == second.id, "a late action clamped to the end of a short video should remain explicitly selected")
        try expect(ReviewTimelineSelection.duration(videoDuration: 0, steps: steps) == 3.5, "steps should provide a review duration before the video reports its length")
        try expect(ReviewTimelineSelection.duration(videoDuration: 2, steps: steps) == 2, "the review timeline should clamp markers to the real video duration")
        try expect(ReviewTimelineSelection.duration(videoDuration: 10, steps: steps) == 10, "the review timeline should use the full recording duration")
    }

    private static func stepRepairCheck() throws {
        let originalID = UUID()
        let original = WorkflowStep(
            id: originalID,
            kind: .click,
            title: "Click the old download position",
            detail: "At 420, 260",
            time: 7.5,
            x: 420,
            y: 260,
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            requiresApproval: true,
            origin: .visual
        )
        let linkedInstruction = WorkflowStep(
            kind: .approval,
            title: "Ask before downloading",
            time: 7.4,
            requiresApproval: true,
            origin: .user,
            instructionScope: .thisAction,
            linkedStepID: originalID
        )
        let later = WorkflowStep(kind: .wait, title: "Wait for download", time: 9)

        try expect(StepRepairSupport.isEligible(original), "captured click actions should support focused re-teaching")
        try expect(StepRepairSupport.isRecommended(original), "a visually inferred position-only click should be recommended for repair")

        let events = [
            CaptureEvent(
                time: 0,
                kind: .appSwitch,
                application: "Google Chrome",
                bundleIdentifier: "com.google.Chrome"
            ),
            CaptureEvent(
                time: 1,
                kind: .click,
                x: 610,
                y: 315,
                target: "Download report",
                application: "Google Chrome",
                bundleIdentifier: "com.google.Chrome",
                displayID: 88
            )
        ]
        let repaired = try StepRepairSupport.candidate(replacing: original, from: events)
        try expect(repaired.id == originalID && repaired.time == 7.5, "repair must preserve action identity and timeline position")
        try expect(repaired.target == "Download report" && repaired.x == 610 && repaired.y == 315, "repair should capture a new semantic target with coordinate fallback")
        try expect(repaired.displayID == 88 && repaired.origin == .repaired, "repair should retain monitor metadata and remain visibly attributable")
        try expect(repaired.requiresApproval, "re-teaching must never remove an existing approval requirement")
        try expect(!StepRepairSupport.isRecommended(repaired), "a repaired semantic click should no longer be flagged as position-only")

        let replacedSteps = StepRepairSupport.replacing(
            stepID: originalID,
            with: repaired,
            in: [linkedInstruction, original, later]
        )
        try expect(replacedSteps.count == 3 && replacedSteps[1] == repaired, "repair should replace exactly one action without changing order")
        try expect(replacedSteps[0].linkedStepID == originalID, "preserving the action ID should keep linked user instructions intact")

        let beforeReadiness = RunPreflight.evaluate(
            plan: RunPlan(instruction: "Run", steps: [original], changes: [], summary: "Before repair"),
            accessibilityGranted: true,
            applicationAvailable: { _ in true }
        )
        let afterReadiness = RunPreflight.evaluate(
            plan: RunPlan(instruction: "Run", steps: [repaired], changes: [], summary: "After repair"),
            accessibilityGranted: true,
            applicationAvailable: { _ in true }
        )
        try expect(beforeReadiness.warnings.contains(where: { $0.kind == .coordinateFallback }), "the original position-only click should have a readiness warning")
        try expect(!afterReadiness.warnings.contains(where: { $0.kind == .coordinateFallback }), "a semantic repair should clear the position-only warning")

        let differences = StepRepairSupport.differences(from: original, to: repaired)
        try expect(differences.map(\.field) == ["Target", "Position"], "repair preview should show only the grounding details that changed")

        let inputID = UUID()
        let originalInput = WorkflowStep(
            id: inputID,
            kind: .typeText,
            title: "Enter old amount",
            time: 12,
            text: "$500",
            target: "Invoice amount",
            runVariable: false,
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )
        let inputEvents = [
            CaptureEvent(time: 1, kind: .click, x: 240, y: 360, application: "Google Chrome", bundleIdentifier: "com.google.Chrome", displayID: 17),
            CaptureEvent(time: 1.2, kind: .text, text: "$", target: "Invoice amount", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 1.3, kind: .text, text: "7", target: "Invoice amount", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 1.4, kind: .text, text: "5", target: "Invoice amount", application: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            CaptureEvent(time: 1.5, kind: .text, text: "0", target: "Invoice amount", application: "Google Chrome", bundleIdentifier: "com.google.Chrome")
        ]
        let repairedInput = try StepRepairSupport.candidate(replacing: originalInput, from: inputEvents)
        try expect(repairedInput.text == "$750", "focused input repair should merge the complete captured example value")
        try expect(repairedInput.x == 240 && repairedInput.y == 360 && repairedInput.displayID == 17, "focused input repair should retain the field click as a replay fallback")
        try expect(repairedInput.target == "Invoice amount" && repairedInput.runVariable == false, "input repair should retain semantic field identity and the original variable policy")

        let wrongAppEvents = [CaptureEvent(
            time: 1,
            kind: .click,
            x: 20,
            y: 20,
            target: "Download report",
            application: "Safari",
            bundleIdentifier: "com.apple.Safari"
        )]
        do {
            _ = try StepRepairSupport.candidate(replacing: original, from: wrongAppEvents)
            throw Failure(description: "a replacement captured in another app should be rejected")
        } catch let error as StepRepairError {
            try expect(
                error == .wrongApplication(expected: "Google Chrome", actual: "Safari"),
                "wrong-app repair should explain both expected and captured applications"
            )
        }

        let textOnlyEvents = [CaptureEvent(
            time: 1,
            kind: .text,
            text: "$750",
            target: "Invoice amount",
            application: "Google Chrome",
            bundleIdentifier: "com.google.Chrome"
        )]
        do {
            _ = try StepRepairSupport.candidate(replacing: original, from: textOnlyEvents)
            throw Failure(description: "capturing the wrong kind of action should be rejected")
        } catch let error as StepRepairError {
            try expect(error == .noMatchingAction, "wrong-kind repair should remain retryable without modifying the workflow")
        }

        let workflow = Workflow(name: "Repair persistence", transcript: "", steps: replacedSteps)
        let persisted = try JSONDecoder.neloa.decode(Workflow.self, from: JSONEncoder.neloa.encode(workflow))
        try expect(persisted.steps[1].origin == .repaired && persisted.steps[1].id == originalID, "repaired action attribution and identity should survive persistence")
    }

    private static func automationScheduleCheck() throws {
        let workflowID = UUID()
        let invalid = AutomationSchedule(
            repeatMode: .weekly,
            hour: 42,
            minute: -8,
            weekday: 12
        )
        let normalized = AutomationScheduleSupport.normalized(invalid)
        try expect(
            normalized.hour == 23 && normalized.minute == 0 && normalized.weekday == 7,
            "saved reminder components should be clamped to valid calendar values"
        )

        let weekdaySchedule = AutomationSchedule(
            repeatMode: .weekdays,
            hour: 8,
            minute: 30,
            weekday: nil
        )
        let weekdayDrafts = AutomationScheduleSupport.reminderDrafts(
            workflowID: workflowID,
            schedule: weekdaySchedule
        )
        try expect(weekdayDrafts.count == 5, "a weekday reminder should register one local trigger for each weekday")
        try expect(
            weekdayDrafts.compactMap(\.weekday) == [2, 3, 4, 5, 6],
            "weekday reminders should use Calendar's Monday-through-Friday values"
        )
        try expect(
            Set(weekdayDrafts.map(\.identifier)).count == 5,
            "each weekday reminder should have a stable unique identifier"
        )

        let daily = AutomationSchedule(repeatMode: .daily, hour: 9, minute: 15, weekday: 6)
        let dailyDrafts = AutomationScheduleSupport.reminderDrafts(workflowID: workflowID, schedule: daily)
        try expect(
            dailyDrafts.count == 1 && dailyDrafts[0].weekday == nil,
            "daily reminders should not accidentally inherit a saved weekday"
        )
        let disabled = AutomationSchedule(repeatMode: .daily, hour: 9, minute: 15, weekday: nil, isEnabled: false)
        try expect(
            AutomationScheduleSupport.reminderDrafts(workflowID: workflowID, schedule: disabled).isEmpty,
            "disabled reminders should register no notification triggers"
        )
        let removableIdentifiers = AutomationScheduleSupport.allIdentifiers(for: workflowID)
        try expect(
            Set(removableIdentifiers).isSuperset(of: weekdayDrafts.map(\.identifier))
                && Set(removableIdentifiers).isSuperset(of: dailyDrafts.map(\.identifier)),
            "removing a workflow should cover every reminder identifier it may have registered"
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let weekly = AutomationSchedule(repeatMode: .weekly, hour: 10, minute: 45, weekday: 2)
        try expect(
            AutomationScheduleSupport.summary(weekly, calendar: calendar, locale: calendar.locale ?? .current).contains("Monday"),
            "weekly reminder copy should name the selected day"
        )

        let workflow = Workflow(
            id: workflowID,
            name: "Scheduled report",
            transcript: "",
            steps: [],
            schedule: weekdaySchedule
        )
        let encoded = try JSONEncoder.neloa.encode(workflow)
        let decoded = try JSONDecoder.neloa.decode(Workflow.self, from: encoded)
        try expect(decoded.schedule == weekdaySchedule, "run reminders should survive workflow persistence")

        guard var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw Failure(description: "could not construct a legacy schedule fixture")
        }
        legacyObject.removeValue(forKey: "schedule")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder.neloa.decode(Workflow.self, from: legacyData)
        try expect(legacy.schedule == nil, "workflows saved before reminders existed should continue to decode")
    }

    private static func deepLinkCheck() throws {
        let workflowID = UUID()
        let url = NeloaDeepLink.runURL(workflowID: workflowID)
        try expect(
            url.absoluteString == "neloa://run/\(workflowID.uuidString)",
            "copied run links should use the registered Neloa URL scheme"
        )
        try expect(
            NeloaDeepLink.runWorkflowID(from: url) == workflowID,
            "a valid run link should route to exactly one saved workflow"
        )

        let unsafeOrMalformed = [
            "https://run/\(workflowID.uuidString)",
            "neloa://delete/\(workflowID.uuidString)",
            "neloa://run/not-a-workflow",
            "neloa://run/\(workflowID.uuidString)/extra",
            "neloa://run/\(workflowID.uuidString)?start=true",
            "neloa://run/\(workflowID.uuidString)#execute"
        ]
        for rawURL in unsafeOrMalformed {
            guard let malformedURL = URL(string: rawURL) else {
                throw Failure(description: "could not construct deep-link rejection fixture")
            }
            try expect(
                NeloaDeepLink.runWorkflowID(from: malformedURL) == nil,
                "run-link routing should reject unsupported or authority-expanding URL: \(rawURL)"
            )
        }
    }

    private static func automationRunQueueCheck() throws {
        let firstWorkflowID = UUID()
        let secondWorkflowID = UUID()
        let first = AutomationRunRequest(workflowID: firstWorkflowID, source: .reminder)
        let second = AutomationRunRequest(
            workflowID: secondWorkflowID,
            initialInstruction: "Use the new file at: /tmp/report.csv",
            source: .watchedFolder
        )
        let third = AutomationRunRequest(workflowID: firstWorkflowID, source: .shortcut)

        var queue = AutomationRunQueue()
        queue.enqueue(first)
        queue.enqueue(second)
        queue.enqueue(third)
        try expect(queue.current == first, "the first external run request should be reviewed first")
        try expect(queue.queued == [second, third], "later triggers should queue instead of replacing a visible run")

        queue.finishCurrent()
        try expect(queue.current == second && queue.queued == [third], "finishing a run sheet should reveal the next queued trigger")
        queue.removeRequests(for: firstWorkflowID)
        try expect(queue.current == second && queue.queued.isEmpty, "deleting a workflow should remove all of its queued run links and reminders")
        queue.finishCurrent()
        try expect(queue.current == nil, "the external run queue should become idle after every request is reviewed")
    }

    private static func fileTriggerCheck() throws {
        let fixtureFolder = WorkflowStore.uiTestFileTriggerFolder(environment: [
            "NELOA_UI_TEST_FILE_TRIGGER_FOLDER": "  /tmp/Neloa Trigger Fixture  "
        ])
        try expect(
            fixtureFolder?.path == "/tmp/Neloa Trigger Fixture",
            "the opt-in UI fixture should use a trimmed, isolated watched folder"
        )
        try expect(
            WorkflowStore.uiTestFileTriggerFolder(environment: [:]) == nil,
            "normal launches must never seed the watched-folder UI fixture"
        )

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaFileTriggerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let existingCSV = folder.appendingPathComponent("existing.csv")
        let hiddenCSV = folder.appendingPathComponent(".private.csv")
        let partialDownload = folder.appendingPathComponent("report.crdownload")
        try Data("account,total\nAcme,10\n".utf8).write(to: existingCSV)
        try Data("hidden".utf8).write(to: hiddenCSV)
        try Data("partial".utf8).write(to: partialDownload)

        let initial = try FileTriggerSupport.snapshot(folderURL: folder, kind: .csv)
        try expect(Set(initial.keys) == [existingCSV.standardizedFileURL], "watched folders should ignore hidden and partial-download files")
        try expect(FileTriggerSupport.accepts(existingCSV, kind: .spreadsheet), "spreadsheet triggers should accept CSV input")
        try expect(!FileTriggerSupport.accepts(existingCSV, kind: .pdf), "file-type filters should reject unrelated extensions")

        let arrivingPDF = folder.appendingPathComponent("August report.pdf")
        try Data("PDF fixture".utf8).write(to: arrivingPDF)
        let current = try FileTriggerSupport.snapshot(folderURL: folder, kind: .any)
        let newFiles = Set(current.keys).subtracting(initial.keys)
        try expect(newFiles.contains(arrivingPDF.standardizedFileURL), "a newly arrived regular file should be distinguishable from the initial folder snapshot")

        let instruction = FileTriggerSupport.instruction(for: arrivingPDF)
        try expect(
            instruction == "Use the new file at: \(arrivingPDF.standardizedFileURL.path)",
            "a folder event should produce one exact, inspectable local-path instruction"
        )

        let addressBar = WorkflowStep(
            kind: .typeText,
            title: "Enter address",
            time: 0,
            text: "https://example.com",
            target: "Address and search bar"
        )
        let fileInput = WorkflowStep(
            kind: .typeText,
            title: "Choose source file",
            detail: "Upload document path",
            time: 1,
            text: "/tmp/old-report.pdf",
            target: "Source file"
        )
        let secondFileInput = WorkflowStep(
            kind: .typeText,
            title: "Choose backup attachment",
            detail: "Upload backup file path",
            time: 2,
            text: "/tmp/backup.pdf",
            target: "Backup attachment"
        )
        let workflow = Workflow(
            name: "Import a report",
            transcript: "",
            steps: [addressBar, fileInput, secondFileInput],
            fileTrigger: AutomationFileTrigger(
                folderPath: folder.path,
                kind: .pdf,
                inputStepID: fileInput.id
            )
        )
        try expect(FileTriggerSupport.fileInputIndex(in: workflow) == 1, "watched folders should target the demonstrated file field, not a browser address")
        try expect(
            FileTriggerSupport.fileInputIndex(in: workflow, preferredStepID: secondFileInput.id) == 2,
            "a user-selected demonstrated file field should win when a workflow has several candidates"
        )

        let plan = RunPlanner.plan(workflow: workflow, instruction: instruction)
        try expect(plan.changes.count == 1, "an arriving file should create one reviewed value change")
        try expect(plan.changes[0].stepID == fileInput.id, "the watched-folder plan should update only the grounded file input")
        try expect(plan.changes[0].after == arrivingPDF.path, "the watched-folder plan should preserve the exact local path")
        try expect(plan.steps[1].text == arrivingPDF.path, "the prepared plan should use the new file without adding actions")
        try expect(plan.steps.map(\.id) == workflow.steps.map(\.id), "a file trigger must not expand the captured workflow authority")

        let outsideFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("outside-\(UUID().uuidString).pdf")
        try Data("outside".utf8).write(to: outsideFolder)
        defer { try? FileManager.default.removeItem(at: outsideFolder) }
        let outsidePlan = RunPlanner.plan(
            workflow: workflow,
            instruction: FileTriggerSupport.instruction(for: outsideFolder)
        )
        try expect(outsidePlan.changes.isEmpty, "a path outside the selected folder must not impersonate a watched-folder event")

        let wrongType = folder.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: wrongType)
        let wrongTypePlan = RunPlanner.plan(
            workflow: workflow,
            instruction: FileTriggerSupport.instruction(for: wrongType)
        )
        try expect(wrongTypePlan.changes.isEmpty, "a path outside the selected file type must not enter the reviewed plan")

        let linkedOutsideFile = folder.appendingPathComponent("linked-outside.pdf")
        try FileManager.default.createSymbolicLink(at: linkedOutsideFile, withDestinationURL: outsideFolder)
        let linkedOutsidePlan = RunPlanner.plan(
            workflow: workflow,
            instruction: FileTriggerSupport.instruction(for: linkedOutsideFile)
        )
        try expect(
            linkedOutsidePlan.changes.isEmpty,
            "a symbolic link must not escape the user-selected watched folder"
        )

        var disabledWorkflow = workflow
        disabledWorkflow.fileTrigger?.isEnabled = false
        try expect(
            RunPlanner.plan(workflow: disabledWorkflow, instruction: instruction).changes.isEmpty,
            "a disabled watched folder must not authorize its deterministic file substitution"
        )

        var missingFieldWorkflow = workflow
        missingFieldWorkflow.fileTrigger?.inputStepID = UUID()
        try expect(
            RunPlanner.plan(workflow: missingFieldWorkflow, instruction: instruction).changes.isEmpty,
            "a removed or re-taught selected file field must stop the trigger until the user chooses again"
        )

        let missingInstruction = FileTriggerSupport.instruction(for: folder.appendingPathComponent("missing.pdf"))
        let missingPlan = RunPlanner.plan(workflow: workflow, instruction: missingInstruction)
        try expect(missingPlan.changes.isEmpty, "a file removed before review should not be inserted into the run plan")

        let encoded = try JSONEncoder.neloa.encode(workflow)
        let decoded = try JSONDecoder.neloa.decode(Workflow.self, from: encoded)
        try expect(decoded.fileTrigger == workflow.fileTrigger, "watched-folder settings should survive workflow persistence")

        guard var legacyObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw Failure(description: "could not construct a legacy watched-folder fixture")
        }
        legacyObject.removeValue(forKey: "fileTrigger")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder.neloa.decode(Workflow.self, from: legacyData)
        try expect(legacy.fileTrigger == nil, "workflows saved before watched folders existed should continue to decode")
    }

    private static func workflowInstructionCheck() throws {
        let click = WorkflowStep(kind: .click, title: "Choose Share", time: 4)
        let input = WorkflowStep(kind: .typeText, title: "Enter amount", time: 8, text: "$500")
        let originalSteps = [click, input]

        guard let instruction = WorkflowInstructionSupport.makeStep(
            text: "  Always ask me before sharing.  ",
            time: 3.5,
            scope: .thisAction,
            existingSteps: originalSteps
        ) else {
            throw Failure(description: "a non-empty timeline instruction should be created")
        }

        try expect(instruction.isUserInstruction, "timeline instructions should remain visually and semantically distinct from inferred actions")
        try expect(instruction.text == "Always ask me before sharing.", "timeline instructions should trim accidental whitespace")
        try expect(instruction.linkedStepID == click.id, "this-action instructions should link to the nearest captured action")
        try expect(instruction.requiresApproval && instruction.kind == .approval, "explicit ask-before instructions should become approval gates")

        let inserted = WorkflowInstructionSupport.inserting(instruction, into: originalSteps)
        try expect(inserted.map(\.id) == [instruction.id, click.id, input.id], "a timeline instruction should be inserted chronologically before an action at or after its timestamp")
        try expect(ReviewTimelineSelection.stepID(at: 3.6, in: inserted) == instruction.id, "seeking to a user marker should select its sidebar card")

        guard let lateApproval = WorkflowInstructionSupport.makeStep(
            text: "Get my confirmation before sharing",
            time: 4.2,
            scope: .thisAction,
            existingSteps: originalSteps
        ) else {
            throw Failure(description: "common confirmation wording should create an instruction")
        }
        let safelyOrdered = WorkflowInstructionSupport.inserting(lateApproval, into: originalSteps)
        try expect(lateApproval.requiresApproval, "confirmation wording should conservatively become an approval gate")
        try expect(safelyOrdered.first?.id == lateApproval.id && safelyOrdered.dropFirst().first?.id == click.id, "a this-action approval added just after an action should still execute before that linked action")

        guard let globalInstruction = WorkflowInstructionSupport.makeStep(
            text: "Use only approved client values",
            time: 7,
            scope: .entireWorkflow,
            existingSteps: originalSteps
        ) else {
            throw Failure(description: "a workflow-wide instruction should be created")
        }
        let globallyOrdered = WorkflowInstructionSupport.inserting(globalInstruction, into: originalSteps)
        try expect(globallyOrdered.first?.id == globalInstruction.id, "an entire-workflow instruction should be reviewed before any captured action")
        try expect(AutomationRunner.requiresInstructionReview(globalInstruction), "general user instructions should become explicit review checkpoints instead of being silently skipped")
        try expect(AutomationRunner.approvalPrompt(for: globalInstruction) == nil, "general guidance should not be misrepresented as an enforced approval rule")

        let unlinked = WorkflowInstructionSupport.removing(stepID: click.id, from: inserted)
        let remainingInstruction = unlinked.first(where: { $0.id == instruction.id })
        try expect(remainingInstruction?.linkedStepID == nil && remainingInstruction?.detail.contains("Linked action removed") == true, "removing an action should visibly invalidate instructions linked to it")

        let workflow = Workflow(name: "Review", transcript: "", steps: inserted)
        let data = try JSONEncoder.neloa.encode(workflow)
        let decoded = try JSONDecoder.neloa.decode(Workflow.self, from: data)
        try expect(decoded.steps.first?.instructionScope == .thisAction, "instruction scope should survive workflow persistence")
        try expect(RunPlanner.prompt(workflow: workflow, instruction: "Use $750").contains("Always ask me before sharing."), "the local planner should receive explicit saved instructions")
        try expect(SkillExporter.markdown(for: workflow).contains("Explicit user instructions"), "portable skills should preserve user-authored timeline instructions")
        try expect(WorkflowInstructionSupport.makeStep(text: "   ", time: 1, scope: .fromHere, existingSteps: originalSteps) == nil, "blank timeline instructions should not be saved")
    }

    private static func diagnosticsPrivacyCheck() throws {
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let permissions = DiagnosticsPermissionSummary(
            screenRecording: "granted",
            clicksAndTyping: "denied",
            microphone: "unknown",
            speechRecognition: "granted",
            screenRestartNeeded: false
        )
        let app = DiagnosticsAppSummary(version: "0.2.18", build: "21", buildMode: "test")
        let system = DiagnosticsSystemSummary(
            operatingSystem: "Fixture macOS",
            architecture: "arm64",
            memoryGB: 16
        )

        func fixture(secret: String) -> (Workflow, AutomationRunReceipt, DiagnosticsModelSummary) {
            let approval = WorkflowStep(
                kind: .approval,
                title: "PRIVATE_APPROVAL_\(secret)",
                detail: "PRIVATE_APPROVAL_DETAIL_\(secret)",
                time: 3,
                text: "PRIVATE_APPROVAL_TEXT_\(secret)",
                target: "PRIVATE_APPROVAL_TARGET_\(secret)",
                application: "PRIVATE_APP_\(secret)",
                bundleIdentifier: "private.bundle.\(secret)",
                requiresApproval: true
            )
            let typed = WorkflowStep(
                kind: .typeText,
                title: "PRIVATE_INPUT_\(secret)",
                detail: "PRIVATE_INPUT_DETAIL_\(secret)",
                time: 2,
                x: secret == "ALPHA" ? 123.456 : 987.654,
                y: secret == "ALPHA" ? 234.567 : 876.543,
                text: "PRIVATE_TYPED_VALUE_\(secret)",
                target: "PRIVATE_FIELD_\(secret)",
                runVariable: true,
                application: "PRIVATE_APP_\(secret)",
                bundleIdentifier: "private.bundle.\(secret)",
                displayID: secret == "ALPHA" ? 41 : 99,
                origin: .visual
            )
            let web = WorkflowStep(
                kind: .openURL,
                title: "PRIVATE_WEB_\(secret)",
                time: 1,
                text: "https://private.example/\(secret)",
                application: "PRIVATE_BROWSER_\(secret)",
                bundleIdentifier: "private.browser.\(secret)"
            )
            let workflow = Workflow(
                id: UUID(),
                name: "PRIVATE_WORKFLOW_NAME_\(secret)",
                createdAt: Date(timeIntervalSince1970: secret == "ALPHA" ? 100 : 200),
                updatedAt: Date(timeIntervalSince1970: secret == "ALPHA" ? 300 : 400),
                transcript: "PRIVATE_TRANSCRIPT_\(secret)",
                narrationSegments: [NarrationSegment(
                    text: "PRIVATE_NARRATION_\(secret)",
                    time: 1,
                    duration: 2,
                    confidence: 0.91
                )],
                recordingPath: "/Users/private/\(secret)/recording.mp4",
                narrationPath: "/Users/private/\(secret)/narration.m4a",
                steps: [web, typed, approval],
                defaultInstruction: "PRIVATE_DEFAULT_\(secret)",
                schedule: AutomationSchedule(repeatMode: .weekly, hour: 9, minute: 37, weekday: 4),
                fileTrigger: AutomationFileTrigger(
                    folderPath: "/Users/private/\(secret)/Incoming",
                    kind: .pdf,
                    inputStepID: typed.id
                ),
                semanticVersion: 3
            )
            let change = PlannedChange(
                stepID: typed.id,
                before: "PRIVATE_BEFORE_\(secret)",
                after: "PRIVATE_AFTER_\(secret)",
                reason: "PRIVATE_REASON_\(secret)"
            )
            let receipt = AutomationRunReceipt(
                id: UUID(),
                workflowID: workflow.id,
                workflowName: workflow.name,
                startedAt: Date(timeIntervalSince1970: secret == "ALPHA" ? 500 : 600),
                finishedAt: Date(timeIntervalSince1970: secret == "ALPHA" ? 700 : 800),
                instruction: "PRIVATE_RUN_INSTRUCTION_\(secret)",
                summary: "PRIVATE_RUN_SUMMARY_\(secret)",
                changes: [change],
                stepCount: 3,
                status: .failed,
                message: "PRIVATE_FAILURE_MESSAGE_\(secret)"
            )
            let model = DiagnosticsModelSummary.sanitized(
                tier: .balanced4Bit,
                status: .failed("PRIVATE_MODEL_FAILURE_\(secret)"),
                runtimeBundled: true,
                installed: true,
                eligible: true
            )
            return (workflow, receipt, model)
        }

        func report(for secret: String) -> DiagnosticsReport {
            let fixture = fixture(secret: secret)
            return DiagnosticsReportBuilder.make(
                workflows: [fixture.0],
                activities: [fixture.1],
                storeIssuePresent: true,
                permissions: permissions,
                model: fixture.2,
                generatedAt: generatedAt,
                app: app,
                system: system,
                readiness: { workflow in
                    RunPreflight.evaluate(
                        plan: RunPlan(
                            instruction: "",
                            steps: workflow.steps,
                            changes: [],
                            summary: ""
                        ),
                        accessibilityGranted: false,
                        applicationAvailable: { _ in false }
                    )
                }
            )
        }

        let alpha = report(for: "ALPHA")
        let beta = report(for: "BETA")
        try expect(
            alpha == beta,
            "diagnostics should depend on safe structure and health, not user-authored content or identifiers"
        )
        let data = try alpha.jsonData()
        let betaData = try beta.jsonData()
        try expect(
            data == betaData,
            "equivalent safe structure should produce byte-for-byte identical diagnostics despite different secrets"
        )
        let text = String(decoding: data, as: UTF8.self)
        let forbidden = [
            "PRIVATE_", "/Users/private", "private.example", "private.bundle",
            "123.456", "234.567", "987.654", "876.543"
        ]
        for value in forbidden {
            try expect(!text.contains(value), "diagnostics must not contain redacted value: \(value)")
        }
        try expect(!text.contains("workflowID") && !text.contains("stepID"), "diagnostics must not serialize automation or action identifiers")
        try expect(
            text.range(
                of: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#,
                options: .regularExpression
            ) == nil,
            "diagnostics must not serialize UUID-shaped automation, action, or run identifiers"
        )
        try expect(alpha.workflows.first?.stepKinds == ["approval": 1, "openURL": 1, "typeText": 1], "diagnostics should retain safe action-type counts")
        try expect(alpha.workflows.first?.readiness.blockerCount == 3, "diagnostics should retain readiness blocker counts without their private wording")
        try expect(alpha.activity == DiagnosticsActivitySummary(total: 1, completed: 0, stopped: 0, failed: 1), "diagnostics should retain aggregate run outcomes only")
        let decoded = try JSONDecoder.neloa.decode(DiagnosticsReport.self, from: data)
        try expect(decoded == alpha, "the redacted diagnostics report should round-trip as portable JSON")
    }

    private static func automationTemplateCheck() throws {
        func fixture(_ secret: String) -> Workflow {
            let input = WorkflowStep(
                kind: .typeText,
                title: "PRIVATE_INPUT_\(secret)",
                detail: "PRIVATE_DETAIL_\(secret)",
                time: 4,
                x: secret == "ALPHA" ? 100 : 900,
                y: secret == "ALPHA" ? 200 : 800,
                text: "PRIVATE_TYPED_\(secret)",
                target: "PRIVATE_TARGET_\(secret)",
                runVariable: true,
                application: "PRIVATE_APP_\(secret)",
                bundleIdentifier: "private.bundle.\(secret)",
                displayID: secret == "ALPHA" ? 41 : 99,
                origin: .visual
            )
            return Workflow(
                name: "PRIVATE_WORKFLOW_\(secret)",
                createdAt: Date(timeIntervalSince1970: secret == "ALPHA" ? 100 : 900),
                updatedAt: Date(timeIntervalSince1970: secret == "ALPHA" ? 200 : 800),
                transcript: "PRIVATE_TRANSCRIPT_\(secret)",
                narrationSegments: [NarrationSegment(text: "PRIVATE_NARRATION_\(secret)", time: 1, duration: 2)],
                recordingPath: "/Users/private/\(secret)/recording.mp4",
                narrationPath: "/Users/private/\(secret)/narration.m4a",
                steps: [
                    WorkflowStep(
                        kind: .openApp,
                        title: "PRIVATE_OPEN_APP_\(secret)",
                        time: 0,
                        application: "PRIVATE_APP_\(secret)",
                        bundleIdentifier: "private.bundle.\(secret)"
                    ),
                    WorkflowStep(
                        kind: .openURL,
                        title: "PRIVATE_URL_\(secret)",
                        time: 1,
                        text: "https://private.example/\(secret)",
                        application: "PRIVATE_BROWSER_\(secret)",
                        bundleIdentifier: "private.browser.\(secret)"
                    ),
                    WorkflowStep(
                        kind: .click,
                        title: "PRIVATE_CLICK_\(secret)",
                        time: 2,
                        x: 321,
                        y: 654,
                        target: "PRIVATE_CONTROL_\(secret)",
                        application: "PRIVATE_APP_\(secret)",
                        bundleIdentifier: "private.bundle.\(secret)",
                        requiresApproval: true
                    ),
                    input,
                    WorkflowStep(
                        kind: .keyPress,
                        title: "PRIVATE_KEY_\(secret)",
                        time: 5,
                        keyCode: secret == "ALPHA" ? 8 : 9,
                        flags: secret == "ALPHA" ? 1_048_576 : 2_097_152,
                        application: "PRIVATE_APP_\(secret)"
                    ),
                    WorkflowStep(
                        kind: .approval,
                        title: "PRIVATE_APPROVAL_\(secret)",
                        detail: "PRIVATE_RULE_\(secret)",
                        time: 6,
                        text: "PRIVATE_INSTRUCTION_\(secret)",
                        requiresApproval: true,
                        origin: .user,
                        instructionScope: .fromHere,
                        linkedStepID: input.id
                    )
                ],
                defaultInstruction: "PRIVATE_DEFAULT_\(secret)",
                schedule: AutomationSchedule(repeatMode: .weekly, hour: 9, minute: 30, weekday: 3),
                fileTrigger: AutomationFileTrigger(
                    folderPath: "/Users/private/\(secret)/Incoming",
                    kind: .pdf,
                    inputStepID: input.id
                ),
                semanticVersion: 3
            )
        }

        let alpha = try AutomationTemplateCodec.make(
            workflow: fixture("ALPHA"),
            publicTitle: "Monthly report starter"
        )
        let beta = try AutomationTemplateCodec.make(
            workflow: fixture("BETA"),
            publicTitle: "  Monthly report starter  "
        )
        let alphaData = try alpha.jsonData()
        let betaData = try beta.jsonData()
        try expect(alpha == beta && alphaData == betaData, "templates with the same public title and action shape must be independent of private workflow data")
        try expect(alpha.steps.count == 6, "a reusable template should preserve the action sequence")
        try expect(alpha.flexibleInputCount == 1, "a reusable template should preserve which input can change each run")
        try expect(alpha.approvalCount == 2, "a reusable template should preserve explicit and action-level approval gates")
        try expect(alpha.steps[2].label == "Choose a control after approval", "template outlines should explain approval placement without leaking the control label")

        let text = String(decoding: alphaData, as: UTF8.self)
        let forbidden = [
            "PRIVATE_", "private.example", "private.bundle", "/Users/private",
            "recordingPath", "narrationPath", "transcript", "application", "bundleIdentifier",
            "target", "keyCode", "flags", "displayID", "instructionScope", "linkedStepID",
            "createdAt", "updatedAt", "schedule", "fileTrigger"
        ]
        for value in forbidden {
            try expect(!text.contains(value), "a reusable template must not serialize private or executable field: \(value)")
        }
        let decoded = try AutomationTemplateCodec.decode(alphaData)
        try expect(decoded == alpha, "a privacy-safe reusable template should round-trip through its public JSON format")

        let temporaryFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaTemplateCodec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryFolder) }
        let savedTemplate = temporaryFolder.appendingPathComponent("safe.neloa-template.json")
        try alphaData.write(to: savedTemplate, options: .atomic)
        let readTemplate = try AutomationTemplateCodec.read(from: savedTemplate)
        try expect(
            readTemplate == alpha,
            "the file importer should preserve a valid safe template"
        )
        try expect(
            AutomationTemplateCodec.sanitizedSlug("  Monthly Report: Starter!  ") == "monthly-report-starter",
            "template filenames should use a portable public-title slug"
        )

        func expectDecodeFailure(
            _ data: Data,
            equals expected: AutomationTemplateError,
            _ message: String
        ) throws {
            do {
                _ = try AutomationTemplateCodec.decode(data)
                throw Failure(description: message)
            } catch let error as AutomationTemplateError {
                try expect(error == expected, "\(message); got \(error)")
            }
        }

        var unknownRoot = try JSONSerialization.jsonObject(with: alphaData) as? [String: Any] ?? [:]
        unknownRoot["recordingPath"] = "/Users/private/recording.mp4"
        try expectDecodeFailure(
            JSONSerialization.data(withJSONObject: unknownRoot),
            equals: .unexpectedFields("the file"),
            "imports must reject unknown top-level fields instead of silently ignoring possible private data"
        )

        var unknownStep = try JSONSerialization.jsonObject(with: alphaData) as? [String: Any] ?? [:]
        var stepObjects = unknownStep["steps"] as? [[String: Any]] ?? []
        stepObjects[0]["text"] = "PRIVATE_TYPED_VALUE"
        unknownStep["steps"] = stepObjects
        try expectDecodeFailure(
            JSONSerialization.data(withJSONObject: unknownStep),
            equals: .unexpectedFields("guide step 1"),
            "imports must reject executable text hidden in a guide step"
        )

        let oversized = Data(repeating: 0x20, count: AutomationTemplate.maximumFileSize + 1)
        try expectDecodeFailure(oversized, equals: .tooLarge, "imports must reject oversized template files before parsing")
        let oversizedFile = temporaryFolder.appendingPathComponent("oversized.neloa-template.json")
        try oversized.write(to: oversizedFile, options: .atomic)
        do {
            _ = try AutomationTemplateCodec.read(from: oversizedFile)
            throw Failure(description: "the file importer must reject oversized templates before reading their contents")
        } catch let error as AutomationTemplateError {
            try expect(error == .tooLarge, "the file importer should report its size boundary")
        }

        let deceptiveTitle = AutomationTemplate(
            title: "Quarterly report\u{202E}nosj.exe",
            steps: [AutomationTemplateStep(kind: .openApp, isFlexibleInput: false, requiresApproval: false)]
        )
        do {
            _ = try deceptiveTitle.jsonData()
            throw Failure(description: "template titles must reject invisible or bidirectional formatting controls")
        } catch let error as AutomationTemplateError {
            try expect(error == .invalidTitle, "unsafe title formatting should use the public-title validation error")
        }

        let invalidFlexible = AutomationTemplate(
            title: "Invalid flexible step",
            steps: [AutomationTemplateStep(kind: .click, isFlexibleInput: true, requiresApproval: false)]
        )
        do {
            _ = try invalidFlexible.jsonData()
            throw Failure(description: "only typed inputs may be marked flexible")
        } catch let error as AutomationTemplateError {
            try expect(error == .invalidStep(1), "invalid flexible-input metadata should identify its guide step")
        }

        let approvalOnly = AutomationTemplate(
            title: "Approval only",
            steps: [AutomationTemplateStep(kind: .approval, isFlexibleInput: false, requiresApproval: true)]
        )
        do {
            _ = try approvalOnly.jsonData()
            throw Failure(description: "a template without a demonstrable task should be rejected")
        } catch let error as AutomationTemplateError {
            try expect(error == .noDemonstrableActions, "a template should not consist only of metadata or approval markers")
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
}
