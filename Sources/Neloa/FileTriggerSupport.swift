import AppKit
import Combine
import Darwin
import Foundation

struct FileTriggerFingerprint: Equatable, Sendable {
    var size: Int64
    var modifiedAt: Date
}

enum FileTriggerSupport {
    static let instructionPrefix = "Use the new file at: "

    struct FileInputCandidate: Identifiable, Equatable, Sendable {
        var id: UUID { stepID }
        var stepID: UUID
        var index: Int
        var label: String
        fileprivate var score: Int
    }

    nonisolated static func accepts(_ url: URL, kind: AutomationFileTriggerKind) -> Bool {
        let name = url.lastPathComponent
        guard !name.isEmpty,
              !name.hasPrefix("."),
              !name.hasPrefix("~$"),
              !["crdownload", "download", "part", "tmp"].contains(url.pathExtension.lowercased()) else {
            return false
        }
        guard let allowed = kind.fileExtensions else { return true }
        return allowed.contains(url.pathExtension.lowercased())
    }

    nonisolated static func snapshot(
        folderURL: URL,
        kind: AutomationFileTriggerKind,
        fileManager: FileManager = .default
    ) throws -> [URL: FileTriggerFingerprint] {
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var result: [URL: FileTriggerFingerprint] = [:]
        for url in urls where accepts(url, kind: kind) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true else { continue }
            result[url.standardizedFileURL] = FileTriggerFingerprint(
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        return result
    }

    nonisolated static func instruction(for fileURL: URL) -> String {
        "\(instructionPrefix)\(fileURL.standardizedFileURL.path)"
    }

    nonisolated static func displayFolder(_ trigger: AutomationFileTrigger) -> String {
        URL(fileURLWithPath: trigger.folderPath).lastPathComponent
    }

    nonisolated static func fileInputCandidates(in workflow: Workflow) -> [FileInputCandidate] {
        workflow.steps.indices
            .filter { workflow.steps[$0].isRunVariable }
            .map { index in
                let step = workflow.steps[index]
                return FileInputCandidate(
                    stepID: step.id,
                    index: index,
                    label: fileInputLabel(step, index: index),
                    score: fileInputScore(step)
                )
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score { return $0.index < $1.index }
                return $0.score > $1.score
            }
    }

    nonisolated static func fileInputIndex(in workflow: Workflow, preferredStepID: UUID? = nil) -> Int? {
        let candidates = fileInputCandidates(in: workflow)
        if let preferredStepID {
            return candidates.first(where: { $0.stepID == preferredStepID })?.index
        }
        return candidates.first?.index
    }

    nonisolated static func contains(_ fileURL: URL, in trigger: AutomationFileTrigger) -> Bool {
        guard trigger.isEnabled, accepts(fileURL, kind: trigger.kind) else { return false }
        let selectedFolder = URL(fileURLWithPath: trigger.folderPath, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let containingFolder = fileURL.standardizedFileURL
            .resolvingSymlinksInPath()
            .deletingLastPathComponent()
        return containingFolder == selectedFolder
    }

    private nonisolated static func fileInputLabel(_ step: WorkflowStep, index: Int) -> String {
        if let target = step.target?.trimmingCharacters(in: .whitespacesAndNewlines), !target.isEmpty {
            return target
        }
        let title = step.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        return "File field \(index + 1)"
    }

    private nonisolated static func fileInputScore(_ step: WorkflowStep) -> Int {
        let context = [step.target, step.title, step.detail]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        var score = 0
        for keyword in ["attachment", "document", "file", "source", "upload"] where context.contains(keyword) {
            score += 3
        }
        if let text = step.text, text.hasPrefix("/") { score += 4 }
        if let text = step.text,
           text.range(of: #"\.(csv|numbers|ods|pdf|rtf|txt|xls|xlsx)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            score += 2
        }
        if context.contains("address and search") || context.contains("url") { score -= 8 }
        return score
    }
}

private final class WatchedFolder {
    private let folderURL: URL
    private let kind: AutomationFileTriggerKind
    private let queue: DispatchQueue
    private let source: DispatchSourceFileSystemObject
    private let deliver: (URL) -> Void
    private let fail: (String) -> Void
    private var known: [URL: FileTriggerFingerprint]
    private var pending: [URL: FileTriggerFingerprint] = [:]
    private var scanWorkItem: DispatchWorkItem?

    init(
        workflowID: UUID,
        folderURL: URL,
        kind: AutomationFileTriggerKind,
        deliver: @escaping (URL) -> Void,
        fail: @escaping (String) -> Void
    ) throws {
        self.folderURL = folderURL.standardizedFileURL
        self.kind = kind
        self.deliver = deliver
        self.fail = fail
        known = try FileTriggerSupport.snapshot(folderURL: self.folderURL, kind: kind)
        queue = DispatchQueue(label: "ai.neloa.watched-folder.\(workflowID.uuidString)")

        let descriptor = open(self.folderURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.delete, .rename, .write],
            queue: queue
        )
        source.setCancelHandler { close(descriptor) }
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.resume()
    }

    func stop() {
        scanWorkItem?.cancel()
        source.cancel()
    }

    private func folderChanged() {
        let flags = source.data
        if flags.contains(.delete) || flags.contains(.rename) {
            fail("The watched folder moved or was removed. Choose it again to resume this trigger.")
            stop()
            return
        }
        scheduleScan()
    }

    private func scheduleScan() {
        scanWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.scanForSettledFiles() }
        scanWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.75, execute: item)
    }

    private func scanForSettledFiles() {
        do {
            let current = try FileTriggerSupport.snapshot(folderURL: folderURL, kind: kind)
            known = known.filter { current[$0.key] != nil }
            pending = pending.filter { current[$0.key] != nil }

            let changedURLs = current.keys
                .filter { url in current[url].map { known[url] != $0 } ?? false }
                .sorted { lhs, rhs in
                    let left = current[lhs]?.modifiedAt ?? .distantPast
                    let right = current[rhs]?.modifiedAt ?? .distantPast
                    if left == right { return lhs.path < rhs.path }
                    return left < right
                }
            for url in changedURLs {
                guard let fingerprint = current[url] else { continue }
                if pending[url] == fingerprint {
                    pending[url] = nil
                    known[url] = fingerprint
                    deliver(url)
                } else {
                    pending[url] = fingerprint
                }
            }
            if !pending.isEmpty { scheduleScan() }
        } catch {
            fail("Neloa could not read the watched folder: \(error.localizedDescription)")
            stop()
        }
    }
}

@MainActor
final class FileTriggerCenter: ObservableObject {
    @Published private(set) var issues: [UUID: String] = [:]
    @Published private(set) var watchingWorkflowIDs: Set<UUID> = []

    private var watchers: [UUID: WatchedFolder] = [:]
    private let runRouter: AutomationRunRouter

    init() {
        runRouter = .shared
    }

    init(runRouter: AutomationRunRouter) {
        self.runRouter = runRouter
    }

    func reconcile(workflows: [Workflow]) {
        for watcher in watchers.values { watcher.stop() }
        watchers = [:]
        issues = [:]
        watchingWorkflowIDs = []

        for workflow in workflows {
            guard let trigger = workflow.fileTrigger, trigger.isEnabled else { continue }
            guard FileTriggerSupport.fileInputIndex(
                in: workflow,
                preferredStepID: trigger.inputStepID
            ) != nil else {
                issues[workflow.id] = "The demonstrated file field is no longer available. Choose it again to resume this trigger."
                continue
            }
            let folderURL = URL(fileURLWithPath: trigger.folderPath, isDirectory: true).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                issues[workflow.id] = "The watched folder is unavailable. Choose it again to resume this trigger."
                continue
            }
            do {
                let watcher = try WatchedFolder(
                    workflowID: workflow.id,
                    folderURL: folderURL,
                    kind: trigger.kind,
                    deliver: { [weak self] fileURL in
                        Task { @MainActor in self?.prepareRun(workflow: workflow, fileURL: fileURL) }
                    },
                    fail: { [weak self] message in
                        Task { @MainActor in
                            self?.issues[workflow.id] = message
                            self?.watchingWorkflowIDs.remove(workflow.id)
                        }
                    }
                )
                watchers[workflow.id] = watcher
                watchingWorkflowIDs.insert(workflow.id)
            } catch {
                issues[workflow.id] = "Neloa could not watch this folder: \(error.localizedDescription)"
            }
        }
    }

    func remove(workflowID: UUID) {
        watchers.removeValue(forKey: workflowID)?.stop()
        issues[workflowID] = nil
        watchingWorkflowIDs.remove(workflowID)
        runRouter.removeRequests(for: workflowID)
    }

    private func prepareRun(workflow: Workflow, fileURL: URL) {
        runRouter.enqueue(AutomationRunRequest(
            workflowID: workflow.id,
            initialInstruction: FileTriggerSupport.instruction(for: fileURL),
            source: .watchedFolder
        ))
        NSApplication.shared.requestUserAttention(.informationalRequest)
    }
}
