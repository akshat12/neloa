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

    let hardware: LocalModelHardware
    private let qwen = QwenRuntime()

    init(hardware: LocalModelHardware = .current) {
        self.hardware = hardware
        refreshModelStatus()
        if LocalModelPaths.isInstalled, hardware.eligibilityIssue == nil, Self.isQwenRuntimeBundled {
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
        if let issue = hardware.eligibilityIssue {
            modelStatus = .unavailable(issue)
        } else if !Self.isQwenRuntimeBundled {
            modelStatus = .unavailable("This development build does not include the Apple GPU model runtime.")
        } else if LocalModelPaths.isInstalled {
            if modelStatus != .ready && modelStatus != .loading {
                modelStatus = .checking
            }
        } else {
            modelStatus = .notInstalled
        }
    }

    func setupModel() async {
        guard hardware.eligibilityIssue == nil else {
            modelStatus = .unavailable(hardware.eligibilityIssue ?? "This Mac is not supported.")
            return
        }
        guard Self.isQwenRuntimeBundled else {
            modelStatus = .unavailable("This development build does not include the Apple GPU model runtime.")
            return
        }

        let wasInstalled = LocalModelPaths.isInstalled
        modelStatus = wasInstalled ? .loading : .downloading(0)
        status = wasInstalled ? "Loading local visual intelligence…" : "Downloading local visual intelligence…"
        do {
            try await qwen.load { [weak self] progress in
                Task { @MainActor in
                    guard let self, !wasInstalled else { return }
                    self.modelStatus = .downloading(min(max(progress, 0), 1))
                }
            }
            modelStatus = .ready
            status = "Qwen visual intelligence ready on this Mac"
        } catch {
            LocalModelPaths.clearInstallMarker()
            modelStatus = .failed(error.localizedDescription)
            status = "Local visual intelligence needs attention"
        }
    }

    func removeModel() async {
        await qwen.unload()
        try? FileManager.default.removeItem(at: LocalModelPaths.modelsDirectory)
        modelStatus = .notInstalled
        status = "Local visual model removed"
    }

    func learnWorkflow(candidate: Workflow, recordingURL: URL?) async -> Workflow {
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
                    steps: candidate.steps
                )
            } else {
                frames = []
            }
            defer { removeTemporaryEvidence(frames) }

            let prompt = try WorkflowLearner.prompt(candidate: candidate, frames: frames)
            let content = try await qwen.respond(
                prompt: prompt,
                imageURLs: frames.map(\.imageURL),
                instructions: WorkflowLearner.instructions,
                maximumTokens: 1_250
            )
            let response = try WorkflowLearner.decode(content)
            status = "Learned privately with Qwen visual intelligence"
            return WorkflowLearner.apply(response, to: candidate)
        } catch {
            status = "Visual understanding could not finish; kept the captured actions"
            return candidate
        }
    }

    func makePlan(workflow: Workflow, instruction: String) async -> RunPlan {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RunPlanner.plan(workflow: workflow, instruction: instruction)
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
        guard LocalModelPaths.isInstalled else { return false }
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
        guard let data = extractJSONObject(from: content).data(using: .utf8) else {
            throw AgentError.badResponse
        }
        return try JSONDecoder().decode(AgentPlanResponse.self, from: data)
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
        let agentPlan = RunPlanner.plan(workflow: workflow, instruction: instruction, agentResponse: response)
        guard agentPlan.changes.isEmpty else { return agentPlan }

        var grounded = RunPlanner.plan(workflow: workflow, instruction: instruction)
        if !grounded.changes.isEmpty {
            grounded.summary = "\(response.summary) Verified against the requested value."
            return grounded
        }
        return agentPlan
    }

    private func removeTemporaryEvidence(_ frames: [WorkflowEvidenceFrame]) {
        let directories = Set(frames.map { $0.imageURL.deletingLastPathComponent() })
        for directory in directories where directory.lastPathComponent.hasPrefix("NeloaEvidence-") {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    enum AgentError: Error { case badResponse }
}
