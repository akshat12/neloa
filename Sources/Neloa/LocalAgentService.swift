import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class LocalAgentService: ObservableObject {
    @Published private(set) var isPlanning = false
    @Published private(set) var isLearning = false
    @Published var status = "Local agent ready"
    @Published private(set) var modelStatus: LocalModelStatus = .checking
    @Published private(set) var selectedTier: LocalModelTier

    let hardware: LocalModelHardware
    private let qwen = QwenRuntime()
    private var setupTask: Task<Bool, Never>?
    private let defaults: UserDefaults?

    init(
        hardware: LocalModelHardware = .current,
        selectedTier: LocalModelTier? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.hardware = hardware
        self.selectedTier = selectedTier ?? LocalModelTier.resolve(defaults.string(forKey: LocalModelTier.storageKey))
        self.defaults = selectedTier == nil ? defaults : nil
        refreshModelStatus()
        if LocalModelPaths.isInstalled(self.selectedTier),
           hardware.eligibilityIssue(for: self.selectedTier) == nil,
           Self.isQwenRuntimeBundled {
            Task { await setupModel() }
        } else {
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
                status = "Apple on-device fallback ready"
            }
            #endif
        }
    }

    static var isQwenRuntimeBundled: Bool {
        #if NELOA_MLX
        true
        #else
        false
        #endif
    }

    func refreshModelStatus() {
        switch modelStatus {
        case .downloading, .loading, .removing, .ready, .failed:
            return
        case .checking, .notInstalled, .unavailable:
            break
        }
        if let issue = hardware.eligibilityIssue(for: selectedTier) {
            modelStatus = .unavailable(issue)
        } else if !Self.isQwenRuntimeBundled {
            modelStatus = .unavailable("This development build does not include the Apple GPU model runtime.")
        } else if LocalModelPaths.isInstalled(selectedTier) {
            if modelStatus != .ready && modelStatus != .loading {
                modelStatus = .checking
            }
        } else {
            modelStatus = .notInstalled
        }
    }

    func setupModel() async {
        if let setupTask {
            _ = await setupTask.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await self.performModelSetup()
        }
        setupTask = task
        _ = await task.value
        setupTask = nil
    }

    private func performModelSetup() async -> Bool {
        let tier = selectedTier
        guard hardware.eligibilityIssue(for: tier) == nil else {
            modelStatus = .unavailable(hardware.eligibilityIssue(for: tier) ?? "This Mac is not supported.")
            return false
        }
        guard Self.isQwenRuntimeBundled else {
            modelStatus = .unavailable("This development build does not include the Apple GPU model runtime.")
            return false
        }

        let wasInstalled = LocalModelPaths.isInstalled(tier)
        modelStatus = wasInstalled ? .loading : .downloading(0)
        status = wasInstalled ? "Loading local visual intelligence…" : "Downloading local visual intelligence…"
        do {
            try await qwen.load(tier: tier) { [weak self] progress in
                Task { @MainActor in
                    guard let self, !wasInstalled else { return }
                    let progress = min(max(progress, 0), 1)
                    self.modelStatus = progress >= 0.999 ? .loading : .downloading(progress)
                }
            }
            modelStatus = .ready
            status = "Qwen \(tier.precisionLabel) visual intelligence ready on this Mac"
            return true
        } catch {
            LocalModelPaths.clearInstallMarker(tier)
            if error is CancellationError || Task.isCancelled {
                modelStatus = .notInstalled
                status = "Model download paused; Neloa will resume it next time"
                return false
            }
            modelStatus = .failed(friendlyModelError(error))
            status = "Local visual intelligence needs attention"
            return false
        }
    }

    func cancelModelSetup() async {
        guard modelStatus.isPreparing else { return }
        modelStatus = .removing
        status = "Pausing the model download…"
        setupTask?.cancel()
        await qwen.cancelLoad()
        if let setupTask {
            _ = await setupTask.value
        }
        setupTask = nil
        LocalModelPaths.clearInstallMarker(selectedTier)
        modelStatus = .notInstalled
        status = "Model download paused; Neloa will resume it next time"
    }

    func removeModel() async {
        let tier = selectedTier
        modelStatus = .removing
        status = "Removing the local visual model…"
        setupTask?.cancel()
        await qwen.cancelLoad()
        if let setupTask {
            _ = await setupTask.value
        }
        setupTask = nil
        await qwen.unload()
        do {
            let repository = LocalModelPaths.repositoryDirectory(for: tier)
            if FileManager.default.fileExists(atPath: repository.path) {
                try FileManager.default.removeItem(at: repository)
            }
            LocalModelPaths.clearInstallMarker(tier)
            modelStatus = .notInstalled
            status = "Qwen \(tier.precisionLabel) model removed"
        } catch {
            modelStatus = .failed("Neloa could not remove the model: \(error.localizedDescription)")
            status = "Local visual intelligence needs attention"
        }
    }

    func selectTier(_ tier: LocalModelTier) async {
        guard tier != selectedTier else { return }
        setupTask?.cancel()
        await qwen.cancelLoad()
        if let setupTask { _ = await setupTask.value }
        setupTask = nil
        await qwen.unload()
        selectedTier = tier
        defaults?.set(tier.rawValue, forKey: LocalModelTier.storageKey)
        modelStatus = .checking
        status = "Checking the \(tier.precisionLabel) model…"
        refreshModelStatus()
        if LocalModelPaths.isInstalled(tier), hardware.eligibilityIssue(for: tier) == nil {
            await setupModel()
        }
    }

    func learnWorkflow(candidate: Workflow, recordingURL: URL?, captureFrame: CGRect?) async -> Workflow {
        guard await ensureQwenReady() else {
            status = "Built safely from captured actions; visual understanding is not set up"
            return candidate
        }

        isLearning = true
        defer { isLearning = false }
        do {
            let frames: [WorkflowEvidenceFrame]
            if let recordingURL, FileManager.default.fileExists(atPath: recordingURL.path) {
                frames = try await WorkflowEvidenceExtractor.extract(
                    recordingURL: recordingURL,
                    steps: candidate.steps,
                    captureFrame: captureFrame
                )
            } else {
                frames = []
            }
            defer { removeTemporaryEvidence(frames) }
            return try await learnWorkflowWithQwen(candidate: candidate, frames: frames)
        } catch {
            status = "Visual understanding could not finish; kept the captured actions"
            return candidate
        }
    }

    func learnWorkflow(candidate: Workflow, evidenceFrames: [WorkflowEvidenceFrame]) async -> Workflow {
        guard await ensureQwenReady() else { return candidate }
        isLearning = true
        defer { isLearning = false }
        do {
            return try await learnWorkflowWithQwen(candidate: candidate, frames: evidenceFrames)
        } catch {
            fputs("Neloa Qwen visual-learning error: \(String(describing: error))\n", stderr)
            status = "Visual understanding could not finish; kept the captured actions"
            return candidate
        }
    }

    func makePlan(workflow: Workflow, instruction: String) async -> RunPlan {
        guard !RunPlanner.isUnchangedInstruction(instruction) else {
            status = "Ready to run the saved workflow"
            return RunPlanner.plan(workflow: workflow, instruction: instruction)
        }
        if let spreadsheetPlan = RunPlanner.spreadsheetCellPlan(workflow: workflow, instruction: instruction) {
            status = "Planned with safe spreadsheet navigation"
            return spreadsheetPlan
        }
        isPlanning = true
        defer { isPlanning = false }

        if await ensureQwenReady() {
            do {
                let response = try await queryQwen(
                    prompt: RunPlanner.prompt(workflow: workflow, instruction: instruction)
                )
                status = "Planned privately with Qwen"
                return validatedPlan(workflow: workflow, instruction: instruction, response: response)
            } catch {
                if error is CancellationError || Task.isCancelled {
                    status = "Planning cancelled"
                    return RunPlanner.plan(workflow: workflow, instruction: "")
                }
                fputs("Neloa Qwen planning error: \(String(describing: error))\n", stderr)
                status = "Qwen could not finish—trying the on-device fallback"
            }
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let response = try await queryApple(prompt: RunPlanner.prompt(workflow: workflow, instruction: instruction))
                status = "Planned with the Apple on-device fallback"
                return validatedPlan(workflow: workflow, instruction: instruction, response: response)
            } catch {
                status = "On-device models unavailable—used safe built-in planning"
            }
        }
        #endif

        return RunPlanner.plan(workflow: workflow, instruction: instruction)
    }

    private func ensureQwenReady() async -> Bool {
        if modelStatus == .ready { return true }
        if modelStatus.isPreparing {
            await setupModel()
            return modelStatus == .ready
        }
        guard LocalModelPaths.isInstalled(selectedTier) else { return false }
        await setupModel()
        return modelStatus == .ready
    }

    private func queryQwen(prompt: String) async throws -> AgentPlanResponse {
        let content = try await qwen.respond(
            prompt: prompt,
            imageURLs: [],
            instructions: "You are Neloa's private local run planner. Return only the requested JSON object. Do not include markdown fences.",
            maximumTokens: 700
        )
        guard let data = QwenResponseSupport.jsonData(
            from: content,
            topLevelKeys: ["summary", "replacements"]
        ) else {
            throw AgentError.badResponse
        }
        return try JSONDecoder().decode(AgentPlanResponse.self, from: data)
    }

    private func learnWorkflowWithQwen(
        candidate: Workflow,
        frames: [WorkflowEvidenceFrame]
    ) async throws -> Workflow {
        let hasCapturedReplayActions = candidate.steps.contains {
            [.openURL, .click, .typeText, .keyPress].contains($0.kind)
        }
        let hasCapturedTyping = candidate.steps.contains { $0.kind == .typeText }
        let recoveryFrames = WorkflowEvidenceExtractor.prioritizedRecoveryFrames(frames)
        // A partial event tap is common in browsers: clicks may be captured
        // while secure-input transitions or accessibility clients hide the
        // actual keystrokes. Treat grounded spreadsheet before/after evidence
        // as recovery input whenever no typing survived, not only when the
        // entire event stream is empty.
        let canRecoverMissingTyping = !hasCapturedTyping
            && recoveryFrames.count > 1
            && recoveryFrames.count < frames.count
        let modelFrames = canRecoverMissingTyping
            ? recoveryFrames
            : (hasCapturedReplayActions ? frames : recoveryFrames)
        let usesGroundedPerFrameRecovery = canRecoverMissingTyping
            || (!hasCapturedReplayActions && modelFrames.count > 1 && modelFrames.count < frames.count)
        let content: String
        let response: LearnedWorkflowResponse
        if usesGroundedPerFrameRecovery {
            var recovered: [(response: LearnedWorkflowResponse, frameIndex: Int, time: TimeInterval)] = []
            var rawResponses: [String] = []
            for (index, frame) in modelFrames.enumerated() {
                let frameContent = try await qwen.respond(
                    prompt: WorkflowLearner.singleFrameRecoveryPrompt(candidate: candidate, frame: frame),
                    imageURLs: [frame.imageURL],
                    instructions: WorkflowLearner.instructions,
                    maximumTokens: 360
                )
                rawResponses.append(frameContent)
                if let decoded = try? WorkflowLearner.decode(frameContent),
                   let grounded = WorkflowLearner.groundedSingleFrameResponse(decoded, frame: frame) {
                    recovered.append((grounded, index, frame.time))
                } else if let grounded = WorkflowLearner.groundedRecoveryResponse(
                    from: frameContent,
                    frame: frame
                ) {
                    recovered.append((grounded, index, frame.time))
                }
            }
            response = WorkflowLearner.mergingRecoveryResponses(recovered)
            content = rawResponses.joined(separator: "\n--- next evidence frame ---\n")
        } else {
            let prompt = try WorkflowLearner.prompt(candidate: candidate, frames: modelFrames)
            content = try await qwen.respond(
                prompt: prompt,
                imageURLs: modelFrames.map(\.imageURL),
                instructions: WorkflowLearner.instructions,
                maximumTokens: hasCapturedReplayActions ? 600 : 850
            )
            response = try WorkflowLearner.decode(content)
        }
        if isQwenSmokeTest {
            fputs("Neloa Qwen visual-learning response: \(content)\n", stderr)
        }
        let learned = WorkflowSemanticEnricher.enrich(
            WorkflowLearner.apply(response, to: candidate, frames: modelFrames)
        )
        let visualDraftCount = learned.steps.filter { $0.origin == .visual && $0.kind != .openApp }.count
        status = visualDraftCount > 0
            ? "Qwen drafted \(visualDraftCount) actions from the recording for your review"
            : "Learned privately with Qwen visual intelligence"
        return learned
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func queryApple(prompt: String) async throws -> AgentPlanResponse {
        let session = LanguageModelSession(instructions: "You are Neloa's private on-device run planner. Follow the requested JSON schema exactly and do not include markdown fences.")
        let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 700))
        guard let data = extractJSONObject(from: response.content).data(using: .utf8) else {
            throw AgentError.badResponse
        }
        return try JSONDecoder().decode(AgentPlanResponse.self, from: data)
    }
    #endif

    private func extractJSONObject(from content: String) -> String {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start <= end else {
            return content
        }
        return String(content[start...end])
    }

    private func validatedPlan(workflow: Workflow, instruction: String, response: AgentPlanResponse) -> RunPlan {
        let grounded = RunPlanner.plan(workflow: workflow, instruction: instruction)
        let agentPlan = RunPlanner.plan(workflow: workflow, instruction: instruction, agentResponse: response)
        // Qwen is still confined to known typeText step IDs by RunPlanner, so a
        // multi-field response is safe to prefer over the one-value parser.
        // The deterministic parser remains the fallback when the model cannot
        // produce a valid grounded replacement.
        guard agentPlan.changes.isEmpty else { return agentPlan }
        return grounded
    }

    private func removeTemporaryEvidence(_ frames: [WorkflowEvidenceFrame]) {
        let directories = Set(frames.map { $0.imageURL.deletingLastPathComponent() })
        for directory in directories where directory.lastPathComponent.hasPrefix("NeloaEvidence-") {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func friendlyModelError(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "The download timed out. Try again to resume where it stopped."
        }
        return "Neloa couldn't prepare the model. Try again, or reset the download below."
    }

    private var isQwenSmokeTest: Bool {
        CommandLine.arguments.contains("--qwen-smoke-test")
            || CommandLine.arguments.contains("--qwen-8bit-smoke-test")
            || CommandLine.arguments.contains("--qwen-recording-test")
            || ProcessInfo.processInfo.environment["NELOA_MODEL_EVAL_VERBOSE"] == "1"
    }

    enum AgentError: Error { case badResponse }
}

private extension LocalModelStatus {
    var isPreparing: Bool {
        switch self {
        case .downloading, .loading: true
        default: false
        }
    }
}
