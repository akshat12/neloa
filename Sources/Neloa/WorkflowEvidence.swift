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
    var focusReason: String? = nil
}

enum WorkflowEvidenceExtractor {
    static let maximumFrameCount = 8
    private static let maximumCandidateFrameCount = 36

    private struct GeneratedFrame {
        var time: TimeInterval
        var image: CGImage
    }

    private struct VisualChange {
        var previousIndex: Int
        var currentIndex: Int
        var score: Double
        var bounds: CGRect?
    }

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
            .map { step -> TimeInterval in
                let offset: TimeInterval
                switch step.kind {
                case .click: offset = -0.12
                case .typeText: offset = 0.38
                case .keyPress: offset = 0.18
                case .decision, .approval: offset = 0
                default: offset = 0
                }
                return max(0, step.time + offset)
            }
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

    static func sampleTimes(
        steps: [WorkflowStep],
        duration: TimeInterval,
        maximumCount: Int = maximumFrameCount
    ) -> [TimeInterval] {
        guard maximumCount > 0 else { return [] }
        let eventTimes = sampleTimes(steps: steps, maximumCount: maximumCount)
            .map { min(max(0, $0), max(0, duration - 0.08)) }
            .reduce(into: [TimeInterval]()) { result, time in
                if result.last.map({ abs($0 - time) >= 0.12 }) ?? true {
                    result.append(time)
                }
            }
        guard duration.isFinite, duration > 0.05 else { return eventTimes }
        if maximumCount == 1 { return [eventTimes.first ?? 0] }

        // A recording remains useful evidence even when the system event tap did
        // not observe an action (for example, input produced by an accessibility
        // client). Fill the remaining visual budget across the whole recording.
        // Event-adjacent frames still win when native events are available.
        let usableEnd = max(0, duration - 0.08)
        let uniformCount = max(maximumCount, 2)
        let uniformTimes = (0..<uniformCount).map { index in
            let fraction = Double(index) / Double(uniformCount - 1)
            return min(usableEnd, max(0, fraction * usableEnd))
        }

        guard eventTimes.count < maximumCount else { return eventTimes }
        let candidates = uniformTimes.filter { time in
            !eventTimes.contains(where: { abs($0 - time) < 0.28 })
        }
        let remaining = maximumCount - eventTimes.count
        let selectedUniform: [TimeInterval]
        if candidates.count <= remaining {
            selectedUniform = candidates
        } else if remaining == 1 {
            selectedUniform = [candidates[candidates.count / 2]]
        } else {
            selectedUniform = (0..<remaining).map { position in
                let fraction = Double(position) / Double(remaining - 1)
                let index = Int((fraction * Double(candidates.count - 1)).rounded())
                return candidates[index]
            }
        }
        return (eventTimes + selectedUniform).sorted()
    }

    /// Scan more frames than the model ultimately receives so a brief edit is
    /// not lost between eight uniformly spaced screenshots.
    static func candidateSampleTimes(
        steps: [WorkflowStep],
        duration: TimeInterval,
        maximumCount: Int = maximumCandidateFrameCount
    ) -> [TimeInterval] {
        guard maximumCount > 0, duration.isFinite, duration > 0.05 else {
            return sampleTimes(steps: steps, duration: duration, maximumCount: maximumCount)
        }
        let usableEnd = max(0, duration - 0.08)
        let desiredCount = min(
            maximumCount,
            max(maximumFrameCount, Int(ceil(usableEnd / 0.75)) + 1)
        )
        guard desiredCount > 1 else { return [0] }

        var times = (0..<desiredCount).map { index in
            min(usableEnd, Double(index) / Double(desiredCount - 1) * usableEnd)
        }
        times.append(contentsOf: sampleTimes(
            steps: steps,
            duration: duration,
            maximumCount: maximumFrameCount
        ))
        return times.sorted().reduce(into: []) { result, time in
            if result.last.map({ abs($0 - time) >= 0.12 }) ?? true {
                result.append(time)
            }
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

    static func prioritizedRecoveryFrames(_ frames: [WorkflowEvidenceFrame]) -> [WorkflowEvidenceFrame] {
        let settledSelections = frames.filter {
            $0.focusReason?.contains("settled selected spreadsheet cell") == true
        }
        if settledSelections.count >= 2 {
            return Array(settledSelections.suffix(4))
        }
        let cellPattern = #"\b[A-Z]{1,3}[0-9]+\b"#
        let groundedCloseUps = frames.filter { frame in
            guard frame.focusReason != nil else { return false }
            let text = frame.recognizedText.joined(separator: " ")
            let imageExists = FileManager.default.fileExists(atPath: frame.imageURL.path)
            return text.range(of: cellPattern, options: .regularExpression) != nil
                && (!imageExists || WorkflowLearner.selectedSpreadsheetImagePoint(at: frame.imageURL) != nil)
        }
        guard groundedCloseUps.count >= 2 else { return frames }
        return Array(groundedCloseUps.suffix(4))
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
                let cropRect = CGRect(
                    x: originX,
                    y: originYFromTop,
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
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NeloaEvidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        do {
            let asset = AVURLAsset(url: recordingURL)
            let duration = try await asset.load(.duration).seconds
            let times = candidateSampleTimes(steps: steps, duration: duration)
            guard !times.isEmpty else {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                return []
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1_280, height: 1_280)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.12, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.12, preferredTimescale: 600)

            let requestedTimes = times.map { CMTime(seconds: $0, preferredTimescale: 600) }
            var generated: [GeneratedFrame] = []
            for await result in generator.images(for: requestedTimes) {
                guard case .success(requestedTime: let requestedTime, let image, actualTime: let actualTime) = result else {
                    continue
                }
                generated.append(GeneratedFrame(
                    time: actualTime.seconds.isFinite ? actualTime.seconds : requestedTime.seconds,
                    image: image
                ))
            }
            generated.sort { $0.time < $1.time }
            guard !generated.isEmpty else {
                try? FileManager.default.removeItem(at: temporaryDirectory)
                return []
            }

            let changes = rankedVisualChanges(in: generated)
            let overviewIndices = overviewFrameIndices(
                frameCount: generated.count,
                changes: changes,
                maximumCount: maximumFrameCount / 2
            )
            var frames: [WorkflowEvidenceFrame] = []
            for index in overviewIndices {
                let source = generated[index]
                frames.append(try writeEvidenceFrame(
                    image: source.image,
                    time: source.time,
                    captureFrame: captureFrame,
                    focusReason: nil,
                    directory: temporaryDirectory,
                    ordinal: frames.count + 1
                ))
            }

            let focusBudget = maximumFrameCount - frames.count
            if focusBudget > 0 {
                let spreadsheetFrames = try makeSpreadsheetSelectionFrames(
                    from: generated,
                    captureFrame: captureFrame,
                    directory: temporaryDirectory,
                    maximumCount: focusBudget,
                    startingOrdinal: frames.count + 1
                )
                frames.append(contentsOf: spreadsheetFrames)
                let remainingFocusBudget = maximumFrameCount - frames.count
                if remainingFocusBudget > 0 {
                    frames.append(contentsOf: try makeVisualChangeFrames(
                    from: generated,
                    changes: changes,
                    captureFrame: captureFrame,
                    directory: temporaryDirectory,
                    maximumCount: remainingFocusBudget,
                    startingOrdinal: frames.count + 1
                ))
                }
            }
            // Put global context first and close-ups last. Small VLMs heavily
            // weight the final images; timestamps still preserve demonstrated
            // order while the actionable cell/field evidence remains salient.
            return frames
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }
    }

    private static func makeSpreadsheetSelectionFrames(
        from frames: [GeneratedFrame],
        captureFrame: CGRect?,
        directory: URL,
        maximumCount: Int,
        startingOrdinal: Int
    ) throws -> [WorkflowEvidenceFrame] {
        guard maximumCount > 0 else { return [] }
        var settledSelections: [(frame: GeneratedFrame, point: CGPoint)] = []
        var active: (frame: GeneratedFrame, point: CGPoint)?
        for frame in frames {
            guard let point = WorkflowLearner.selectedSpreadsheetImagePoint(in: frame.image) else { continue }
            if let current = active, hypot(current.point.x - point.x, current.point.y - point.y) < 8 {
                // Keep replacing the segment with its latest frame so typed text
                // has time to appear before focus moves to the next cell.
                active = (frame, point)
            } else {
                if let active { settledSelections.append(active) }
                active = (frame, point)
            }
        }
        if let active { settledSelections.append(active) }
        // The first segment is the selection that was already present when
        // recording began. Later settled selections are demonstrated edits.
        let demonstrated = Array(settledSelections.dropFirst().suffix(maximumCount))
        var output: [WorkflowEvidenceFrame] = []
        for selection in demonstrated {
            let source = selection.frame
            let cropWidth = min(CGFloat(source.image.width), 640)
            let cropHeight = min(CGFloat(source.image.height), 374)
            let originX = min(
                max(0, selection.point.x - cropWidth / 2),
                CGFloat(source.image.width) - cropWidth
            )
            let originYFromTop = min(
                max(0, selection.point.y - cropHeight * 0.90),
                CGFloat(source.image.height) - cropHeight
            )
            let crop = CGRect(
                x: originX,
                y: originYFromTop,
                width: cropWidth,
                height: cropHeight
            ).integral
            guard let cropped = source.image.cropping(to: crop) else { continue }
            output.append(try writeEvidenceFrame(
                image: cropped,
                time: source.time,
                captureFrame: mappedCaptureFrame(
                    crop: crop,
                    sourceWidth: source.image.width,
                    sourceHeight: source.image.height,
                    captureFrame: captureFrame
                ),
                focusReason: "settled selected spreadsheet cell after an edit",
                directory: directory,
                ordinal: startingOrdinal + output.count
            ))
        }
        return output
    }

    private static func overviewFrameIndices(
        frameCount: Int,
        changes: [VisualChange],
        maximumCount: Int
    ) -> [Int] {
        guard frameCount > 0, maximumCount > 0 else { return [] }
        var indices: [Int] = [0]
        if frameCount > 1 { indices.append(frameCount - 1) }
        for change in changes {
            for index in [change.previousIndex, change.currentIndex] where !indices.contains(index) {
                indices.append(index)
                if indices.count == maximumCount { return indices.sorted() }
            }
        }
        if indices.count < maximumCount {
            for position in 0..<maximumCount {
                let fraction = Double(position) / Double(max(maximumCount - 1, 1))
                let index = Int((fraction * Double(frameCount - 1)).rounded())
                if !indices.contains(index) { indices.append(index) }
                if indices.count == maximumCount { break }
            }
        }
        return Array(indices.prefix(maximumCount)).sorted()
    }

    private static func rankedVisualChanges(in frames: [GeneratedFrame]) -> [VisualChange] {
        guard frames.count > 1 else { return [] }
        let width = 96
        let height = 54
        let thumbnails = frames.map { luminanceThumbnail(for: $0.image, width: width, height: height) }
        return (1..<frames.count).map { index in
            visualChange(
                previous: thumbnails[index - 1],
                current: thumbnails[index],
                width: width,
                height: height,
                previousIndex: index - 1,
                currentIndex: index
            )
        }.sorted { $0.score > $1.score }
    }

    private static func visualChange(
        previous: [UInt8],
        current: [UInt8],
        width: Int,
        height: Int,
        previousIndex: Int,
        currentIndex: Int
    ) -> VisualChange {
        guard previous.count == current.count, previous.count == width * height else {
            return VisualChange(previousIndex: previousIndex, currentIndex: currentIndex, score: 0, bounds: nil)
        }
        var total = 0
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for offset in previous.indices {
            let delta = abs(Int(previous[offset]) - Int(current[offset]))
            total += delta
            guard delta >= 14 else { continue }
            let x = offset % width
            let y = offset / width
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
        let bounds = maxX >= minX && maxY >= minY
            ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
            : nil
        return VisualChange(
            previousIndex: previousIndex,
            currentIndex: currentIndex,
            score: Double(total) / Double(previous.count),
            bounds: bounds
        )
    }

    private static func luminanceThumbnail(for image: CGImage, width: Int, height: Int) -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [UInt8](repeating: 0, count: width * height) }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var luminance = [UInt8]()
        luminance.reserveCapacity(width * height)
        var offset = 0
        while offset < rgba.count {
            let red = Int(rgba[offset])
            let green = Int(rgba[offset + 1])
            let blue = Int(rgba[offset + 2])
            luminance.append(UInt8((red * 54 + green * 183 + blue * 19) / 256))
            offset += 4
        }
        return luminance
    }

    private static func makeVisualChangeFrames(
        from frames: [GeneratedFrame],
        changes: [VisualChange],
        captureFrame: CGRect?,
        directory: URL,
        maximumCount: Int,
        startingOrdinal: Int
    ) throws -> [WorkflowEvidenceFrame] {
        guard maximumCount > 0 else { return [] }
        var output: [WorkflowEvidenceFrame] = []
        var usedTimes: [TimeInterval] = []
        for change in changes {
            guard let bounds = change.bounds,
                  change.score > 0.08,
                  bounds.width * bounds.height < 96 * 54 * 0.55 else { continue }
            let current = frames[change.currentIndex]
            let previous = frames[change.previousIndex]
            let crop = expandedCropRect(
                thumbnailBounds: bounds,
                imageWidth: current.image.width,
                imageHeight: current.image.height
            )
            guard crop.width > 0, crop.height > 0,
                  !usedTimes.contains(where: { abs($0 - current.time) < 0.35 }) else { continue }

            for source in [previous, current] {
                guard let cropped = source.image.cropping(to: crop) else { continue }
                output.append(try writeEvidenceFrame(
                    image: cropped,
                    time: source.time,
                    captureFrame: mappedCaptureFrame(
                        crop: crop,
                        sourceWidth: source.image.width,
                        sourceHeight: source.image.height,
                        captureFrame: captureFrame
                    ),
                    focusReason: "close-up around a visual change; compare with the adjacent before/after image",
                    directory: directory,
                    ordinal: startingOrdinal + output.count
                ))
                if output.count == maximumCount { return output }
            }
            usedTimes.append(current.time)
        }
        return output
    }

    private static func expandedCropRect(
        thumbnailBounds: CGRect,
        imageWidth: Int,
        imageHeight: Int
    ) -> CGRect {
        let scaleX = CGFloat(imageWidth) / 96
        let scaleY = CGFloat(imageHeight) / 54
        let raw = CGRect(
            x: thumbnailBounds.minX * scaleX,
            y: thumbnailBounds.minY * scaleY,
            width: thumbnailBounds.width * scaleX,
            height: thumbnailBounds.height * scaleY
        )
        let desiredWidth = max(raw.width + 160, min(CGFloat(imageWidth), 640))
        let desiredHeight = max(raw.height + 120, min(CGFloat(imageHeight), 360))
        let x = min(max(0, raw.midX - desiredWidth / 2), CGFloat(imageWidth) - desiredWidth)
        let y = min(max(0, raw.midY - desiredHeight / 2), CGFloat(imageHeight) - desiredHeight)
        return CGRect(x: x, y: y, width: desiredWidth, height: desiredHeight).integral
    }

    static func mappedCaptureFrame(
        crop: CGRect,
        sourceWidth: Int,
        sourceHeight: Int,
        captureFrame: CGRect?
    ) -> CGRect? {
        guard let captureFrame, sourceWidth > 0, sourceHeight > 0 else { return captureFrame }
        let scaleX = captureFrame.width / CGFloat(sourceWidth)
        let scaleY = captureFrame.height / CGFloat(sourceHeight)
        return CGRect(
            x: captureFrame.minX + crop.minX * scaleX,
            y: captureFrame.minY + crop.minY * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        )
    }

    private static func writeEvidenceFrame(
        image: CGImage,
        time: TimeInterval,
        captureFrame: CGRect?,
        focusReason: String?,
        directory: URL,
        ordinal: Int
    ) throws -> WorkflowEvidenceFrame {
        let imageURL = directory.appendingPathComponent("frame-\(ordinal).png")
        try pngData(for: image).write(to: imageURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL.path)
        return WorkflowEvidenceFrame(
            time: time,
            imageURL: imageURL,
            recognizedText: recognizedText(in: image),
            imageWidth: image.width,
            imageHeight: image.height,
            captureFrame: captureFrame,
            focusReason: focusReason
        )
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
