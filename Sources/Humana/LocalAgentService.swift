import Foundation

@MainActor
final class LocalAgentService: ObservableObject {
    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "localModelName") }
    }
    @Published private(set) var isPlanning = false
    @Published var status = "Local agent ready"

    init() {
        self.modelName = UserDefaults.standard.string(forKey: "localModelName") ?? "qwen3-vl:4b"
    }

    func makePlan(workflow: Workflow, instruction: String) async -> RunPlan {
        guard !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return RunPlanner.plan(workflow: workflow, instruction: instruction)
        }
        isPlanning = true
        defer { isPlanning = false }

        do {
            let response = try await query(prompt: RunPlanner.prompt(workflow: workflow, instruction: instruction))
            status = "Planned locally with \(modelName)"
            return RunPlanner.plan(workflow: workflow, instruction: instruction, agentResponse: response)
        } catch {
            status = "Local model unavailable—used safe built-in planning"
            return RunPlanner.plan(workflow: workflow, instruction: instruction)
        }
    }

    private func query(prompt: String) async throws -> AgentPlanResponse {
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

    enum AgentError: Error { case badResponse }
}
