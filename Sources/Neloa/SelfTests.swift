import AppKit
import Foundation
import ScreenCaptureKit

enum SelfTests {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run() throws {
        try compilationCheck()
        try spokenOnlyCheck()
        try replacementCheck()
        try amountCheck()
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
        try captureOptionCheck()
        try screenPermissionBranchCheck()
        try appTourStructureCheck()
        try reviewTimelineSelectionCheck()
        try workflowInstructionCheck()
        try agentResponseSafetyCheck()
        try staleEvidenceCleanupCheck()
        try qwenResponseRepairCheck()
    }

    private static func appearanceCheck() throws {
        try expect(AppAppearance.resolve("system") == .system, "system appearance should round-trip")
        try expect(AppAppearance.resolve("light") == .light, "light appearance should round-trip")
        try expect(AppAppearance.resolve("dark") == .dark, "dark appearance should round-trip")
        try expect(AppAppearance.resolve("unexpected") == .system, "unknown appearance should safely follow the system")
    }

    @MainActor
    static func agentSmokeTest() async throws {
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
        let learnedClickTitle = learned.steps[0].title.lowercased()
        try expect(
            learnedClickTitle.contains("download") || learnedClickTitle.contains("report"),
            "Qwen should identify the report action from image pixels without OCR hints; got \(learned.steps[0].title)"
        )
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
    }

    private static func staleEvidenceCleanupCheck() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaEvidence-SelfTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        WorkflowEvidenceExtractor.purgeStaleTemporaryEvidence(olderThan: 0)
        try expect(!FileManager.default.fileExists(atPath: directory.path), "stale temporary screenshots should be removed")
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

        let unrelated = "This is not a structured response"
        try expect(
            QwenResponseSupport.jsonData(from: unrelated, topLevelKeys: ["summary", "replacements"]) == nil,
            "unstructured model output must still be rejected"
        )
    }

    private static func serializationCheck() throws {
        let workflow = Workflow(name: "Serializable", transcript: "hello", steps: [])
        let data = try JSONEncoder.neloa.encode(workflow)
        let decoded = try JSONDecoder.neloa.decode(Workflow.self, from: data)
        try expect(decoded.id == workflow.id && decoded.name == workflow.name && decoded.transcript == workflow.transcript && decoded.steps == workflow.steps, "saved workflows should round-trip")
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

    private static func captureOptionCheck() throws {
        try expect(!TeachController.resolvedSystemAudio(screenEnabled: false, requested: true), "computer audio must be off without screen capture")
        try expect(TeachController.resolvedSystemAudio(screenEnabled: true, requested: true), "computer audio may be enabled with screen capture")
        try expect(!TeachController.resolvedSystemAudio(screenEnabled: true, requested: false), "computer audio should respect an explicit off choice")
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
}
