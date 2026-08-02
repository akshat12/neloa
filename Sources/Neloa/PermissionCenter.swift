import AVFoundation
import ApplicationServices
import CoreGraphics
import Foundation
import Speech

private let accessibilityRequestedKey = "hasRequestedAccessibilityPermission"

@MainActor
final class PermissionCenter: ObservableObject {
    enum Status: Equatable {
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
    @Published private(set) var accessibility: Status = .unknown
    @Published private(set) var screenRestartNeeded = false

    init() { refresh() }

    func refresh() {
        let hasScreenAccess = CGPreflightScreenCaptureAccess()
        screen = hasScreenAccess ? .granted : (screenRestartNeeded ? .denied : .unknown)
        if hasScreenAccess {
            screenRestartNeeded = false
        }
        accessibility = Self.accessibilityStatus(
            isTrusted: AXIsProcessTrusted(),
            hasRequested: Self.hasRequestedAccessibility(in: .standard)
        )
        microphone = status(for: AVCaptureDevice.authorizationStatus(for: .audio))
        speech = status(for: SFSpeechRecognizer.authorizationStatus())
    }

    func requestScreen() {
        let granted = CGRequestScreenCaptureAccess()
        screen = granted ? .granted : .denied
        screenRestartNeeded = !granted
    }

    func requestAccessibility() {
        Self.markAccessibilityRequested(in: .standard)
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

    nonisolated static func accessibilityStatus(isTrusted: Bool, hasRequested: Bool) -> Status {
        if isTrusted { return .granted }
        return hasRequested ? .denied : .unknown
    }

    nonisolated static func hasRequestedAccessibility(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: accessibilityRequestedKey)
    }

    nonisolated static func markAccessibilityRequested(in defaults: UserDefaults) {
        defaults.set(true, forKey: accessibilityRequestedKey)
    }

}
