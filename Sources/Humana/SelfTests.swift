import Foundation

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
        let data = try JSONEncoder.humana.encode(workflow)
        let decoded = try JSONDecoder.humana.decode(Workflow.self, from: data)
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
        let data = try JSONEncoder.humana.encode(receipt)
        let decoded = try JSONDecoder.humana.decode(AutomationRunReceipt.self, from: data)
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }
}
