import AVFoundation
import Foundation
import Speech

@MainActor
final class VoiceService: ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var outputURL: URL?
    private let speechSynthesizer = AVSpeechSynthesizer()

    func start() async throws -> URL {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { throw VoiceError.speechPermission }

        let micAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        guard micAllowed else { throw VoiceError.microphonePermission }
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.unavailable }

        stop()
        transcript = ""
        errorMessage = nil

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Humana-Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("narration-\(UUID().uuidString).caf")

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        self.outputURL = url

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if let error { self?.errorMessage = error.localizedDescription }
            }
        }

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
        return url
    }

    @discardableResult
    func stop() -> URL? {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        audioFile = nil
        isListening = false
        return outputURL
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

        var errorDescription: String? {
            switch self {
            case .speechPermission: "Speech recognition permission is needed for voice instructions."
            case .microphonePermission: "Microphone permission is needed to listen while you teach."
            case .unavailable: "Speech recognition is temporarily unavailable."
            }
        }
    }
}
