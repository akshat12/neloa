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
        try localModelDiscoveryCheck()
        try permissionStateCheck()
        try appearanceCheck()
        try recordingErrorCopyCheck()
        try captureOptionCheck()
        try screenPermissionBranchCheck()
        try appTourStructureCheck()
        try reviewTimelineSelectionCheck()
        try workflowInstructionCheck()
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
        try expect(agent.status.contains("Apple Intelligence"), "Apple on-device agent should handle the test plan; status was: \(agent.status)")
        try expect(plan.steps.first?.text == "August", "on-device agent should replace June with August; got text=\(plan.steps.first?.text ?? "nil"), summary=\(plan.summary), changes=\(plan.changes.map { "\($0.before)->\($0.after)" })")
        try expect(plan.changes.count == 1, "on-device agent should report one reviewed change; got \(plan.changes.count)")

        let teacher = TeachController()
        teacher.setScreenCaptureEnabled(false)
        try expect(!teacher.captureScreen && !teacher.captureSystemAudio, "turning off screen capture should also turn off computer audio")
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

    private static func localModelDiscoveryCheck() throws {
        let response = #"{"models":[{"name":"qwen3-vl:4b"},{"model":"llama3.2:latest"}]}"#
        let installed = try LocalAgentService.installedModelNames(from: Data(response.utf8))
        try expect(LocalAgentService.containsModel("qwen3-vl:4b", in: installed), "exact Ollama model tags should be discovered")
        try expect(LocalAgentService.containsModel("llama3.2", in: installed), "Ollama's implicit latest tag should be discovered")
        try expect(!LocalAgentService.containsModel("missing:1b", in: installed), "unavailable Ollama models should be reported as missing")
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
