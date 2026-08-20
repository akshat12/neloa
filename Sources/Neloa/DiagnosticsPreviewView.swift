import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DiagnosticsPreviewView: View {
    let report: DiagnosticsReport

    @Environment(\.dismiss) private var dismiss
    @State private var saveError: String?
    @State private var savedFilename: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 54, height: 54)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review diagnostics before sharing")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("This report is created on your Mac. Nothing is uploaded or sent by Neloa.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close")
                .accessibilityLabel("Close diagnostics preview")
            }

            HStack(spacing: 10) {
                summaryPill(
                    "\(report.storage.automationCount) automation\(report.storage.automationCount == 1 ? "" : "s")",
                    icon: "repeat"
                )
                summaryPill(
                    "\(readinessBlockerCount) blocker\(readinessBlockerCount == 1 ? "" : "s")",
                    icon: readinessBlockerCount == 0 ? "checkmark.circle" : "exclamationmark.octagon",
                    color: readinessBlockerCount == 0 ? .green : .orange
                )
                summaryPill(
                    "\(report.activity.failed) failed run\(report.activity.failed == 1 ? "" : "s")",
                    icon: "exclamationmark.triangle"
                )
                summaryPill(modelStatusLabel, icon: "memorychip")
            }

            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        privacyColumn(
                            title: "Included",
                            icon: "checkmark.circle.fill",
                            color: .green,
                            items: report.privacy.includes
                        )
                        privacyColumn(
                            title: "Never included",
                            icon: "eye.slash.fill",
                            color: Color.accentColor,
                            items: report.privacy.excludes
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Exact report")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text("JSON · Selectable")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ScrollView([.horizontal, .vertical]) {
                        Text(reportText)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)

            HStack {
                if let savedFilename {
                    Label("Saved \(savedFilename)", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text("Save or share it only after the preview looks right to you.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button {
                    saveReport()
                } label: {
                    Label("Save diagnostics…", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .alert("Diagnostics weren’t saved", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var reportText: String {
        (try? report.jsonString()) ?? "Neloa could not render this diagnostics report."
    }

    private var readinessBlockerCount: Int {
        report.workflows.reduce(0) { $0 + $1.readiness.blockerCount }
    }

    private var modelStatusLabel: String {
        switch report.model.status {
        case "notInstalled": "Model not installed"
        case "ready": "Model ready"
        case "checking": "Checking model"
        case "downloading": "Downloading model"
        case "loading": "Loading model"
        case "removing": "Removing model"
        case "failed": "Model needs attention"
        default: "Model unavailable"
        }
    }

    private func summaryPill(_ text: String, icon: String, color: Color = .secondary) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(color.opacity(0.09), in: Capsule())
    }

    private func privacyColumn(
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
                    Circle()
                        .fill(color.opacity(0.75))
                        .frame(width: 5, height: 5)
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

    private func saveReport() {
        let panel = NSSavePanel()
        panel.title = "Save Neloa Diagnostics"
        panel.prompt = "Save Report"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "Neloa-Diagnostics-\(Self.filenameDate(report.generatedAt)).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try report.jsonData().write(to: url, options: [.atomic])
            savedFilename = url.lastPathComponent
        } catch {
            saveError = error.localizedDescription
        }
    }

    private nonisolated static func filenameDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter.string(from: date)
    }
}
