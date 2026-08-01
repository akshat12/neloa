import SwiftUI

private enum RunDisposition: String, CaseIterable, Identifiable {
    case useOnce = "Use once"
    case saveVariant = "Save variant"
    case updateDefault = "Update default"

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
                        Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 30)).foregroundStyle(voice.isListening ? .red : Color.accentColor)
                    }
                    .buttonStyle(.plain).disabled(voiceBusy)
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
                    Text("You can type or answer by voice. Humana will show the exact changes before touching anything.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 460)
                    Button("Run it the same way") {
                        instruction = "Run it the same way"
                        prepare()
                    }
                    HStack(spacing: 8) {
                        suggestion("Use next month")
                        suggestion("Change the amount")
                        suggestion("Save as a draft")
                    }
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
                if plan.changes.isEmpty {
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
            Button("Run this version") {
                runStartedAt = Date()
                loggedTerminalState = false
                appliedDisposition = false
                runner.run(plan)
            }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            Label("You can stop at any time. Approval steps always pause.", systemImage: "hand.raised")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
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
        case .countdown, .running, .waitingForApproval: true
        default: false
        }
    }

    private func prepare() {
        runner.reset()
        disposition = .useOnce
        Task { plan = await agent.makePlan(workflow: workflow, instruction: instruction) }
    }

    private func toggleVoice() async {
        if voice.isListening {
            _ = voice.stop()
            instruction = voice.transcript
            prepare()
        } else {
            voiceBusy = true
            voice.speak("What should I change this time?")
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

    private func suggestion(_ value: String) -> some View {
        Button(value) {
            instruction = value
            prepare()
        }
        .buttonStyle(.bordered).controlSize(.small)
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
