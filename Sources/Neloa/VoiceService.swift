import AVFoundation
import Foundation
import Speech

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var narrationSegments: [NarrationSegment] = []
    @Published private(set) var isListening = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var hasInputTap = false
    private var timelineOffset: TimeInterval = 0
    private var recognitionFinished = false

    func start(timelineOrigin: Date? = nil) async throws -> URL {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        try Task.checkCancellation()
        guard speechStatus == .authorized else { throw VoiceError.speechPermission }

        let micAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        try Task.checkCancellation()
        guard micAllowed else { throw VoiceError.microphonePermission }
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.unavailable }
        guard recognizer.supportsOnDeviceRecognition else { throw VoiceError.onDeviceUnavailable }

        stop()
        transcript = ""
        narrationSegments = []
        errorMessage = nil
        recognitionFinished = false

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Neloa-Captures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = directory.appendingPathComponent("narration-\(UUID().uuidString).caf")

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request
        self.outputURL = url

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result, let self {
                    self.transcript = result.bestTranscription.formattedString
                    self.narrationSegments = result.bestTranscription.segments.map { segment in
                        NarrationSegment(
                            text: segment.substring,
                            time: self.timelineOffset + segment.timestamp,
                            duration: segment.duration,
                            confidence: Double(segment.confidence)
                        )
                    }
                    if result.isFinal { self.recognitionFinished = true }
                }
                if let error {
                    self?.errorMessage = error.localizedDescription
                    self?.recognitionFinished = true
                }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
        }
        hasInputTap = true

        audioEngine.prepare()
        timelineOffset = timelineOrigin.map { max(0, Date().timeIntervalSince($0)) } ?? 0
        try audioEngine.start()
        isListening = true
        return url
    }

    @discardableResult
    func stop() -> URL? {
        stopAudioCapture()
        request?.endAudio()
        task?.cancel()
        clearRecognitionTask()
        return outputURL
    }

    /// Stops microphone capture immediately while leaving the recognizer alive
    /// long enough to publish its final word timings.
    @discardableResult
    func beginFinalization() -> URL? {
        stopAudioCapture()
        request?.endAudio()
        task?.finish()
        if task == nil { recognitionFinished = true }
        return outputURL
    }

    func awaitFinalization() async {
        for _ in 0..<20 where !recognitionFinished {
            try? await Task.sleep(for: .milliseconds(50))
        }
        clearRecognitionTask()
    }

    private func stopAudioCapture() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if hasInputTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            hasInputTap = false
        }
        audioFile = nil
        isListening = false
    }

    private func clearRecognitionTask() {
        request = nil
        task = nil
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        speechSynthesizer.speak(utterance)
    }

    enum VoiceError: LocalizedError {
        case speechPermission
        case microphonePermission
        case unavailable
        case onDeviceUnavailable

        var errorDescription: String? {
            switch self {
            case .speechPermission: "Speech recognition permission is needed for voice instructions."
            case .microphonePermission: "Microphone permission is needed to listen while you teach."
            case .unavailable: "Speech recognition is temporarily unavailable."
            case .onDeviceUnavailable: "On-device speech recognition is unavailable for this language. Neloa did not send your audio to a server."
            }
        }
    }
}
