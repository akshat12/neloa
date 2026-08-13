import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

@MainActor
final class InteractionRecorder: ObservableObject {
    struct WindowCandidate: Equatable {
        let frame: CGRect
        let layer: Int
        let processID: pid_t
    }

    @Published private(set) var events: [CaptureEvent] = []
    @Published private(set) var isRecording = false
    @Published var permissionMissing = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var applicationObserver: NSObjectProtocol?
    private var startedAt = Date()

    func start() {
        events = []
        startedAt = Date()
        permissionMissing = false
        isRecording = true
        beginObservingApplications()
        captureApplicationSwitch(NSWorkspace.shared.frontmostApplication)

        // Permission is requested explicitly from setup/settings. Triggering the
        // macOS authorization alert after screen recording begins contaminates
        // the demonstration and steals focus from the taught app.
        guard AXIsProcessTrusted() else {
            permissionMissing = true
            return
        }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<InteractionRecorder>.fromOpaque(context).takeUnretainedValue()
            let copy = event.copy() ?? event
            Task { @MainActor in recorder.capture(type: type, event: copy) }
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            permissionMissing = true
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() -> [CaptureEvent] {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        self.eventTap = nil
        self.runLoopSource = nil
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver)
        }
        applicationObserver = nil
        isRecording = false
        return events
    }

    private func beginObservingApplications() {
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.captureApplicationSwitch(application) }
        }
    }

    private func captureApplicationSwitch(_ application: NSRunningApplication?) {
        guard isRecording,
              !PrivacyShield.excludes(application?.bundleIdentifier),
              events.last?.bundleIdentifier != application?.bundleIdentifier else { return }
        events.append(CaptureEvent(
            time: Date().timeIntervalSince(startedAt),
            kind: .appSwitch,
            application: application?.localizedName,
            bundleIdentifier: application?.bundleIdentifier
        ))
    }

    private func capture(type: CGEventType, event: CGEvent) {
        guard isRecording else { return }
        let active = NSWorkspace.shared.frontmostApplication

        let elapsed = Date().timeIntervalSince(startedAt)

        switch type {
        case .leftMouseDown, .rightMouseDown:
            let location = event.location
            let clicked = clickContext(at: location)
            let clickedApplication = clicked.application ?? active
            guard !PrivacyShield.excludes(clickedApplication?.bundleIdentifier) else { return }
            events.append(CaptureEvent(
                time: elapsed,
                kind: type == .rightMouseDown ? .rightClick : .click,
                x: location.x,
                y: location.y,
                target: clicked.target,
                application: clickedApplication?.localizedName,
                bundleIdentifier: clickedApplication?.bundleIdentifier,
                displayID: Self.displayID(at: location)
            ))
        case .keyDown:
            guard !PrivacyShield.excludes(active?.bundleIdentifier) else { return }
            guard !IsSecureEventInputEnabled() else { return }
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let text = unicodeText(from: event)
            let isPrintable = isSafePrintableText(text)
                && !event.flags.contains(.maskCommand)
                && keyCode != 36 && keyCode != 48 && keyCode != 51 && keyCode != 53
            events.append(CaptureEvent(
                time: elapsed,
                kind: isPrintable ? .text : .keyPress,
                text: isPrintable ? text : nil,
                keyCode: isPrintable ? nil : keyCode,
                flags: event.flags.rawValue,
                application: active?.localizedName,
                bundleIdentifier: active?.bundleIdentifier
            ))
        default:
            break
        }
    }

    private func clickContext(at point: CGPoint) -> (application: NSRunningApplication?, target: String?) {
        let systemWideElement = AXUIElementCreateSystemWide()
        var clickedElement: AXUIElement?
        if AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &clickedElement
        ) == .success,
           let clickedElement {
            var processID: pid_t = 0
            if AXUIElementGetPid(clickedElement, &processID) == .success,
               let application = NSRunningApplication(processIdentifier: processID) {
                return (application, Self.semanticClickTarget(from: clickedElement))
            }
        }

        // Accessibility is the most precise source because it resolves the UI
        // element at the click point. Keep the window stack as a safe fallback
        // for apps that expose an incomplete accessibility hierarchy.
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return (nil, nil) }

        let candidates = windowInfo.compactMap { window -> WindowCandidate? in
            guard let layer = (window[kCGWindowLayer] as? NSNumber)?.intValue,
                  let processID = (window[kCGWindowOwnerPID] as? NSNumber)?.int32Value,
                  let bounds = window[kCGWindowBounds] as? [String: Any],
                  let x = (bounds["X"] as? NSNumber)?.doubleValue,
                  let y = (bounds["Y"] as? NSNumber)?.doubleValue,
                  let width = (bounds["Width"] as? NSNumber)?.doubleValue,
                  let height = (bounds["Height"] as? NSNumber)?.doubleValue else { return nil }
            return WindowCandidate(
                frame: CGRect(x: x, y: y, width: width, height: height),
                layer: layer,
                processID: processID
            )
        }
        guard let processID = Self.topmostOwner(at: point, among: candidates) else { return (nil, nil) }
        return (NSRunningApplication(processIdentifier: processID), nil)
    }

    private nonisolated static func semanticClickTarget(from source: AXUIElement) -> String? {
        var element: AXUIElement? = source
        for _ in 0..<5 {
            guard let current = element else { break }
            if stringAttribute(kAXRoleAttribute as CFString, from: current) == "AXSecureTextField" {
                return nil
            }
            if supportsPress(current) {
                for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute] {
                    if let label = usefulTargetLabel(stringAttribute(attribute as CFString, from: current)) {
                        return label
                    }
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parent) == .success,
                  let next = parent else { break }
            element = unsafeBitCast(next, to: AXUIElement.self)
        }
        return nil
    }

    private nonisolated static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    private nonisolated static func supportsPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else { return false }
        return actions.contains(kAXPressAction)
    }

    private nonisolated static func usefulTargetLabel(_ rawValue: String?) -> String? {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 120 else { return nil }
        let generic = ["button", "group", "web area", "scroll area", "unknown"]
        return generic.contains(value.lowercased()) ? nil : value
    }

    nonisolated static func topmostOwner(at point: CGPoint, among candidates: [WindowCandidate]) -> pid_t? {
        candidates.first(where: {
            $0.layer == 0 && $0.frame.width > 1 && $0.frame.height > 1 && $0.frame.contains(point)
        })?.processID
    }

    nonisolated static func displayID(at point: CGPoint) -> CGDirectDisplayID? {
        var displayID = CGDirectDisplayID()
        var count: UInt32 = 0
        guard CGGetDisplaysWithPoint(point, 1, &displayID, &count) == .success, count > 0 else { return nil }
        return displayID
    }

    private func unicodeText(from event: CGEvent) -> String {
        var count = 0
        var characters = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: characters.count, actualStringLength: &count, unicodeString: &characters)
        guard count > 0 else { return "" }
        return String(utf16CodeUnits: characters, count: count)
    }

    private func isSafePrintableText(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0)
        }
    }
}
