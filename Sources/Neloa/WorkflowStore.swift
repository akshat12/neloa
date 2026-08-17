import Foundation
import Combine

struct WorkflowStoreIssue: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let details: String
    let canRetry: Bool
}

@MainActor
final class WorkflowStore: ObservableObject {
    @Published private(set) var workflows: [Workflow] = []
    @Published private(set) var activities: [AutomationRunReceipt] = []
    @Published var lastError: String?
    @Published private(set) var issue: WorkflowStoreIssue?

    private let fileURL: URL
    private var retryAction: (() -> Void)?

    init(
        fileURL: URL? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        #if DEBUG
        let resolvedFileURL = fileURL ?? Self.uiTestFileURL(environment: environment)
        #else
        let resolvedFileURL = fileURL
        #endif
        if let resolvedFileURL {
            self.fileURL = resolvedFileURL
        } else {
            do {
                try BrandMigration.migrateApplicationSupportIfNeeded()
            } catch {
                let message = "Your saved Humana data could not be moved to Neloa."
                lastError = message
                issue = WorkflowStoreIssue(
                    title: "Saved data needs attention",
                    message: message,
                    details: error.localizedDescription,
                    canRetry: false
                )
            }
            self.fileURL = BrandMigration.applicationSupportDirectory.appendingPathComponent("workflows.json")
        }
        load()
        loadActivity()
    }

    nonisolated static func uiTestFileURL(environment: [String: String]) -> URL? {
        guard let path = environment["NELOA_UI_TEST_STORE_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    func save(_ workflow: Workflow) {
        var value = WorkflowSemanticEnricher.enrich(workflow)
        value.updatedAt = Date()
        value.recordingPath = preserveAsset(at: value.recordingPath, for: value.id)
        value.narrationPath = preserveAsset(at: value.narrationPath, for: value.id)
        if let index = workflows.firstIndex(where: { $0.id == value.id }) {
            workflows[index] = value
        } else {
            workflows.insert(value, at: 0)
        }
        persist()
    }

    func delete(_ workflow: Workflow) {
        workflows.removeAll { $0.id == workflow.id }
        let recordings = fileURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(workflow.id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: recordings.path) {
            do {
                try FileManager.default.removeItem(at: recordings)
            } catch {
                report(
                    title: "Recordings weren’t removed",
                    message: "The automation was removed, but its local recordings are still on this Mac.",
                    error: error,
                    retry: { [weak self] in self?.removeRecordings(for: workflow) }
                )
            }
        }
        persist()
    }

    func record(_ receipt: AutomationRunReceipt) {
        activities.insert(receipt, at: 0)
        if activities.count > 250 { activities = Array(activities.prefix(250)) }
        persistActivity()
    }

    func clearActivity() {
        activities = []
        persistActivity()
    }

    func deleteAllRecordings() {
        let recordings = fileURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
        do {
            if FileManager.default.fileExists(atPath: recordings.path) {
                try FileManager.default.removeItem(at: recordings)
            }
            for index in workflows.indices {
                workflows[index].recordingPath = nil
                workflows[index].narrationPath = nil
            }
            persist()
        } catch {
            report(
                title: "Recordings weren’t deleted",
                message: "Neloa could not delete all teaching recordings.",
                error: error,
                retry: { [weak self] in self?.deleteAllRecordings() }
            )
        }
    }

    func retryLastOperation() {
        let retry = retryAction
        dismissIssue()
        retry?()
    }

    func dismissIssue() {
        issue = nil
        lastError = nil
        retryAction = nil
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            workflows = try JSONDecoder.neloa.decode([Workflow].self, from: Data(contentsOf: fileURL))
            repairLegacyAssetPaths()
            repairLegacyWorkflowSemantics()
        } catch {
            report(
                title: "Automations couldn’t be opened",
                message: "Neloa could not read your saved automations.",
                error: error,
                retry: { [weak self] in self?.load() }
            )
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.neloa.encode(workflows).write(to: fileURL, options: .atomic)
        } catch {
            report(
                title: "Changes weren’t saved",
                message: "Neloa could not save your automation changes.",
                error: error,
                retry: { [weak self] in self?.persist() }
            )
        }
    }

    private var activityURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("activity.json")
    }

    private func loadActivity() {
        guard FileManager.default.fileExists(atPath: activityURL.path) else { return }
        do {
            activities = try JSONDecoder.neloa.decode([AutomationRunReceipt].self, from: Data(contentsOf: activityURL))
        } catch {
            report(
                title: "Activity couldn’t be opened",
                message: "Neloa could not read your local run history.",
                error: error,
                retry: { [weak self] in self?.loadActivity() }
            )
        }
    }

    private func persistActivity() {
        do {
            try FileManager.default.createDirectory(at: activityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.neloa.encode(activities).write(to: activityURL, options: .atomic)
        } catch {
            report(
                title: "Run receipt wasn’t saved",
                message: "The automation finished, but Neloa could not save its local activity receipt.",
                error: error,
                retry: { [weak self] in self?.persistActivity() }
            )
        }
    }

    private func preserveAsset(at path: String?, for workflowID: UUID) -> String? {
        guard let path else { return nil }
        let source = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: source.path) else { return path }
        let recordings = fileURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(workflowID.uuidString, isDirectory: true)
        let destination = recordings.appendingPathComponent(source.lastPathComponent)
        if source.path == destination.path { return path }
        do {
            try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            report(
                title: "Recording wasn’t preserved",
                message: "The automation was saved, but its teaching recording could not be copied into Neloa’s library.",
                error: error,
                retry: { [weak self] in self?.retryPreservingAsset(at: path, for: workflowID) }
            )
            return path
        }
    }

    private func removeRecordings(for workflow: Workflow) {
        let recordings = fileURL.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
            .appendingPathComponent(workflow.id.uuidString, isDirectory: true)
        guard FileManager.default.fileExists(atPath: recordings.path) else {
            dismissIssue()
            return
        }
        do {
            try FileManager.default.removeItem(at: recordings)
            dismissIssue()
        } catch {
            report(
                title: "Recordings weren’t removed",
                message: "The automation was removed, but its local recordings are still on this Mac.",
                error: error,
                retry: { [weak self] in self?.removeRecordings(for: workflow) }
            )
        }
    }

    private func retryPreservingAsset(at path: String, for workflowID: UUID) {
        guard let index = workflows.firstIndex(where: { $0.id == workflowID }) else {
            dismissIssue()
            return
        }
        let preservedPath = preserveAsset(at: path, for: workflowID)
        if workflows[index].recordingPath == path { workflows[index].recordingPath = preservedPath }
        if workflows[index].narrationPath == path { workflows[index].narrationPath = preservedPath }
        if preservedPath != path {
            dismissIssue()
            persist()
        }
    }

    private func report(
        title: String,
        message: String,
        error: Error,
        retry: (() -> Void)?
    ) {
        lastError = message
        issue = WorkflowStoreIssue(
            title: title,
            message: message,
            details: error.localizedDescription,
            canRetry: retry != nil
        )
        retryAction = retry
    }

    private func repairLegacyAssetPaths() {
        var changed = false
        for index in workflows.indices {
            let recording = BrandMigration.repairedAssetPath(workflows[index].recordingPath)
            let narration = BrandMigration.repairedAssetPath(workflows[index].narrationPath)
            if recording != workflows[index].recordingPath || narration != workflows[index].narrationPath {
                workflows[index].recordingPath = recording
                workflows[index].narrationPath = narration
                changed = true
            }
        }
        if changed { persist() }
    }

    private func repairLegacyWorkflowSemantics() {
        var changed = false
        for index in workflows.indices {
            let enriched = WorkflowSemanticEnricher.enrich(workflows[index])
            if enriched != workflows[index] {
                workflows[index] = enriched
                changed = true
            }
        }
        if changed { persist() }
    }
}

extension JSONEncoder {
    static var neloa: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var neloa: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
