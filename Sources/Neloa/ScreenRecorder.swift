import AVFoundation
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit

enum ScreenCaptureTarget: Hashable {
    case followActiveApplication
    case display(CGDirectDisplayID)
}

struct RecordingDisplayOption: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let pixelWidth: Int
    let pixelHeight: Int

    var label: String {
        "\(name) · \(pixelWidth) × \(pixelHeight)"
    }

    @MainActor
    static var connected: [RecordingDisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            return RecordingDisplayOption(
                id: displayID,
                name: screen.localizedName,
                pixelWidth: CGDisplayPixelsWide(displayID),
                pixelHeight: CGDisplayPixelsHigh(displayID)
            )
        }
    }
}

@MainActor
final class ScreenRecorder: NSObject, ObservableObject, SCRecordingOutputDelegate, SCStreamDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var activeDisplayName = ""
    @Published var errorMessage: String?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var timer: Timer?
    private var startedAt: Date?
    private var outputURL: URL?
    private var recordingDidFinish = false
    private var applicationObserver: NSObjectProtocol?
    private var activeDisplayID: CGDirectDisplayID?
    private var capturesSystemAudio = false
    private(set) var captureFrame: CGRect?

    func start(
        includeSystemAudio: Bool,
        preferredBundleIdentifier: String? = nil,
        captureTarget: ScreenCaptureTarget = .followActiveApplication
    ) async throws -> URL {
        let preflightGranted = CGPreflightScreenCaptureAccess()
        let requestGranted = preflightGranted ? false : CGRequestScreenCaptureAccess()
        guard Self.hasScreenCaptureAccess(preflightGranted: preflightGranted, requestGranted: requestGranted) else {
            throw RecordingError.screenPermissionRequired
        }

        do {
            return try await startAuthorizedCapture(
                includeSystemAudio: includeSystemAudio,
                preferredBundleIdentifier: preferredBundleIdentifier,
                captureTarget: captureTarget
            )
        } catch {
            if Self.isScreenPermissionError(error) || !CGPreflightScreenCaptureAccess() {
                throw RecordingError.screenPermissionRequired
            }
            throw error
        }
    }

    private func startAuthorizedCapture(
        includeSystemAudio: Bool,
        preferredBundleIdentifier: String?,
        captureTarget: ScreenCaptureTarget
    ) async throws -> URL {

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display: SCDisplay
        switch captureTarget {
        case .followActiveApplication:
            guard let resolved = preferredDisplay(in: content, bundleIdentifier: preferredBundleIdentifier)
                ?? content.displays.first else {
                throw RecordingError.noDisplay
            }
            display = resolved
        case .display(let displayID):
            guard let resolved = content.displays.first(where: { $0.displayID == displayID }) else {
                throw RecordingError.selectedDisplayUnavailable
            }
            display = resolved
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Neloa-Captures", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
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
        captureFrame = display.frame

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
        self.recordingDidFinish = false
        self.activeDisplayID = display.displayID
        self.activeDisplayName = Self.displayName(for: display.displayID)
        self.capturesSystemAudio = includeSystemAudio
        self.startedAt = Date()
        self.isRecording = true
        if captureTarget == .followActiveApplication {
            beginFollowingActiveApplication()
        }
        self.timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
        return url
    }

    nonisolated static func hasScreenCaptureAccess(preflightGranted: Bool, requestGranted: Bool) -> Bool {
        preflightGranted || requestGranted
    }

    nonisolated static func isScreenPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.Code.userDeclined.rawValue
    }

    func stop() async -> URL? {
        stopFollowingActiveApplication()
        timer?.invalidate()
        timer = nil
        do {
            try await stream?.stopCapture()
        } catch {
            errorMessage = error.localizedDescription
        }
        // stopCapture can return before SCRecordingOutput finalizes the MP4.
        // Visual learning opens it immediately, so give the delegate a short,
        // bounded window to make the asset readable first.
        for _ in 0..<50 where !recordingDidFinish {
            try? await Task.sleep(for: .milliseconds(40))
        }
        stream = nil
        recordingOutput = nil
        isRecording = false
        return outputURL
    }

    /// A teaching session often starts with Neloa on one display and the app
    /// being taught on another. Follow the activated app so the movie contains
    /// the screen where the user is actually demonstrating the task.
    private func beginFollowingActiveApplication() {
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  !PrivacyShield.excludes(application.bundleIdentifier) else { return }
            Task { @MainActor [weak self] in
                await self?.follow(application)
            }
        }
    }

    private func stopFollowingActiveApplication() {
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver)
        }
        applicationObserver = nil
    }

    private func follow(_ application: NSRunningApplication) async {
        guard let stream else { return }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let appWindows = content.windows.filter {
                $0.owningApplication?.processID == application.processIdentifier && $0.isOnScreen
            }
            let frontmostID = Self.frontmostWindowID(processID: application.processIdentifier)
            let targetWindow = frontmostID.flatMap { id in appWindows.first(where: { $0.windowID == id }) }
                ?? appWindows.max(by: { windowArea($0.frame) < windowArea($1.frame) })
            guard let targetWindow,
                  let display = Self.bestDisplay(for: targetWindow.frame, among: content.displays),
                  display.displayID != activeDisplayID else { return }

            let excludedApplications = content.applications.filter { PrivacyShield.excludes($0.bundleIdentifier) }
            let filter = SCContentFilter(display: display, excludingApplications: excludedApplications, exceptingWindows: [])
            try await stream.updateContentFilter(filter)

            activeDisplayID = display.displayID
            activeDisplayName = Self.displayName(for: display.displayID)
            captureFrame = display.frame
        } catch {
            // Keep recording the previous display if a transient workspace
            // change cannot be resolved. The session remains usable.
            errorMessage = "Neloa could not follow the active window: \(error.localizedDescription)"
        }
    }

    nonisolated static func bestDisplayIndex(for windowFrame: CGRect, displayFrames: [CGRect]) -> Int? {
        displayFrames.indices.max {
            intersectionArea(windowFrame, displayFrames[$0]) < intersectionArea(windowFrame, displayFrames[$1])
        }.flatMap { intersectionArea(windowFrame, displayFrames[$0]) > 0 ? $0 : nil }
    }

    nonisolated private static func frontmostWindowID(processID: pid_t) -> CGWindowID? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }
        for window in windows {
            guard (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value == processID,
                  (window[kCGWindowLayer] as? NSNumber)?.intValue == 0,
                  let number = window[kCGWindowNumber] as? NSNumber else { continue }
            return CGWindowID(number.uint32Value)
        }
        return nil
    }

    private static func bestDisplay(for windowFrame: CGRect, among displays: [SCDisplay]) -> SCDisplay? {
        guard let index = bestDisplayIndex(for: windowFrame, displayFrames: displays.map(\.frame)) else { return nil }
        return displays[index]
    }

    private static func displayName(for displayID: CGDirectDisplayID) -> String {
        RecordingDisplayOption.connected.first(where: { $0.id == displayID })?.name ?? "Selected display"
    }

    private func preferredDisplay(
        in content: SCShareableContent,
        bundleIdentifier: String?
    ) -> SCDisplay? {
        guard let bundleIdentifier,
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
            return nil
        }
        let windows = content.windows.filter {
            $0.owningApplication?.processID == application.processIdentifier && $0.isOnScreen
        }
        let frontmostID = Self.frontmostWindowID(processID: application.processIdentifier)
        let target = frontmostID.flatMap { id in windows.first(where: { $0.windowID == id }) }
            ?? windows.max(by: { windowArea($0.frame) < windowArea($1.frame) })
        return target.flatMap { Self.bestDisplay(for: $0.frame, among: content.displays) }
    }

    nonisolated private static func intersectionArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    nonisolated private func windowArea(_ frame: CGRect) -> CGFloat {
        frame.width * frame.height
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: any Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.recordingDidFinish = true
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.recordingDidFinish = true }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.isRecording = false
        }
    }

    enum RecordingError: LocalizedError, Equatable {
        case screenPermissionRequired
        case noDisplay
        case selectedDisplayUnavailable

        var errorDescription: String? {
            switch self {
            case .screenPermissionRequired:
                "Neloa needs Screen Recording permission to see this workflow."
            case .noDisplay:
                "Neloa could not find a display to record."
            case .selectedDisplayUnavailable:
                "The selected display is no longer connected. Choose another screen and try again."
            }
        }
    }
}
