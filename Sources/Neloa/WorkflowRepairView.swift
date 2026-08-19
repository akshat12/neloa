import SwiftUI

struct WorkflowRepairView: View {
    let original: Workflow

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkflowStore
    @State private var draft: Workflow
    @State private var repairingStep: WorkflowStep?

    init(workflow: Workflow) {
        original = workflow
        _draft = State(initialValue: workflow)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageHeader(
                title: "Review & repair",
                subtitle: "Re-teach one fragile action without rebuilding the rest of \(original.name)."
            )

            if recommendedRepairCount > 0 {
                Label(
                    "\(recommendedRepairCount) action\(recommendedRepairCount == 1 ? "" : "s") would benefit from a stronger target.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.09), in: Capsule())
            }

            WorkflowReviewView(
                workflow: $draft,
                repairAction: { repairingStep = $0 }
            )

            HStack {
                Text("Only reviewed changes are written to this automation.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save review changes") {
                    store.save(draft)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft == original)
            }
        }
        .padding(28)
        .sheet(item: $repairingStep) { step in
            StepRepairCaptureView(original: step) { replacement in
                draft.steps = StepRepairSupport.replacing(
                    stepID: step.id,
                    with: replacement,
                    in: draft.steps
                )
            }
        }
    }

    private var recommendedRepairCount: Int {
        draft.steps.filter(StepRepairSupport.isRecommended).count
    }
}

private struct StepRepairCaptureView: View {
    let original: WorkflowStep
    let save: (WorkflowStep) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = StepRepairController()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "scope")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Re-teach one action")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("The rest of the workflow stays unchanged.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current action")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                StepRow(number: 1, total: 1, step: original)
            }

            phaseContent

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(width: 680, height: 610)
        .interactiveDismissDisabled(controller.phase == .recording)
        .onDisappear { controller.cancel() }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch controller.phase {
        case .ready:
            VStack(alignment: .leading, spacing: 13) {
                Label("How focused capture works", systemImage: "record.circle")
                    .font(.system(size: 16, weight: .semibold))
                Text(instructionText)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("Neloa will bring the original app forward. Perform only this action, return to Neloa, and stop the capture.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button {
                        Task { await controller.start(for: original) }
                    } label: {
                        Label("Start focused capture", systemImage: "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .repairPanel()

        case .recording:
            VStack(alignment: .leading, spacing: 14) {
                Label("Capturing the replacement", systemImage: "record.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
                Text(instructionText)
                    .font(.system(size: 15, weight: .medium))
                Text("When finished, return to Neloa and choose Stop capture. Interactions with Neloa itself are excluded.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel capture") { controller.tryAgain() }
                    Spacer()
                    Button {
                        controller.stop(for: original)
                    } label: {
                        Label("Stop capture", systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .repairPanel(color: .red)

        case .preview:
            if let candidate = controller.candidate {
                VStack(alignment: .leading, spacing: 13) {
                    Label("Review the replacement", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    StepRow(number: 1, total: 1, step: candidate)
                    differenceList(candidate)
                    Label(
                        "The action ID, timeline position, variable setting, and any approval requirement are preserved.",
                        systemImage: "lock.shield"
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    HStack {
                        Button("Capture again") { controller.tryAgain() }
                        Spacer()
                        Button("Use this replacement") {
                            save(candidate)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .repairPanel()
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 13) {
                Label("Replacement not captured", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 14))
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Try again") { controller.tryAgain() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .repairPanel(color: .orange)
        }
    }

    private var instructionText: String {
        switch original.kind {
        case .openApp:
            "Bring \(original.application ?? "the original app") to the front."
        case .click:
            "Click the intended control once."
        case .typeText:
            "Click the intended field and type the complete example value once."
        case .keyPress:
            "Press the intended key or keyboard shortcut once."
        default:
            "Perform the replacement action once."
        }
    }

    @ViewBuilder
    private func differenceList(_ replacement: WorkflowStep) -> some View {
        let differences = StepRepairSupport.differences(from: original, to: replacement)
        if differences.isEmpty {
            Label("The action was captured again with the same visible details.", systemImage: "equal.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(differences) { difference in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(difference.field)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 76, alignment: .leading)
                        Text(difference.before)
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(Color.accentColor)
                        Text(difference.after)
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 13))
                }
            }
        }
    }
}

private extension View {
    func repairPanel(color: Color = .accentColor) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.18)))
    }
}

