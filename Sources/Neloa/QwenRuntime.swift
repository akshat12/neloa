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
import MLX
import MLXHuggingFace
import MLXLMCommon
import MLXVLM
import Tokenizers

actor QwenRuntime {
    private var container: ModelContainer?
    private var loadTask: Task<ModelContainer, Error>?
    private var loadedTier: LocalModelTier?
    private var loadingTier: LocalModelTier?
    private var loadEpoch: UInt = 0
    private var generationInProgress = false
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []

    func load(tier: LocalModelTier, progress: @Sendable @escaping (Double) -> Void) async throws {
        if container != nil, loadedTier == tier {
            progress(1)
            return
        }

        if container != nil, loadedTier != tier {
            container = nil
            loadedTier = nil
            Memory.clearCache()
        }

        if let pendingLoad = loadTask {
            if loadingTier == tier {
                let epoch = loadEpoch
                let loaded = try await pendingLoad.value
                guard epoch == loadEpoch else { throw CancellationError() }
                container = loaded
                loadedTier = tier
                self.loadTask = nil
                loadingTier = nil
                progress(1)
                return
            }

            loadEpoch &+= 1
            pendingLoad.cancel()
            loadTask = nil
            loadingTier = nil
        }

        let epoch = loadEpoch
        let task = Task<ModelContainer, Error> {
            try LocalModelPaths.prepareDirectories()
            Memory.cacheLimit = 64 * 1_024 * 1_024
            let networkConfiguration = URLSessionConfiguration.default
            networkConfiguration.timeoutIntervalForRequest = 10 * 60
            networkConfiguration.timeoutIntervalForResource = 2 * 60 * 60
            networkConfiguration.waitsForConnectivity = true
            let hub = HubClient(
                session: URLSession(configuration: networkConfiguration),
                userAgent: "Neloa macOS",
                cache: HubCache(cacheDirectory: LocalModelPaths.cacheDirectory)
            )
            let configuration = ModelConfiguration(
                id: tier.modelID,
                revision: tier.modelRevision
            )
            let loaded = try await loadModelContainer(
                from: #hubDownloader(hub),
                using: #huggingFaceTokenizerLoader(),
                configuration: configuration,
                useLatest: false,
                progressHandler: { download in
                    progress(download.fractionCompleted)
                }
            )
            try Task.checkCancellation()
            try LocalModelPaths.markInstalled(tier)
            return loaded
        }
        loadingTier = tier
        loadTask = task
        do {
            let loaded = try await task.value
            guard epoch == loadEpoch else { throw CancellationError() }
            container = loaded
            loadedTier = tier
            loadTask = nil
            loadingTier = nil
            progress(1)
        } catch {
            if epoch == loadEpoch {
                container = nil
                loadTask = nil
                loadingTier = nil
            }
            throw error
        }
    }

    func respond(
        prompt: String,
        imageURLs: [URL],
        instructions: String,
        maximumTokens: Int = 1_100
    ) async throws -> String {
        await acquireGenerationSlot()
        defer {
            Memory.clearCache()
            releaseGenerationSlot()
        }
        guard let container else { throw QwenRuntimeError.modelNotLoaded }
        Memory.cacheLimit = 64 * 1_024 * 1_024
        let session = ChatSession(
            container,
            instructions: instructions,
            generateParameters: GenerateParameters(
                maxTokens: maximumTokens,
                maxKVSize: 2_048,
                kvBits: 8,
                temperature: 0,
                topP: 0.9,
                repetitionPenalty: 1.05
            )
        )
        return try await session.respond(
            to: prompt,
            images: imageURLs.map(UserInput.Image.url),
            videos: [],
            audios: []
        )
    }

    func unload() async {
        await acquireGenerationSlot()
        container = nil
        loadedTier = nil
        Memory.clearCache()
        releaseGenerationSlot()
    }

    func cancelLoad() async {
        loadEpoch &+= 1
        let task = loadTask
        task?.cancel()
        if let task {
            _ = try? await task.value
        }
        loadTask = nil
        container = nil
        if let loadingTier { LocalModelPaths.clearInstallMarker(loadingTier) }
        loadingTier = nil
        loadedTier = nil
        Memory.clearCache()
    }

    private func acquireGenerationSlot() async {
        if !generationInProgress {
            generationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            generationWaiters.append(continuation)
        }
    }

    private func releaseGenerationSlot() {
        if generationWaiters.isEmpty {
            generationInProgress = false
        } else {
            generationWaiters.removeFirst().resume()
        }
    }
}
#else
actor QwenRuntime {
    func load(tier: LocalModelTier, progress: @Sendable @escaping (Double) -> Void) async throws {
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

    func unload() async {}
    func cancelLoad() async {}
}
#endif
