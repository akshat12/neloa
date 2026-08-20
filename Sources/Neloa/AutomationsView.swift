import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutomationsView: View {
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var runRouter: AutomationRunRouter
    @EnvironmentObject private var teacher: TeachController
    @State private var selectedID: UUID?
    @State private var templateImport: AutomationTemplateImportDraft?
    @State private var templateImportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 16) {
                PageHeader(title: "My automations", subtitle: "Run one again — or tell Neloa what should be different this time.")
                Spacer()
                Button {
                    importTemplate()
                } label: {
                    Label("Import template…", systemImage: "doc.badge.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(!teacher.canPrepareTemplate)
                .help(templateImportHelp)
            }
            if store.workflows.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "repeat.circle.fill").font(.system(size: 50)).foregroundStyle(Color.accentColor)
                    Text("Your repeatable work lives here").font(.title2.bold())
                    Text("Teach Neloa one real task. The next time, you’ll only need to say what changed.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 470)
                    HStack(spacing: 10) {
                        Button("Teach my first automation") {
                            NotificationCenter.default.post(name: .showNeloaTeach, object: nil)
                        }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Import a template…") {
                            importTemplate()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(!teacher.canPrepareTemplate)
                        .help(templateImportHelp)
                    }
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
        .onAppear {
            if let workflowID = runRouter.currentRequest?.workflowID { selectedID = workflowID }
        }
        .onChange(of: runRouter.currentRequest) { _, request in
            if let workflowID = request?.workflowID { selectedID = workflowID }
        }
        .sheet(item: runRequestBinding) { request in
            if let workflow = store.workflows.first(where: { $0.id == request.workflowID }) {
                RunView(
                    workflow: workflow,
                    initialInstruction: request.initialInstruction ?? "",
                    onClose: runRouter.finishCurrent
                )
                    .id(request.id)
                    .frame(minWidth: 760, idealWidth: 940, minHeight: 650, idealHeight: 760)
                    .presentationSizing(.fitted)
            } else {
                MissingAutomationRunView(finish: runRouter.finishCurrent)
            }
        }
        .sheet(item: $templateImport) { draft in
            AutomationTemplateImportView(
                template: draft.template,
                startTeaching: { startTeaching(draft.template) }
            )
            .frame(width: 760, height: 640)
            .presentationSizing(.fitted)
        }
        .alert("Template couldn’t be imported", isPresented: Binding(
            get: { templateImportError != nil },
            set: { if !$0 { templateImportError = nil } }
        )) {
            Button("OK") { templateImportError = nil }
        } message: {
            Text(templateImportError ?? "")
        }
    }

    private var runRequestBinding: Binding<AutomationRunRequest?> {
        Binding(
            get: { runRouter.currentRequest },
            set: { request in
                if request == nil { runRouter.finishCurrent() }
            }
        )
    }

    private func lastRunDescription(for workflow: Workflow) -> String {
        guard let run = store.activities.first(where: { $0.workflowID == workflow.id }) else {
            return "Ready to run · Updated \(workflow.updatedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        let status = run.status == .completed ? "Finished" : run.status.rawValue.capitalized
        return "Last ran \(run.finishedAt.formatted(date: .abbreviated, time: .omitted)) · \(status)"
    }

    private var templateImportHelp: String {
        teacher.canPrepareTemplate
            ? "Preview a privacy-safe teaching guide before demonstrating it on this Mac."
            : "Finish the current teaching session before importing another template."
    }

    private func importTemplate() {
        guard teacher.canPrepareTemplate else {
            templateImportError = "Finish or discard the current teaching session before importing a template."
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Import Neloa Reusable Template"
        panel.prompt = "Preview Template"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let template = try AutomationTemplateCodec.read(from: url)
            templateImport = AutomationTemplateImportDraft(template: template)
        } catch {
            templateImportError = error.localizedDescription
        }
    }

    private func startTeaching(_ template: AutomationTemplate) {
        guard teacher.prepare(template: template) else {
            templateImportError = "Finish or discard the current teaching session before using this template."
            return
        }
        templateImport = nil
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showNeloaTeach, object: nil)
        }
    }
}

private struct MissingAutomationRunView: View {
    let finish: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "questionmark.folder.fill")
                .font(.system(size: 38))
                .foregroundStyle(.secondary)
            Text("This automation is no longer available")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("The reminder, watched-folder event, or run link refers to an automation that was removed from this Mac.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 390)
            Button("Done", action: finish)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(width: 520, height: 330)
    }
}

private struct AutomationDetail: View {
    let workflow: Workflow
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var schedules: AutomationScheduleCenter
    @EnvironmentObject private var fileTriggers: FileTriggerCenter
    @State private var showingRun = false
    @State private var showingRepair = false
    @State private var showingSchedule = false
    @State private var showingFileTrigger = false
    @State private var showingTemplateExport = false
    @State private var confirmDelete = false
    @State private var exportMessage: String?
    @State private var actionMessageTitle = "Export"
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
                    Button("Review & repair…") { showingRepair = true }
                    Button("Configure watched folder…") { showingFileTrigger = true }
                    Button("Copy run link for Shortcuts") { copyRunLink() }
                    Button("Share reusable template…") { showingTemplateExport = true }
                    Button("Export Markdown skill…") { exportSkill() }
                    Button("Delete automation", role: .destructive) { confirmDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("More automation actions")
                Button {
                    showingRepair = true
                } label: {
                    Label("Review & repair", systemImage: "scope")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Re-teach one fragile action without rebuilding the workflow")
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

            scheduleCard
            fileTriggerCard

            if !approvalRules.isEmpty {
                detailCard(title: "When Neloa asks", icon: "hand.raised.fill") {
                    ForEach(approvalRules) { step in
                        Text(step.title).font(.system(size: 15))
                    }
                }
            }

            if recommendedRepairCount > 0 {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(recommendedRepairCount) action\(recommendedRepairCount == 1 ? "" : "s") use fragile grounding")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Re-teach a position-only or visual action to capture a stronger target.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Repair") { showingRepair = true }
                        .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
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
        .sheet(isPresented: $showingRepair) {
            WorkflowRepairView(workflow: workflow)
                .frame(minWidth: 960, idealWidth: 1120, minHeight: 720, idealHeight: 820)
                .presentationSizing(.fitted)
        }
        .sheet(isPresented: $showingSchedule) {
            AutomationScheduleEditor(workflow: workflow)
                .frame(width: 560, height: 590)
                .presentationSizing(.fitted)
        }
        .sheet(isPresented: $showingFileTrigger) {
            FileTriggerEditor(workflow: workflow)
                .frame(width: 590, height: 640)
                .presentationSizing(.fitted)
        }
        .sheet(isPresented: $showingTemplateExport) {
            AutomationTemplateExportView(workflow: workflow)
                .frame(width: 820, height: 680)
                .presentationSizing(.fitted)
        }
        .alert("Delete \(workflow.name)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                schedules.remove(workflowID: workflow.id)
                fileTriggers.remove(workflowID: workflow.id)
                store.delete(workflow)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the automation and its saved teaching recordings from this Mac. This cannot be undone.")
        }
        .alert(actionMessageTitle, isPresented: Binding(
            get: { exportMessage != nil },
            set: { if !$0 { exportMessage = nil } }
        )) {
            Button("OK") { exportMessage = nil }
        } message: { Text(exportMessage ?? "") }
    }

    private var flexibleInputs: [WorkflowStep] { workflow.steps.filter(\.isRunVariable) }
    private var approvalRules: [WorkflowStep] { workflow.steps.filter { $0.kind == .approval || $0.requiresApproval } }
    private var userInstructions: [WorkflowStep] { workflow.steps.filter(\.isUserInstruction) }
    private var recommendedRepairCount: Int { workflow.steps.filter(StepRepairSupport.isRecommended).count }
    private var appsUsed: [String] {
        Array(Set(workflow.steps.compactMap(\.application).filter { !$0.isEmpty })).sorted()
    }

    @ViewBuilder
    private var scheduleCard: some View {
        if let schedule = workflow.schedule {
            detailCard(title: "Run reminder", icon: "calendar.badge.clock") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(AutomationScheduleSupport.summary(schedule))
                            .font(.system(size: 15, weight: .medium))
                        Text("Opens a reviewed run; it never starts the automation automatically.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    scheduleStatus(schedule)
                    Button("Edit") { showingSchedule = true }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run this on a routine?")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add a private reminder that opens a reviewed run when you are ready.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add reminder") { showingSchedule = true }
                    .buttonStyle(.bordered)
            }
            .padding(14)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func scheduleStatus(_ schedule: AutomationSchedule) -> some View {
        if !schedule.isEnabled {
            Label("Off", systemImage: "pause.circle.fill")
                .foregroundStyle(.secondary)
        } else if schedules.canDeliverReminders {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Permission needed", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help("Allow Neloa notifications so this local reminder can appear.")
        }
    }

    @ViewBuilder
    private var fileTriggerCard: some View {
        if let trigger = workflow.fileTrigger {
            detailCard(title: "Watched folder", icon: "folder.badge.gearshape") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(FileTriggerSupport.displayFolder(trigger)) · \(trigger.kind.label)")
                            .font(.system(size: 15, weight: .medium))
                        Text("A new or replaced matching file prepares a reviewed run while Neloa is open.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    fileTriggerStatus(trigger)
                    Button("Edit") { showingFileTrigger = true }
                        .buttonStyle(.bordered)
                }
            }
        } else if FileTriggerSupport.fileInputIndex(in: workflow) != nil {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start when a file arrives?")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Watch one local folder and prepare this automation for review.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose folder") { showingFileTrigger = true }
                    .buttonStyle(.bordered)
            }
            .padding(14)
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    @ViewBuilder
    private func fileTriggerStatus(_ trigger: AutomationFileTrigger) -> some View {
        if !trigger.isEnabled {
            Label("Off", systemImage: "pause.circle.fill")
                .foregroundStyle(.secondary)
        } else if let issue = fileTriggers.issues[workflow.id] {
            Label("Needs attention", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .help(issue)
        } else if fileTriggers.watchingWorkflowIDs.contains(workflow.id) {
            Label("Watching", systemImage: "eye.circle.fill")
                .foregroundStyle(.green)
        } else {
            Label("Starting…", systemImage: "clock.fill")
                .foregroundStyle(.secondary)
        }
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
            actionMessageTitle = "Export"
            exportMessage = "The automation was exported to \(url.lastPathComponent)."
        } catch {
            actionMessageTitle = "Export"
            exportMessage = "The skill could not be exported: \(error.localizedDescription)"
        }
    }

    private func copyRunLink() {
        let url = NeloaDeepLink.runURL(workflowID: workflow.id).absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        actionMessageTitle = "Run link copied"
        exportMessage = "Paste this link into Apple Shortcuts, Raycast, or another launcher. Opening it shows Neloa’s reviewed run screen; it never starts the automation by itself."
    }
}

private struct AutomationScheduleEditor: View {
    let workflow: Workflow

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: WorkflowStore
    @EnvironmentObject private var schedules: AutomationScheduleCenter
    @State private var repeatMode: AutomationScheduleRepeat
    @State private var reminderTime: Date
    @State private var weekday: Int
    @State private var isEnabled: Bool
    @State private var isSaving = false
    @State private var permissionNeeded = false

    init(workflow: Workflow) {
        self.workflow = workflow
        let schedule = workflow.schedule ?? AutomationSchedule(
            repeatMode: .weekdays,
            hour: 9,
            minute: 0,
            weekday: 2
        )
        let normalized = AutomationScheduleSupport.normalized(schedule)
        _repeatMode = State(initialValue: normalized.repeatMode)
        _reminderTime = State(initialValue: Self.time(hour: normalized.hour, minute: normalized.minute))
        _weekday = State(initialValue: normalized.weekday ?? 2)
        _isEnabled = State(initialValue: normalized.isEnabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 50, height: 50)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Run reminder")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text(workflow.name)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: $isEnabled)
                    .toggleStyle(.switch)
            }

            VStack(alignment: .leading, spacing: 15) {
                Text("When should Neloa remind you?")
                    .font(.system(size: 16, weight: .semibold))

                Picker("Repeat", selection: $repeatMode) {
                    ForEach(AutomationScheduleRepeat.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!isEnabled)

                HStack {
                    if repeatMode == .weekly {
                        Picker("Day", selection: $weekday) {
                            ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                                Text(name).tag(index + 1)
                            }
                        }
                        .frame(maxWidth: 220)
                    }
                    Spacer()
                    Text("Time")
                        .font(.system(size: 14, weight: .medium))
                    DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .disabled(!isEnabled)
            }
            .padding(16)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 8) {
                Label("A reminder, not unattended automation", systemImage: "hand.raised.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("At the scheduled time, macOS shows a private notification. Opening it takes you to Neloa’s normal change preview, readiness check, and cancellation countdown. No clicks or typing happen until you explicitly start the run.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 15))

            if permissionNeeded {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notification permission is needed")
                            .font(.system(size: 14, weight: .semibold))
                        Text(schedules.lastError ?? "Allow notifications for Neloa, then save again. The automation itself remains off until you start it.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open Settings") { schedules.openNotificationSettings() }
                        .buttonStyle(.bordered)
                }
                .padding(13)
                .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
            }

            Spacer(minLength: 0)

            HStack {
                if workflow.schedule != nil {
                    Button("Remove reminder", role: .destructive) { removeReminder() }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "Saving…" : "Save reminder") { saveReminder() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
            }
        }
        .padding(26)
        .interactiveDismissDisabled(isSaving)
        .task { await schedules.refreshAuthorization() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await schedules.refreshAuthorization() }
        }
    }

    private func saveReminder() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        let schedule = AutomationSchedule(
            repeatMode: repeatMode,
            hour: components.hour ?? 9,
            minute: components.minute ?? 0,
            weekday: repeatMode == .weekly ? weekday : nil,
            isEnabled: isEnabled
        )
        var updated = workflow
        updated.schedule = schedule
        store.save(updated)
        isSaving = true
        Task {
            let applied = await schedules.apply(schedule: schedule, to: updated)
            isSaving = false
            permissionNeeded = isEnabled && !applied
            if applied || !isEnabled { dismiss() }
        }
    }

    private func removeReminder() {
        schedules.remove(workflowID: workflow.id)
        var updated = workflow
        updated.schedule = nil
        store.save(updated)
        dismiss()
    }

    private static func time(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
