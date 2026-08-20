import AppKit
import SwiftUI

struct FileTriggerEditor: View {
    let workflow: Workflow

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var fileTriggers: FileTriggerCenter
    @State private var folderPath: String
    @State private var kind: AutomationFileTriggerKind
    @State private var inputStepID: UUID?
    @State private var isEnabled: Bool

    init(workflow: Workflow) {
        self.workflow = workflow
        let trigger = workflow.fileTrigger ?? AutomationFileTrigger(
            folderPath: "",
            kind: .any
        )
        _folderPath = State(initialValue: trigger.folderPath)
        _kind = State(initialValue: trigger.kind)
        _inputStepID = State(initialValue: trigger.inputStepID
            ?? FileTriggerSupport.fileInputCandidates(in: workflow).first?.stepID)
        _isEnabled = State(initialValue: trigger.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 50, height: 50)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watched folder")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(workflow.name)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("When a new or replaced file is ready")
                    .font(.system(size: 16, weight: .semibold))

                Button(action: chooseFolder) {
                    HStack(spacing: 10) {
                        Image(systemName: folderPath.isEmpty ? "folder.badge.plus" : "folder.fill")
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folderPath.isEmpty ? "Choose a folder" : URL(fileURLWithPath: folderPath).lastPathComponent)
                                .font(.system(size: 14, weight: .semibold))
                            if !folderPath.isEmpty {
                                Text(folderPath)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18)))
                .disabled(!isEnabled)

                Picker("File type", selection: $kind) {
                    ForEach(AutomationFileTriggerKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .disabled(!isEnabled)

                if !fileInputCandidates.isEmpty {
                    Picker("Fill this field", selection: $inputStepID) {
                        ForEach(fileInputCandidates) { candidate in
                            Text(candidate.label).tag(Optional(candidate.stepID))
                        }
                    }
                    .disabled(!isEnabled)
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 15))

            if fileInputCandidates.isEmpty {
                Label {
                    Text("This automation has no flexible file field yet. Re-teach the file-path entry before enabling a watched folder.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.orange)
                .padding(14)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Prepares a run; never starts one", systemImage: "hand.raised.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Neloa watches only this folder while the app is open. After a new or replaced matching file finishes copying, Neloa fills its local path into the demonstrated file field and opens the normal change preview. You still review and start the run yourself.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))
            }

            if let issue = fileTriggers.issues[workflow.id] {
                Label(issue, systemImage: "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(13)
                    .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            }

            Spacer(minLength: 0)

            HStack {
                if workflow.fileTrigger != nil {
                    Button("Remove watched folder", role: .destructive) { removeTrigger() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save watched folder") { saveTrigger() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(26)
    }

    private var canSave: Bool {
        if !isEnabled { return workflow.fileTrigger != nil }
        return !folderPath.isEmpty && inputStepID != nil
    }

    private var fileInputCandidates: [FileTriggerSupport.FileInputCandidate] {
        FileTriggerSupport.fileInputCandidates(in: workflow)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder for \(workflow.name)"
        panel.prompt = "Watch Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if !folderPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.standardizedFileURL.path
    }

    private func saveTrigger() {
        var updated = workflow
        updated.fileTrigger = AutomationFileTrigger(
            folderPath: folderPath,
            kind: kind,
            inputStepID: inputStepID,
            isEnabled: isEnabled
        )
        store.save(updated)
        fileTriggers.reconcile(workflows: store.workflows)
        dismiss()
    }

    private func removeTrigger() {
        fileTriggers.remove(workflowID: workflow.id)
        var updated = workflow
        updated.fileTrigger = nil
        store.save(updated)
        dismiss()
    }
}
