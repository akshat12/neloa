import Foundation

enum LocalModelTier: String, CaseIterable, Identifiable, Sendable {
    case balanced4Bit
    case quality8Bit

    static let storageKey = "NeloaLocalModelTier"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced4Bit: "Balanced"
        case .quality8Bit: "Higher precision"
        }
    }

    var precisionLabel: String {
        switch self {
        case .balanced4Bit: "4-bit"
        case .quality8Bit: "8-bit"
        }
    }

    var modelID: String {
        switch self {
        case .balanced4Bit: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit"
        case .quality8Bit: "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-8bit"
        }
    }

    var modelRevision: String {
        switch self {
        case .balanced4Bit: "552af30c9952c44f1e1a27c7c5810ded58e892bc"
        case .quality8Bit: "e73e3fbb7dae9f23283989a81a05d327a3958f3f"
        }
    }

    var downloadSizeLabel: String {
        switch self {
        case .balanced4Bit: "3.1 GB"
        case .quality8Bit: "5.1 GB"
        }
    }

    var minimumFreeDiskBytes: Int64 {
        switch self {
        case .balanced4Bit: 6 * 1_024 * 1_024 * 1_024
        case .quality8Bit: 10 * 1_024 * 1_024 * 1_024
        }
    }

    var recommendation: String {
        switch self {
        case .balanced4Bit: "Recommended for 16 GB Macs"
        case .quality8Bit: "Best with 24 GB or more"
        }
    }

    static func resolve(_ rawValue: String?) -> LocalModelTier {
        rawValue.flatMap(LocalModelTier.init(rawValue:)) ?? .balanced4Bit
    }
}

enum LocalModelStatus: Equatable, Sendable {
    case checking
    case unavailable(String)
    case notInstalled
    case downloading(Double)
    case loading
    case removing
    case ready
    case failed(String)
}

struct LocalModelHardware: Equatable, Sendable {
    static let minimumMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024

    var isAppleSilicon: Bool
    var physicalMemoryBytes: UInt64
    var freeDiskBytes: Int64

    static var current: LocalModelHardware {
        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif

        let diskProbe = LocalModelPaths.modelsDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourceValues = try? diskProbe.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        return LocalModelHardware(
            isAppleSilicon: isAppleSilicon,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            freeDiskBytes: resourceValues?.volumeAvailableCapacityForImportantUsage ?? 0
        )
    }

    var eligibilityIssue: String? { eligibilityIssue(for: .balanced4Bit) }

    func eligibilityIssue(for tier: LocalModelTier) -> String? {
        if !isAppleSilicon {
            return "The visual model requires an Apple silicon Mac."
        }
        if physicalMemoryBytes < Self.minimumMemoryBytes {
            return "The visual model requires at least 16 GB of memory."
        }
        if freeDiskBytes > 0, freeDiskBytes < tier.minimumFreeDiskBytes {
            return "Free at least \(tier == .quality8Bit ? "10" : "6") GB of storage to install this model tier."
        }
        return nil
    }

    var memoryLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(physicalMemoryBytes), countStyle: .memory)
    }
}

enum LocalModelPaths {
    static let displayName = "Qwen3-VL 4B"

    static var modelsDirectory: URL {
        BrandMigration.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var cacheDirectory: URL {
        modelsDirectory.appendingPathComponent("HuggingFace", isDirectory: true)
    }

    static func installMarkerURL(for tier: LocalModelTier) -> URL {
        let filename = tier == .balanced4Bit ? "qwen3-vl-4b.ready" : "qwen3-vl-4b-8bit.ready"
        return modelsDirectory.appendingPathComponent(filename)
    }

    static func repositoryDirectory(for tier: LocalModelTier) -> URL {
        let repositoryFolder = "models--" + tier.modelID.replacingOccurrences(of: "/", with: "--")
        return cacheDirectory.appendingPathComponent(repositoryFolder, isDirectory: true)
    }

    static func snapshotDirectory(for tier: LocalModelTier) -> URL {
        repositoryDirectory(for: tier)
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(tier.modelRevision, isDirectory: true)
    }

    static func hasCachedFiles(for tier: LocalModelTier) -> Bool {
        FileManager.default.fileExists(atPath: repositoryDirectory(for: tier).path)
    }

    static func isInstalled(_ tier: LocalModelTier) -> Bool {
        guard let marker = try? String(contentsOf: installMarkerURL(for: tier), encoding: .utf8) else { return false }
        guard marker.trimmingCharacters(in: .whitespacesAndNewlines) == installMarker(for: tier) else { return false }
        let requiredFiles = ["config.json", "tokenizer.json", "model.safetensors"]
        return requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: snapshotDirectory(for: tier).appendingPathComponent($0).path)
        }
    }

    static func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func markInstalled(_ tier: LocalModelTier) throws {
        try prepareDirectories()
        try Data(installMarker(for: tier).utf8).write(to: installMarkerURL(for: tier), options: .atomic)
    }

    static func clearInstallMarker(_ tier: LocalModelTier) {
        try? FileManager.default.removeItem(at: installMarkerURL(for: tier))
    }

    private static func installMarker(for tier: LocalModelTier) -> String {
        "\(tier.modelID)@\(tier.modelRevision)"
    }
}
