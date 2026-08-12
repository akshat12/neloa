import AppKit
import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var store: WorkflowStore
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "My automations", subtitle: "Run one again — or tell Neloa what should be different this time.")
            if store.workflows.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "repeat.circle.fill").font(.system(size: 50)).foregroundStyle(Color.accentColor)
                    Text("Your repeatable work lives here").font(.title2.bold())
                    Text("Teach Neloa one real task. The next time, you’ll only need to say what changed.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 470)
                    Button("Teach my first automation") {
                        NotificationCenter.default.post(name: .showNeloaTeach, object: nil)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    VStack(spacing: 4) {
                        Text("Good first examples: a monthly report, an invoice, or a form you fill repeatedly.")
                        Text("Usually takes 2–5 minutes · Your recording stays on this Mac")
                    }
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.workflows.count == 1, let workflow = store.workflows.first {
                AutomationDetail(workflow: workflow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(store.workflows, selection: $selectedID) { workflow in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workflow.name).fontWeight(.semibold)
                            Text(lastRunDescription(for: workflow))
                                .font(.system(size: 14)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                        .tag(workflow.id)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(workflow.name), \(lastRunDescription(for: workflow))")
                    }
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320)
                    .onAppear { selectedID = selectedID ?? store.workflows.first?.id }

                    if let workflow = store.workflows.first(where: { $0.id == selectedID }) ?? store.workflows.first {
                        AutomationDetail(workflow: workflow)
                            .id(workflow.id)
                            .frame(minWidth: 560)
                    }
                }
            }
        }
        .padding(32)
    }

    private func lastRunDescription(for workflow: Workflow) -> String {
        guard let run = store.activities.first(where: { $0.workflowID == workflow.id }) else {
            return "Ready to run · Updated \(workflow.updatedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        let status = run.status == .completed ? "Finished" : run.status.rawValue.capitalized
        return "Last ran \(run.finishedAt.formatted(date: .abbreviated, time: .omitted)) · \(status)"
    }
}

private struct AutomationDetail: View {
    let workflow: Workflow
    @EnvironmentObject private var store: WorkflowStore
    @State private var showingRun = false
    @State private var confirmDelete = false
    @State private var exportMessage: String?
    @State private var showHowItWorks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workflow.name).font(.title2.bold())
                    Text("Created \(workflow.createdAt.formatted(date: .abbreviated, time: .shortened)) · Updated \(workflow.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Export automation…") { exportSkill() }
                    Button("Delete automation", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("More automation actions")
                Button("Run again…") { showingRun = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(NeloaPalette.accent)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
            if !flexibleInputs.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Label("Flexible each run", systemImage: "slider.horizontal.3")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("Say a new value when you run again")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 7) {
                        ForEach(Array(flexibleInputs.prefix(5).enumerated()), id: \.element.id) { index, step in
                            Text("\(inputName(step, index: index)): \(step.text?.isEmpty == false ? step.text! : "Not set")")
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.09), in: Capsule())
                                .accessibilityLabel("\(inputName(step, index: index)), current value \(step.text?.isEmpty == false ? step.text! : "not set")")
                        }
                    }
                }
                .padding(14)
                .background(.quaternary.opacity(0.34), in: RoundedRectangle(cornerRadius: 14))
            }

            if !approvalRules.isEmpty {
                detailCard(title: "When Neloa asks", icon: "hand.raised.fill") {
                    ForEach(approvalRules) { step in
                        Text(step.title).font(.system(size: 15))
                    }
                }
            }

            if !userInstructions.isEmpty {
                detailCard(title: "Instructions you added", icon: "text.bubble.fill") {
                    ForEach(userInstructions) { step in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.text ?? step.title).font(.system(size: 15, weight: .medium))
                            Text("\((step.instructionScope ?? .thisAction).label) · \(step.time.clockString)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !appsUsed.isEmpty {
                detailCard(title: "Apps used", icon: "square.grid.2x2") {
                    Text(appsUsed.joined(separator: " · "))
                        .font(.system(size: 15))
                }
            }

            DisclosureGroup("How it works · \(workflow.steps.count) steps", isExpanded: $showHowItWorks) {
                LazyVStack(spacing: 9) {
                    ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                        StepRow(number: index + 1, total: workflow.steps.count, step: step)
                    }
                }
                .padding(.top, 10)
            }
            .font(.system(size: 15, weight: .semibold))
            .accessibilityLabel("How it works, \(workflow.steps.count) steps")
                }
            }
        }
        .padding(.leading, 20)
        .sheet(isPresented: $showingRun) {
            RunView(workflow: workflow)
                .frame(minWidth: 760, idealWidth: 940, minHeight: 650, idealHeight: 760)
                .presentationSizing(.fitted)
        }
        .alert("Delete \(workflow.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.delete(workflow) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the automation and its saved teaching recordings from this Mac. This cannot be undone.")
        }
        .alert("Export", isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    private var flexibleInputs: [WorkflowStep] { workflow.steps.filter(\.isRunVariable) }
    private var approvalRules: [WorkflowStep] { workflow.steps.filter { $0.kind == .approval || $0.requiresApproval } }
    private var userInstructions: [WorkflowStep] { workflow.steps.filter(\.isUserInstruction) }
    private var appsUsed: [String] {
        Array(Set(workflow.steps.compactMap(\.application).filter { !$0.isEmpty })).sorted()
    }

    private func inputName(_ step: WorkflowStep, index: Int) -> String {
        if let target = step.target, !target.isEmpty { return target }
        let value = step.text ?? ""
        let context = "\(step.title) \(step.detail)".lowercased()
        if context.contains("recipient") || value.contains("@") { return "Recipient" }
        if context.contains("file") || value.range(of: #"\.[a-zA-Z0-9]{2,5}$"#, options: .regularExpression) != nil { return "File" }
        if context.contains("amount") || value.contains("$") || value.range(of: #"\b[0-9]+(?:\.[0-9]{2})\b"#, options: .regularExpression) != nil { return "Amount" }
        if value.contains("%") { return "Percentage" }
        if context.contains("date") || context.contains("month") || value.range(of: #"(?i)\b(january|february|march|april|may|june|july|august|september|october|november|december)\b"#, options: .regularExpression) != nil { return "Date" }
        return "Text input \(index + 1)"
    }

    private func detailCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
    }

    private func exportSkill() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(SkillExporter.slug(workflow.name)).md"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SkillExporter.markdown(for: workflow).write(to: url, atomically: true, encoding: .utf8)
            exportMessage = "The automation was exported to \(url.lastPathComponent)."
        } catch {
            exportMessage = "The skill could not be exported: \(error.localizedDescription)"
        }
    }
}
