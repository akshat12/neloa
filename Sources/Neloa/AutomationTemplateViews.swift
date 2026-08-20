import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AutomationTemplateImportDraft: Identifiable {
    let id = UUID()
    let template: AutomationTemplate
}

struct AutomationTemplateExportView: View {
    let workflow: Workflow

    @Environment(\.dismiss) private var dismiss
    @State private var publicTitle = ""
    @State private var saveError: String?
    @State private var savedFilename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(alignment: .leading, spacing: 7) {
                Text("Public template title")
                    .font(.system(size: 14, weight: .semibold))
                TextField("For example, Monthly report starter", text: $publicTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 15))
                    .accessibilityLabel("Public template title")
                Text("Enter a reusable title that contains no client, account, or personal information. Neloa does not reuse the private automation name.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let templateValidationMessage {
                    Label(templateValidationMessage, systemImage: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                }
            }

            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        privacyCard(
                            title: "Included",
                            icon: "checkmark.circle.fill",
                            color: .green,
                            items: TemplatePrivacyCopy.included
                        )
                        privacyCard(
                            title: "Never included",
                            icon: "eye.slash.fill",
                            color: Color.accentColor,
                            items: TemplatePrivacyCopy.excluded
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Teaching outline")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Text("\(workflow.steps.count) guide steps")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(Array(templateSteps.enumerated()), id: \.offset) { offset, step in
                                TemplateStepRow(number: offset + 1, step: step)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(10)
                    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 13))

                    DisclosureGroup("View exact JSON") {
                        ScrollView([.horizontal, .vertical]) {
                            Text(templateJSON)
                                .font(.system(size: 10, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                        }
                        .frame(height: 150)
                        .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            footer
        }
        .padding(26)
        .alert("Template wasn’t saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.and.arrow.up.on.square.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52, height: 52)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 4) {
                Text("Share the shape, not your work")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("The recipient gets a non-executable teaching guide and must demonstrate the task on their own Mac.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill").font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close")
            .accessibilityLabel("Close template export")
        }
    }

    private var footer: some View {
        HStack {
            if let savedFilename {
                Label("Saved \(savedFilename)", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.green)
            } else {
                Label("Nothing is uploaded by Neloa.", systemImage: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button {
                saveTemplate()
            } label: {
                Label("Save template…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(resolvedTemplate == nil)
        }
    }

    private var templateSteps: [AutomationTemplateStep] {
        workflow.steps.map { step in
            AutomationTemplateStep(
                kind: step.kind,
                isFlexibleInput: step.kind == .typeText && step.isRunVariable,
                requiresApproval: step.kind == .approval || step.requiresApproval
            )
        }
    }

    private var resolvedTemplate: AutomationTemplate? {
        try? AutomationTemplateCodec.make(workflow: workflow, publicTitle: publicTitle)
    }

    private var templateValidationMessage: String? {
        guard !publicTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            _ = try AutomationTemplateCodec.make(workflow: workflow, publicTitle: publicTitle)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private var templateJSON: String {
        guard let template = resolvedTemplate else {
            return "Enter a public title to preview the exact template file."
        }
        return (try? template.jsonString()) ?? "Neloa could not render this template."
    }

    private func privacyCard(
        title: String,
        icon: String,
        color: Color,
        items: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(color.opacity(0.75)).frame(width: 5, height: 5)
                    Text(item)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
    }

    private func saveTemplate() {
        guard let template = resolvedTemplate else { return }
        let panel = NSSavePanel()
        panel.title = "Save Neloa Reusable Template"
        panel.prompt = "Save Template"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(AutomationTemplateCodec.sanitizedSlug(template.title)).neloa-template.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try template.jsonData().write(to: url, options: .atomic)
            savedFilename = url.lastPathComponent
        } catch {
            saveError = error.localizedDescription
        }
    }
}

struct AutomationTemplateImportView: View {
    let template: AutomationTemplate
    let startTeaching: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "doc.badge.arrow.up.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Review this teaching guide before using it on your Mac.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close template preview")
            }

            HStack(spacing: 9) {
                summaryPill("\(template.steps.count) guide steps", icon: "list.number")
                summaryPill("\(template.flexibleInputCount) flexible inputs", icon: "slider.horizontal.3")
                summaryPill("\(template.approvalCount) approval gates", icon: "hand.raised.fill")
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What you’ll demonstrate")
                        .font(.system(size: 16, weight: .semibold))
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(Array(template.steps.enumerated()), id: \.offset) { offset, step in
                                TemplateStepRow(number: offset + 1, step: step)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Not an executable automation", systemImage: "checkmark.shield.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("This file cannot replay clicks, type values, open a private address, or name an app. It only describes the order and kind of work to teach.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Text("Neloa will record your own demonstration, build a fresh automation, and show the normal review before anything can be saved or run.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DisclosureGroup("Privacy guarantees") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(TemplatePrivacyCopy.excluded, id: \.self) { item in
                                Label(item, systemImage: "minus.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 7)
                    }
                    .font(.system(size: 13, weight: .semibold))
                }
                .padding(16)
                .frame(width: 300, alignment: .topLeading)
                .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
            }
            .frame(maxHeight: .infinity)

            HStack {
                Label("Importing does not save or run an automation.", systemImage: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    startTeaching()
                } label: {
                    Label("Teach this template", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
    }

    private func summaryPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.09), in: Capsule())
    }
}

struct AutomationTemplateTeachingGuide: View {
    let template: AutomationTemplate
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Teaching from a reusable template", systemImage: "doc.badge.arrow.up")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                    Text(template.title)
                        .font(.system(size: 14, weight: .medium))
                }
                Spacer()
                Button("Remove guide", action: remove)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            Text("Demonstrate these steps yourself. The template supplies no clicks, values, apps, addresses, or executable actions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 7) {
                ForEach(Array(template.steps.prefix(7).enumerated()), id: \.offset) { offset, step in
                    TemplateStepRow(number: offset + 1, step: step, compact: true)
                }
                if template.steps.count > 7 {
                    Text("+ \(template.steps.count - 7) more guide steps")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Label("You will still review the freshly learned automation before saving it.", systemImage: "checkmark.shield")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color.accentColor.opacity(0.065), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct TemplateStepRow: View {
    let number: Int
    let step: AutomationTemplateStep
    var compact = false

    var body: some View {
        HStack(spacing: 9) {
            Text("\(number)")
                .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: compact ? 23 : 27, height: compact ? 23 : 27)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            Image(systemName: step.icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(step.label)
                .font(.system(size: compact ? 12 : 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            if step.isFlexibleInput {
                Text("Flexible")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.09), in: Capsule())
            }
            if step.requiresApproval {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                    .help("Approval guide step")
                    .accessibilityLabel("Approval guide step")
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 6 : 8)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(step.label)\(step.isFlexibleInput ? ", flexible input" : "")\(step.requiresApproval ? ", approval" : "")")
    }
}

private enum TemplatePrivacyCopy {
    static let included = [
        "The order and kind of guide steps",
        "Which typed inputs may change each run",
        "Where approval gates belong",
        "The public title you enter"
    ]

    static let excluded = [
        "Recordings, narration, transcripts, and instructions",
        "Typed values, web addresses, files, and folders",
        "Workflow, control, field, and app names",
        "Click positions, display IDs, and keyboard data",
        "Automation IDs, timestamps, reminders, and watched folders"
    ]
}
