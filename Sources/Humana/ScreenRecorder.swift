import AVFoundation
import Foundation
import ScreenCaptureKit

@MainActor
final class ScreenRecorder: NSObject, ObservableObject, SCRecordingOutputDelegate, SCStreamDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorMessage: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var timer: Timer?
    private var startedAt: Date?
    private var outputURL: URL?

    func start(includeSystemAudio: Bool) async throws -> URL {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw RecordingError.noDisplay
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Humana-Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("teach-\(UUID().uuidString).mp4")

        let excludedApplications = content.applications.filter { PrivacyShield.excludes($0.bundleIdentifier) }
        let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.queueDepth = 6
        configuration.showsCursor = true
        configuration.capturesAudio = includeSystemAudio
        configuration.excludesCurrentProcessAudio = true

        let outputConfiguration = SCRecordingOutputConfiguration()
        outputConfiguration.outputURL = url
        outputConfiguration.videoCodecType = .h264
        outputConfiguration.outputFileType = .mp4

        let output = SCRecordingOutput(configuration: outputConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = output
        self.outputURL = url
        self.startedAt = Date()
        self.isRecording = true
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        return url
    }

    func stop() async -> URL? {
        timer?.invalidate()
        timer = nil
        do {
            try await stream?.stopCapture()
        } catch {
            errorMessage = error.localizedDescription
        }
        stream = nil
        recordingOutput = nil
        isRecording = false
        return outputURL
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in self.errorMessage = error.localizedDescription }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.isRecording = false
        }
    }

    enum RecordingError: LocalizedError {
        case noDisplay

        var errorDescription: String? { "Humana could not find a display to record." }
    }
}
