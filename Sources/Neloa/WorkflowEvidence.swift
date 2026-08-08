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
    var focusStepID: UUID? = nil
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

    static func focusedClickFrames(
        candidate: Workflow,
        frames: [WorkflowEvidenceFrame]
    ) async throws -> [WorkflowEvidenceFrame] {
        try await Task.detached(priority: .userInitiated) {
            try makeFocusedClickFrames(candidate: candidate, frames: frames)
        }.value
    }

    private static func makeFocusedClickFrames(
        candidate: Workflow,
        frames: [WorkflowEvidenceFrame]
    ) throws -> [WorkflowEvidenceFrame] {
        let clickSteps = candidate.steps.filter(WorkflowLearner.isGenericCapturedClick)
        guard !clickSteps.isEmpty else { return [] }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaEvidence-Focus-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            var focused: [WorkflowEvidenceFrame] = []
            for step in clickSteps {
                guard let match = frames.enumerated().min(by: {
                    abs($0.element.time - step.time) < abs($1.element.time - step.time)
                }),
                let location = WorkflowLearner.evidenceLocation(for: step, frames: [match.element]),
                let imageData = try? Data(contentsOf: match.element.imageURL),
                let sourceImage = NSBitmapImageRep(data: imageData)?.cgImage,
                let originalCaptureFrame = match.element.captureFrame else { continue }

                let cropWidth = min(CGFloat(sourceImage.width), 420)
                let cropHeight = min(CGFloat(sourceImage.height), 260)
                let originX = min(
                    max(0, location.point.x - cropWidth / 2),
                    CGFloat(sourceImage.width) - cropWidth
                )
                let originYFromTop = min(
                    max(0, location.point.y - cropHeight / 2),
                    CGFloat(sourceImage.height) - cropHeight
                )
                // CGImage cropping uses a bottom-left origin; captured CGEvent
                // coordinates and the model prompt use a top-left origin.
                let cropRect = CGRect(
                    x: originX,
                    y: CGFloat(sourceImage.height) - originYFromTop - cropHeight,
                    width: cropWidth,
                    height: cropHeight
                ).integral
                guard let croppedImage = sourceImage.cropping(to: cropRect) else { continue }

                let url = directory.appendingPathComponent("click-\(focused.count + 1).png")
                try pngData(for: croppedImage).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)

                let scaleX = originalCaptureFrame.width / CGFloat(sourceImage.width)
                let scaleY = originalCaptureFrame.height / CGFloat(sourceImage.height)
                focused.append(WorkflowEvidenceFrame(
                    time: step.time,
                    imageURL: url,
                    recognizedText: [],
                    imageWidth: croppedImage.width,
                    imageHeight: croppedImage.height,
                    captureFrame: CGRect(
                        x: originalCaptureFrame.minX + cropRect.minX * scaleX,
                        y: originalCaptureFrame.minY + originYFromTop * scaleY,
                        width: cropRect.width * scaleX,
                        height: cropRect.height * scaleY
                    ),
                    focusStepID: step.id
                ))
            }
            if focused.isEmpty { try? FileManager.default.removeItem(at: directory) }
            return focused
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
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
