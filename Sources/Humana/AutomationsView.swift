import SwiftUI

struct AutomationsView: View {
    @EnvironmentObject private var store: WorkflowStore
    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: "Automations", subtitle: "Run a saved workflow as-is, or ask for a small one-time change.")
            if store.workflows.isEmpty {
                ContentUnavailableView("No automations yet", systemImage: "square.grid.2x2", description: Text("Teach your first workflow and it will appear here."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    List(store.workflows, selection: $selectedID) { workflow in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(workflow.name).fontWeight(.semibold)
                            Text("\(workflow.steps.count) steps · \(workflow.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7).tag(workflow.id)
                    }
                    .frame(minWidth: 270, idealWidth: 320)
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
}

private struct AutomationDetail: View {
    let workflow: Workflow
    @EnvironmentObject private var store: WorkflowStore
    @State private var showingRun = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workflow.name).font(.title2.bold())
                    Text("Taught \(workflow.createdAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Delete automation", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                Button("Run automation") { showingRun = true }.buttonStyle(.borderedProminent)
            }
            Divider()
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(workflow.steps.enumerated()), id: \.element.id) { index, step in
                        StepRow(number: index + 1, step: step)
                    }
                }
            }
        }
        .padding(.leading, 20)
        .sheet(isPresented: $showingRun) { RunView(workflow: workflow).frame(minWidth: 760, minHeight: 650) }
        .alert("Delete \(workflow.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { store.delete(workflow) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The saved workflow will be removed.") }
    }
}
