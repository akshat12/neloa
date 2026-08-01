import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: WorkflowStore
    @State private var showingClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageHeader(title: "Activity", subtitle: "A private receipt for every automation Humana runs.")
                Spacer()
                if !store.activities.isEmpty {
                    Button("Clear history") { showingClearConfirmation = true }
                }
            }

            if store.activities.isEmpty {
                ContentUnavailableView(
                    "No runs yet",
                    systemImage: "checkmark.seal",
                    description: Text("Completed runs and their one-time changes will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.activities) { receipt in
                            ActivityCard(receipt: receipt)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(32)
        .alert("Clear activity history?", isPresented: $showingClearConfirmation) {
            Button("Clear", role: .destructive) { store.clearActivity() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes local run receipts. Your automations will not be affected.")
        }
    }
}

private struct ActivityCard: View {
    let receipt: AutomationRunReceipt

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: statusIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 42, height: 42)
                .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(receipt.workflowName).font(.headline)
                    Spacer()
                    Text(receipt.finishedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(receipt.instruction.isEmpty ? "Ran without changes" : receipt.instruction)
                    .font(.system(size: 14, weight: .medium))
                if !receipt.changes.isEmpty {
                    Text(receipt.changes.map { "\($0.before) → \($0.after)" }.joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(Color.accentColor)
                }
                HStack(spacing: 12) {
                    Label(statusLabel, systemImage: statusIcon)
                    Text("\(receipt.stepCount) steps")
                    Text(receipt.summary)
                }
                .font(.caption).foregroundStyle(.secondary)
                if let message = receipt.message, !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(Color.secondary.opacity(0.15)))
    }

    private var statusIcon: String {
        switch receipt.status {
        case .completed: "checkmark.circle.fill"
        case .stopped: "stop.circle.fill"
        case .failed: "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch receipt.status {
        case .completed: .green
        case .stopped: .orange
        case .failed: .red
        }
    }

    private var statusLabel: String { receipt.status.rawValue.capitalized }
}
