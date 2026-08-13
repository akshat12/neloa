import SwiftUI

enum RunPresentation {
    nonisolated static func canPreview(_ instruction: String) -> Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static func summary(for plan: RunPlan) -> String {
        guard !plan.changes.isEmpty else { return "Neloa will use the saved workflow without changing its values." }
        if let selection = plan.steps.first(where: { $0.kind == .selectSpreadsheetCell }),
           let target = selection.target,
           let value = plan.steps.first(where: { $0.kind == .typeText && $0.target == target })?.text {
            return "For this run, Neloa will set \(target) to \(value)."
        }
        let values = plan.changes.map(\.after)
        let joined: String
        if values.count == 1 {
            joined = values[0]
        } else if values.count == 2 {
            joined = "\(values[0]) and \(values[1])"
        } else {
            joined = values.dropLast().joined(separator: ", ") + ", and " + (values.last ?? "")
        }
        return "For this run, Neloa will use \(joined)."
    }

    nonisolated static func apps(in steps: [WorkflowStep]) -> [String] {
        Array(Set(steps.compactMap(\.application).filter { !$0.isEmpty })).sorted()
    }
}

private enum RunDisposition: String, CaseIterable, Identifiable {
    case useOnce = "Just this time"
    case saveVariant = "Save another version"
    case updateDefault = "Use from now on"

    var id: String { rawValue }

    var help: String {
        switch self {
        case .useOnce: "Keep this change temporary."
        case .saveVariant: "Save a separate version for later."
        case .updateDefault: "Make this the new normal for this automation."
        }
    }
}

struct RunView: View {
    let workflow: Workflow
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var agent: LocalAgentService
    @EnvironmentObject private var runner: AutomationRunner
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var permissions: PermissionCenter
    @StateObject private var voice = VoiceService()
    @State private var instruction = ""
    @State private var plan: RunPlan?
    @State private var voiceBusy = false
    @State private var disposition: RunDisposition = .useOnce
    @State private var runStartedAt: Date?
    @State private var loggedTerminalState = false
    @State private var appliedDisposition = false
    @State private var allowOriginalRun = false
    @State private var clarificationQuestion: String?
    @State private var planningTask: Task<Void, Never>?
    @State private var planningRequestID: UUID?
    @State private var requestBeganByVoice = false
    @State private var restartWarningStepCount: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                PageHeader(title: "What should change this time?", subtitle: workflow.name)
                Button {
                    cancelPlanning()
                    runner.stop()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 10) {
                TextField(
                    "For example: Use August 2026 and change the amount to $3,000",
                    text: $instruction,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .lineLimit(2...3)
                .disabled(isPreparingPlan)
                .frame(minHeight: 54, maxHeight: 82, alignment: .topLeading)
                .accessibilityLabel("What should change this time?")
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))

                HStack(spacing: 10) {
                    Button {
                        Task { await toggleVoice() }
                    } label: {
                        Label(
                            voice.isListening ? "Finish speaking" : "Tell Neloa what changed",
                            systemImage: voice.isListening ? "stop.circle.fill" : "mic.fill"
                        )
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(voice.isListening ? .red : Color.accentColor)
                    .disabled(voiceBusy || isPreparingPlan)

                    Spacer()

                    if isPreparingPlan {
                        Button("Cancel") { cancelPlanning() }
                            .buttonStyle(.bordered)
                    }
                    Button(isPreparingPlan ? "Preparing preview…" : "Preview changes") {
                        prepare(startedByVoice: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!RunPresentation.canPreview(instruction) || isPreparingPlan)
                }

                HStack {
                    Label(agent.status, systemImage: "lock.fill")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Nothing in this plan leaves your Mac")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 15))

            Divider()

            if isPreparingPlan {
                planningView
            } else if let plan {
                runPlan(plan)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "quote.bubble").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                    Text("Change only what is different").font(.title3.bold())
                    Text("Type or answer by voice. Neloa will show the exact changes before touching anything.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                    Button("Run it the same way") {
                        instruction = "Run it the same way"
                        prepare(startedByVoice: false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .tint(NeloaPalette.accent)
        .interactiveDismissDisabled(isRunning)
        .onAppear { runner.reset() }
        .onDisappear {
            cancelPlanning()
            runner.reset()
        }
        .onChange(of: runner.state) { _, newState in handleStateChange(newState) }
    }

    private var planningView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing your preview privately on this Mac")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("This can take a few seconds while Neloa checks the saved values and safety rules.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Cancel planning") { cancelPlanning() }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preparing your preview privately on this Mac")
    }

    @ViewBuilder
    private func runPlan(_ plan: RunPlan) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    ScrollView {
                        planDetails(plan)
                    }
                    stateControls(plan)
                }
                .frame(minWidth: 360, idealWidth: 400, maxWidth: 440)

                Divider()

                planSteps(plan)
                    .frame(minWidth: 420)
            }
            .frame(minWidth: 820)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    planOverview(plan)
                    Divider()
                    planStepsContent(plan)
                }
                .padding(.trailing, 6)
            }
        }
    }

    private func planOverview(_ plan: RunPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            planDetails(plan)
            stateControls(plan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func planDetails(_ plan: RunPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This run")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(RunPresentation.summary(for: plan))
                .font(.system(size: 16, weight: .medium))

            if cannotApplyRequestedChange(plan) {
                clarificationCard(plan)
            } else if plan.changes.isEmpty {
                Label("No saved values will change", systemImage: "equal.circle")
                    .foregroundStyle(.secondary)
            } else {
                changeCards(plan.changes)
                dispositionPicker
            }

            trustSummary(plan)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clarificationCard(_ plan: RunPlan) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("I couldn’t safely make that change", systemImage: "questionmark.bubble.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.orange)
                .accessibilityAddTraits(.isHeader)
            Text("Tell me which saved value should change and what it should become. Neloa won’t quietly run the original.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            if let clarificationQuestion {
                Text(clarificationQuestion)
                    .font(.system(size: 15, weight: .medium))
            }
            HStack {
                Button("Edit my request") {
                    self.plan = nil
                    allowOriginalRun = false
                }
                Button("Answer by voice") {
                    requestBeganByVoice = true
                    Task { await toggleVoice() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
    }

    private func changeCards(_ changes: [PlannedChange]) -> some View {
        VStack(spacing: 9) {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 7) {
                    Text(change.before)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Label(change.after, systemImage: "arrow.turn.down.right")
                        .fontWeight(.semibold)
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Change \(change.before) to \(change.after)")
                .help(change.reason)
            }
        }
    }

    private var dispositionPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("After this run")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Picker("After this run", selection: $disposition) {
                ForEach(RunDisposition.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            Text(disposition.help)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func trustSummary(_ plan: RunPlan) -> some View {
        let apps = RunPresentation.apps(in: plan.steps)
        let approvals = plan.steps.filter { $0.kind == .approval || $0.requiresApproval }.count
        return VStack(alignment: .leading, spacing: 8) {
            Text("Ready to run")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Label(
                apps.isEmpty ? "No app switches captured" : "Will use \(apps.joined(separator: ", "))",
                systemImage: "square.grid.2x2"
            )
            Label(
                permissions.accessibility == .granted ? "Control permission is ready" : "Control permission is required",
                systemImage: permissions.accessibility == .granted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(permissions.accessibility == .granted ? Color.secondary : Color.red)
            Label(
                approvals == 0 ? "No approval pauses were taught" : "Will pause for \(approvals) approval\(approvals == 1 ? "" : "s")",
                systemImage: "hand.raised.fill"
            )
            Label(
                "\(plan.changes.count) requested change\(plan.changes.count == 1 ? "" : "s")",
                systemImage: "arrow.left.arrow.right"
            )
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }

    private func planSteps(_ plan: RunPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps Neloa will take")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ScrollView { planStepRows(plan) }
        }
    }

    private func planStepsContent(_ plan: RunPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Steps Neloa will take")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            planStepRows(plan)
        }
    }

    private func planStepRows(_ plan: RunPlan) -> some View {
        LazyVStack(spacing: 8) {
            ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                StepRow(
                    number: index + 1,
                    total: plan.steps.count,
                    step: step,
                    isCurrent: runner.currentStepID == step.id,
                    isCompleted: runner.completedStepIDs.contains(step.id)
                )
            }
        }
    }

    @ViewBuilder
    private func stateControls(_ plan: RunPlan) -> some View {
        switch runner.state {
        case .idle, .stopped:
            if let restartWarningStepCount {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Restarting will repeat completed work", systemImage: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("\(restartWarningStepCount) step\(restartWarningStepCount == 1 ? " has" : "s have") already completed. Restarting begins again at step 1.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Cancel restart") { self.restartWarningStepCount = nil }
                        Button("Restart from step 1") {
                            self.restartWarningStepCount = nil
                            startRun(plan)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(13)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            } else if cannotApplyRequestedChange(plan) && !allowOriginalRun {
                Button("Run the original instead") {
                    allowOriginalRun = true
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                Text("This is a separate choice because your requested change was not applied.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                Button(plan.changes.isEmpty ? "Run the original" : "Run this time") {
                    startRun(plan)
                }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }
            Label("You can stop at any time. Approval steps always pause.", systemImage: "hand.raised")
                .font(.system(size: 14)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        case .countdown(let seconds):
            VStack(spacing: 8) {
                Text("Starting in \(seconds)…").font(.title2.bold())
                Button("Cancel", role: .cancel) { runner.stop() }
            }.frame(maxWidth: .infinity)
        case .running(let index):
            VStack(spacing: 8) {
                ProgressView("Running step \(index + 1) of \(plan.steps.count)")
                Button("Stop", role: .destructive) { runner.stop() }
            }.frame(maxWidth: .infinity)
        case .waitingForApproval(let question):
            VStack(alignment: .leading, spacing: 10) {
                Label("Your approval is needed", systemImage: "hand.raised.fill").font(.headline).foregroundStyle(.orange)
                Text(question)
                HStack {
                    Button("Stop", role: .destructive) { runner.deny() }
                    Button("Approve & continue") { runner.approve() }.buttonStyle(.borderedProminent)
                }
            }
            .padding().background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
        case .waitingForInstruction(let instruction):
            VStack(alignment: .leading, spacing: 10) {
                Label("Review your instruction", systemImage: "text.bubble.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(instruction)
                    .font(.system(size: 15, weight: .medium))
                Text("Neloa has not changed the captured actions automatically. Stop if this instruction is not satisfied; continuing runs the recorded actions from this point.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Stop", role: .destructive) { runner.deny() }
                    Button("Continue with recorded workflow") { runner.approve() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding().background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
        case .completed:
            VStack(spacing: 10) {
                Label("Run complete", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
                Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Label("Run stopped", systemImage: "xmark.octagon.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message).font(.system(size: 13))
                if !runner.completedStepIDs.isEmpty {
                    Text("\(runner.completedStepIDs.count) step\(runner.completedStepIDs.count == 1 ? " completed" : "s completed") before the problem. Restarting may repeat those actions.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                }
                Button("Review before restarting") {
                    restartWarningStepCount = runner.completedStepIDs.count
                    runner.reset(preservingCompletedSteps: true)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isRunning: Bool {
        switch runner.state {
        case .countdown, .running, .waitingForApproval, .waitingForInstruction: true
        default: false
        }
    }

    private var isPreparingPlan: Bool { planningRequestID != nil }

    private func prepare(startedByVoice: Bool) {
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInstruction.isEmpty else { return }
        cancelPlanning()
        runner.reset()
        disposition = .useOnce
        allowOriginalRun = false
        clarificationQuestion = nil
        restartWarningStepCount = nil
        requestBeganByVoice = startedByVoice
        instruction = cleanInstruction
        let requestID = UUID()
        planningRequestID = requestID
        planningTask = Task {
            let nextPlan = await agent.makePlan(workflow: workflow, instruction: cleanInstruction)
            guard !Task.isCancelled, planningRequestID == requestID else { return }
            plan = nextPlan
            planningRequestID = nil
            planningTask = nil
            if cannotApplyRequestedChange(nextPlan) {
                let question = "Which saved value should I replace, and what should it become?"
                clarificationQuestion = question
                if requestBeganByVoice { voice.speak(question) }
            }
        }
    }

    private func cancelPlanning() {
        planningTask?.cancel()
        planningTask = nil
        planningRequestID = nil
        if agent.isPlanning { agent.status = "Planning cancelled" }
    }

    private func toggleVoice() async {
        if voice.isListening {
            _ = voice.stop()
            instruction = voice.transcript
            prepare(startedByVoice: true)
        } else {
            voiceBusy = true
            voice.speak(clarificationQuestion ?? "What should I change this time?")
            try? await Task.sleep(for: .seconds(1.6))
            do { _ = try await voice.start() } catch { agent.status = error.localizedDescription }
            voiceBusy = false
        }
    }

    private func saveVariant(_ plan: RunPlan) {
        var variant = workflow
        variant.id = UUID()
        variant.name = "\(workflow.name) — \(instruction)"
        variant.createdAt = Date()
        variant.steps = plan.steps
        variant.defaultInstruction = instruction
        store.save(variant)
    }

    private func updateDefault(_ plan: RunPlan) {
        var updated = workflow
        updated.steps = plan.steps
        updated.defaultInstruction = instruction
        store.save(updated)
    }

    private func cannotApplyRequestedChange(_ plan: RunPlan) -> Bool {
        let clean = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        return !clean.isEmpty && clean.lowercased() != "run it the same way" && plan.changes.isEmpty
    }

    private func startRun(_ plan: RunPlan) {
        runStartedAt = Date()
        loggedTerminalState = false
        appliedDisposition = false
        runner.run(plan)
    }

    private func handleStateChange(_ state: AutomationRunner.State) {
        guard let plan, let startedAt = runStartedAt, !loggedTerminalState else { return }
        switch state {
        case .completed:
            applyDispositionIfNeeded(plan)
            record(plan: plan, startedAt: startedAt, status: .completed, message: nil)
        case .stopped:
            record(plan: plan, startedAt: startedAt, status: .stopped, message: "Stopped by the user")
        case .failed(let message):
            record(plan: plan, startedAt: startedAt, status: .failed, message: message)
        default:
            break
        }
    }

    private func applyDispositionIfNeeded(_ plan: RunPlan) {
        guard !appliedDisposition else { return }
        appliedDisposition = true
        switch disposition {
        case .useOnce: break
        case .saveVariant: saveVariant(plan)
        case .updateDefault: updateDefault(plan)
        }
    }

    private func record(plan: RunPlan, startedAt: Date, status: AutomationRunStatus, message: String?) {
        loggedTerminalState = true
        store.record(AutomationRunReceipt(
            workflowID: workflow.id,
            workflowName: workflow.name,
            startedAt: startedAt,
            instruction: instruction,
            summary: plan.summary,
            changes: plan.changes,
            stepCount: plan.steps.count,
            status: status,
            message: message
        ))
    }
}
