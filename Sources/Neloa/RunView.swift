import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeader(title: "Again, but…", subtitle: "\(workflow.name) · Say only what should be different this time.")
                Button { runner.stop(); dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }

            VStack(spacing: 9) {
                HStack(spacing: 10) {
                    TextField("Use July instead of June, change the amount to $750…", text: $instruction)
                        .textFieldStyle(.plain).font(.system(size: 17))
                        .onSubmit { prepare() }
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
                    .disabled(voiceBusy)
                    Button(agent.isPlanning ? "Planning…" : "Preview changes") { prepare() }
                        .buttonStyle(.borderedProminent).disabled(agent.isPlanning)
                }
                .padding(.horizontal, 15).padding(.vertical, 12)
                .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 15))

                HStack {
                    Label(agent.status, systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("Nothing in this plan leaves your Mac")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()

            if let plan {
                runPlan(plan)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "quote.bubble").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                    Text("“What should I change this time?”").font(.title3.bold())
                    Text("You can type or answer by voice. Neloa will show the exact changes before touching anything.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                    Button("Run it the same way") {
                        instruction = "Run it the same way"
                        prepare()
                    }
                    Text("For example: “Replace June with July” or “Use an amount of $750.”")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .interactiveDismissDisabled(isRunning)
        .onAppear { runner.reset() }
        .onDisappear { runner.reset() }
        .onChange(of: runner.state) { _, newState in handleStateChange(newState) }
    }

    @ViewBuilder
    private func runPlan(_ plan: RunPlan) -> some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("This run").font(.headline)
                Text(plan.summary).foregroundStyle(.secondary)
                if cannotApplyRequestedChange(plan) {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("I couldn’t safely make that change", systemImage: "questionmark.bubble.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.orange)
                        Text("Tell me which saved value should change and what it should become. Neloa won’t quietly run the original.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
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
                                Task { await toggleVoice() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(14)
                    .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
                } else if plan.changes.isEmpty {
                    Label("No workflow values changed", systemImage: "equal.circle").foregroundStyle(.secondary)
                } else {
                    ForEach(plan.changes) { change in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(change.before).strikethrough().foregroundStyle(.secondary)
                            Label(change.after, systemImage: "arrow.turn.down.right").fontWeight(.semibold)
                            Text(change.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(13).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("After this run").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Picker("After this run", selection: $disposition) {
                            ForEach(RunDisposition.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .labelsHidden().pickerStyle(.segmented)
                        Text(disposition.help).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }
                Spacer()
                stateControls(plan)
            }
            .padding(.trailing, 14).frame(minWidth: 280, idealWidth: 320)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        StepRow(number: index + 1, step: step, isCurrent: runner.currentStepID == step.id)
                    }
                }
            }
            .padding(.leading, 14).frame(minWidth: 360)
        }
    }

    @ViewBuilder
    private func stateControls(_ plan: RunPlan) -> some View {
        switch runner.state {
        case .idle, .stopped:
            if cannotApplyRequestedChange(plan) && !allowOriginalRun {
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
            VStack(spacing: 10) {
                Label("Run stopped", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                Text(message).font(.caption)
                Button("Try again") { runner.run(plan) }
            }.frame(maxWidth: .infinity)
        }
    }

    private var isRunning: Bool {
        switch runner.state {
        case .countdown, .running, .waitingForApproval, .waitingForInstruction: true
        default: false
        }
    }

    private func prepare() {
        runner.reset()
        disposition = .useOnce
        allowOriginalRun = false
        clarificationQuestion = nil
        Task {
            let nextPlan = await agent.makePlan(workflow: workflow, instruction: instruction)
            plan = nextPlan
            if cannotApplyRequestedChange(nextPlan) {
                let question = "Which saved value should I replace, and what should it become?"
                clarificationQuestion = question
                voice.speak(question)
            }
        }
    }

    private func toggleVoice() async {
        if voice.isListening {
            _ = voice.stop()
            instruction = voice.transcript
            prepare()
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
