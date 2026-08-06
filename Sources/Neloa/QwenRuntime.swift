import Foundation

enum QwenRuntimeError: LocalizedError {
    case runtimeNotBundled
    case modelNotLoaded
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .runtimeNotBundled:
            "This development build does not include the Apple GPU model runtime."
        case .modelNotLoaded:
            "The local visual model has not finished loading."
        case .invalidResponse:
            "The local visual model returned an answer Neloa could not verify."
        }
    }
}

#if NELOA_MLX
import HuggingFace
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

actor QwenRuntime {
    private var container: ModelContainer?

    func load(progress: @Sendable @escaping (Double) -> Void) async throws {
        if container != nil {
            progress(1)
            return
        }

        try LocalModelPaths.prepareDirectories()
        let hub = HubClient(
            userAgent: "Neloa macOS",
            cache: HubCache(cacheDirectory: LocalModelPaths.cacheDirectory)
        )
        let configuration = ModelConfiguration(id: LocalModelPaths.modelID)
        let loaded = try await loadModelContainer(
            from: #hubDownloader(hub),
            using: #huggingFaceTokenizerLoader(),
            configuration: configuration,
            useLatest: false,
            progressHandler: { download in
                progress(download.fractionCompleted)
            }
        )
        container = loaded
        try LocalModelPaths.markInstalled()
        progress(1)
    }

    func respond(
        prompt: String,
        imageURLs: [URL],
        instructions: String,
        maximumTokens: Int = 1_100
    ) async throws -> String {
        guard let container else { throw QwenRuntimeError.modelNotLoaded }
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(
                maxTokens: maximumTokens,
                temperature: 0.1,
                topP: 0.9,
                repetitionPenalty: 1.05
            )
        )
        return try await session.respond(
            to: prompt,
            images: imageURLs.map(UserInput.Image.url),
            videos: []
        )
    }

    func unload() {
        container = nil
    }
}
#else
actor QwenRuntime {
    func load(progress: @Sendable @escaping (Double) -> Void) async throws {
        throw QwenRuntimeError.runtimeNotBundled
    }

    func respond(
        prompt: String,
        imageURLs: [URL],
        instructions: String,
        maximumTokens: Int = 1_100
    ) async throws -> String {
        throw QwenRuntimeError.runtimeNotBundled
    }

    func unload() {}
}
#endif
