import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class LocalAgentService: ObservableObject {
    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "localModelName") }
    }
    @Published private(set) var isPlanning = false
    @Published var status = "Local agent ready"

    init() {
        self.modelName = UserDefaults.standard.string(forKey: "localModelName") ?? "qwen3-vl:4b"
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            self.status = "Apple on-device agent ready"
        }
        #endif
    }

    func makePlan(workflow: Workflow, instruction: String) async -> RunPlan {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RunPlanner.plan(workflow: workflow, instruction: instruction)
        }
        isPlanning = true
        defer { isPlanning = false }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let response = try await queryApple(prompt: RunPlanner.prompt(workflow: workflow, instruction: instruction))
                status = "Planned on device with Apple Intelligence"
                return validatedPlan(workflow: workflow, instruction: instruction, response: response)
            } catch {
                status = "Apple agent unavailable—trying local Qwen"
            }
        }
        #endif

        do {
            let response = try await queryOllama(prompt: RunPlanner.prompt(workflow: workflow, instruction: instruction))
            status = "Planned locally with \(modelName)"
            return validatedPlan(workflow: workflow, instruction: instruction, response: response)
        } catch {
            status = "Local model unavailable—used safe built-in planning"
            return RunPlanner.plan(workflow: workflow, instruction: instruction)
        }
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func queryApple(prompt: String) async throws -> AgentPlanResponse {
        let session = LanguageModelSession(instructions: "You are Humana's private on-device run planner. Follow the requested JSON schema exactly and do not include markdown fences.")
        let response = try await session.respond(to: prompt, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 700))
        guard let data = extractJSONObject(from: response.content).data(using: .utf8) else { throw AgentError.badResponse }
        return try JSONDecoder().decode(AgentPlanResponse.self, from: data)
    }
    #endif

    private func queryOllama(prompt: String) async throws -> AgentPlanResponse {
        guard let url = URL(string: "http://127.0.0.1:11434/api/chat") else { throw AgentError.badResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": modelName,
            "stream": false,
            "format": "json",
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8) else { throw AgentError.badResponse }
        return try JSONDecoder().decode(AgentPlanResponse.self, from: contentData)
    }

    private func extractJSONObject(from content: String) -> String {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}"), start <= end else { return content }
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

    enum AgentError: Error { case badResponse }
}
