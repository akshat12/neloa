import Foundation
import Combine

@MainActor
final class WorkflowStore: ObservableObject {
    @Published private(set) var workflows: [Workflow] = []
    @Published private(set) var activities: [AutomationRunReceipt] = []
    @Published var lastError: String?

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            do {
                try BrandMigration.migrateApplicationSupportIfNeeded()
            } catch {
                lastError = "Your saved Humana data could not be moved to Neloa: \(error.localizedDescription)"
            }
            self.fileURL = BrandMigration.applicationSupportDirectory.appendingPathComponent("workflows.json")
        }
        load()
        loadActivity()
    }

    func save(_ workflow: Workflow) {
        var value = workflow
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
                lastError = "The automation was removed, but its recordings could not be deleted: \(error.localizedDescription)"
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
            lastError = "Your recordings could not be deleted: \(error.localizedDescription)"
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            workflows = try JSONDecoder.neloa.decode([Workflow].self, from: Data(contentsOf: fileURL))
            repairLegacyAssetPaths()
        } catch {
            lastError = "Your saved automations could not be opened: \(error.localizedDescription)"
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.neloa.encode(workflows).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Your automations could not be saved: \(error.localizedDescription)"
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
            lastError = "Your activity history could not be opened: \(error.localizedDescription)"
        }
    }

    private func persistActivity() {
        do {
            try FileManager.default.createDirectory(at: activityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder.neloa.encode(activities).write(to: activityURL, options: .atomic)
        } catch {
            lastError = "Your activity history could not be saved: \(error.localizedDescription)"
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
            lastError = "The workflow was saved, but its recording could not be preserved: \(error.localizedDescription)"
            return path
        }
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
