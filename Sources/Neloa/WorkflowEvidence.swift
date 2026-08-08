import AppKit
@preconcurrency import AVFoundation
import Foundation
import Vision

struct WorkflowEvidenceFrame: Sendable {
    var time: TimeInterval
    var imageURL: URL
    var recognizedText: [String]
    var imageWidth: Int? = nil
    var imageHeight: Int? = nil
    var captureFrame: CGRect? = nil
}

enum WorkflowEvidenceExtractor {
    static let maximumFrameCount = 8

    static func purgeStaleTemporaryEvidence(olderThan age: TimeInterval = 60 * 60) {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let contents = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-age)
        for url in contents where url.lastPathComponent.hasPrefix("NeloaEvidence-") {
            let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if modified.map({ $0 < cutoff }) ?? true {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    static func extract(
        recordingURL: URL,
        steps: [WorkflowStep],
        captureFrame: CGRect?
    ) async throws -> [WorkflowEvidenceFrame] {
        try await Task.detached(priority: .userInitiated) {
            try await extractFrames(recordingURL: recordingURL, steps: steps, captureFrame: captureFrame)
        }.value
    }

    static func sampleTimes(steps: [WorkflowStep], maximumCount: Int = maximumFrameCount) -> [TimeInterval] {
        let usefulKinds: Set<WorkflowStepKind> = [.click, .typeText, .keyPress, .decision, .approval]
        var times = steps
            .filter { usefulKinds.contains($0.kind) }
            .map { max(0, $0.time - ($0.kind == .click ? 0.18 : 0.05)) }
            .sorted()

        times = times.reduce(into: []) { result, time in
            if result.last.map({ abs($0 - time) >= 0.3 }) ?? true {
                result.append(time)
            }
        }

        guard times.count > maximumCount, maximumCount > 1 else {
            return Array(times.prefix(maximumCount))
        }

        return (0..<maximumCount).map { position in
            let fraction = Double(position) / Double(maximumCount - 1)
            let index = Int((fraction * Double(times.count - 1)).rounded())
            return times[index]
        }
    }

    private static func extractFrames(
        recordingURL: URL,
        steps: [WorkflowStep],
        captureFrame: CGRect?
    ) async throws -> [WorkflowEvidenceFrame] {
        let times = sampleTimes(steps: steps)
        guard !times.isEmpty else { return [] }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaEvidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            let asset = AVURLAsset(url: recordingURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1_280, height: 1_280)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

            let requestedTimes = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
            var frames: [WorkflowEvidenceFrame] = []
            for await result in generator.images(for: requestedTimes) {
                guard case .success(requestedTime: let requestedTime, let image, actualTime: let actualTime) = result else {
                    continue
                }
                let imageURL = temporaryDirectory.appendingPathComponent("frame-\(frames.count + 1).png")
                try pngData(for: image).write(to: imageURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)
                frames.append(WorkflowEvidenceFrame(
                    time: actualTime.seconds.isFinite ? actualTime.seconds : requestedTime.seconds,
                    imageURL: imageURL,
                    recognizedText: recognizedText(in: image),
                    imageWidth: image.width,
                    imageHeight: image.height,
                    captureFrame: captureFrame
                ))
            }
            if frames.isEmpty {
                try? FileManager.default.removeItem(at: temporaryDirectory)
            }
            return frames
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func pngData(for image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }

    private static func recognizedText(in image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.012
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(24)
            .map { String($0.prefix(120)) }
    }
}
