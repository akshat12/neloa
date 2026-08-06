import Foundation

enum LocalModelStatus: Equatable, Sendable {
    case checking
    case unavailable(String)
    case notInstalled
    case downloading(Double)
    case loading
    case ready
    case failed(String)
}

struct LocalModelHardware: Equatable, Sendable {
    static let minimumMemoryBytes: UInt64 = 16 * 1_024 * 1_024 * 1_024
    static let minimumFreeDiskBytes: Int64 = 6 * 1_024 * 1_024 * 1_024

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

    var eligibilityIssue: String? {
        if !isAppleSilicon {
            return "The visual model requires an Apple silicon Mac."
        }
        if physicalMemoryBytes < Self.minimumMemoryBytes {
            return "The visual model requires at least 16 GB of memory."
        }
        if freeDiskBytes > 0, freeDiskBytes < Self.minimumFreeDiskBytes {
            return "Free at least 6 GB of storage to install the visual model."
        }
        return nil
    }

    var memoryLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(physicalMemoryBytes), countStyle: .memory)
    }
}

enum LocalModelPaths {
    static let modelID = "lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit"
    static let displayName = "Qwen3-VL 4B"
    static let downloadSizeLabel = "3.1 GB"

    static var modelsDirectory: URL {
        BrandMigration.applicationSupportDirectory.appendingPathComponent("Models", isDirectory: true)
    }

    static var cacheDirectory: URL {
        modelsDirectory.appendingPathComponent("HuggingFace", isDirectory: true)
    }

    static var installMarkerURL: URL {
        modelsDirectory.appendingPathComponent("qwen3-vl-4b.ready")
    }

    static var isInstalled: Bool {
        guard let marker = try? String(contentsOf: installMarkerURL, encoding: .utf8) else { return false }
        return marker.trimmingCharacters(in: .whitespacesAndNewlines) == modelID
    }

    static func prepareDirectories() throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    static func markInstalled() throws {
        try prepareDirectories()
        try Data(modelID.utf8).write(to: installMarkerURL, options: .atomic)
    }

    static func clearInstallMarker() {
        try? FileManager.default.removeItem(at: installMarkerURL)
    }
}
