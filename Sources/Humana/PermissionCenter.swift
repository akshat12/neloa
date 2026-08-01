import AVFoundation
import ApplicationServices
import CoreGraphics
import Foundation
import Speech

@MainActor
final class PermissionCenter: ObservableObject {
    enum Status {
        case unknown
        case granted
        case denied

        var label: String {
            switch self {
            case .unknown: "Not requested"
            case .granted: "Ready"
            case .denied: "Needs permission"
            }
        }
    }

    @Published private(set) var screen: Status = .unknown
    @Published private(set) var microphone: Status = .unknown
    @Published private(set) var speech: Status = .unknown
    @Published private(set) var inputMonitoring: Status = .unknown
    @Published private(set) var accessibility: Status = .unknown

    init() { refresh() }

    func refresh() {
        screen = CGPreflightScreenCaptureAccess() ? .granted : .unknown
        inputMonitoring = CGPreflightListenEventAccess() ? .granted : .unknown
        accessibility = AXIsProcessTrusted() ? .granted : .unknown
        microphone = status(for: AVCaptureDevice.authorizationStatus(for: .audio))
        speech = status(for: SFSpeechRecognizer.authorizationStatus())
    }

    func requestScreen() {
        screen = CGRequestScreenCaptureAccess() ? .granted : .denied
    }

    func requestInputMonitoring() {
        inputMonitoring = CGRequestListenEventAccess() ? .granted : .denied
    }

    func requestAccessibility() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [prompt: true] as CFDictionary
        accessibility = AXIsProcessTrustedWithOptions(options) ? .granted : .denied
    }

    func requestMicrophoneAndSpeech() async {
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        microphone = mic ? .granted : .denied
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        speech = status(for: speechStatus)
    }

    private func status(for value: AVAuthorizationStatus) -> Status {
        switch value {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .unknown
        @unknown default: .unknown
        }
    }

    private func status(for value: SFSpeechRecognizerAuthorizationStatus) -> Status {
        switch value {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .unknown
        @unknown default: .unknown
        }
    }
}
