import SwiftUI

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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeader(title: "Run \(workflow.name)", subtitle: "Tell Humana what is different this time—or leave it unchanged.")
                Button { runner.stop(); dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("For example: Use July instead of June", text: $instruction)
                    .textFieldStyle(.roundedBorder).font(.system(size: 16))
                    .onSubmit { prepare() }
                Button {
                    Task { await toggleVoice() }
                } label: {
                    Image(systemName: voice.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 28)).foregroundStyle(voice.isListening ? .red : Color.accentColor)
                }
                .buttonStyle(.plain).disabled(voiceBusy)
                Button(agent.isPlanning ? "Planning…" : "Preview run") { prepare() }
                    .buttonStyle(.borderedProminent).disabled(agent.isPlanning)
            }

            HStack {
                Circle().fill(agent.status.contains("unavailable") ? .orange : .green).frame(width: 8, height: 8)
                Text(agent.status).font(.caption).foregroundStyle(.secondary)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(28)
        .interactiveDismissDisabled(isRunning)
        .onDisappear { runner.stop() }
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
            Button("Run supervised") { runner.run(plan) }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            if !plan.changes.isEmpty {
                Button("Save as a new automation") { saveVariant(plan) }.frame(maxWidth: .infinity)
            }
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
}
