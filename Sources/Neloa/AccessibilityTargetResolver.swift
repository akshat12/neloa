import ApplicationServices
import Foundation

/// Replays a named click against the current accessibility tree. Semantic
/// targets survive window movement and modest layout changes; the recorded
/// coordinate remains the fallback when an app does not expose a useful node.
enum AccessibilityTargetResolver {
    static func press(target: String, in applicationPID: pid_t) -> Bool {
        let wanted = normalize(target)
        guard !wanted.isEmpty else { return false }

        let root = AXUIElementCreateApplication(applicationPID)
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var best: (element: AXUIElement, score: Int)?
        var visited = 0

        while !queue.isEmpty, visited < 1_500 {
            let current = queue.removeFirst()
            visited += 1

            if supportsPress(current.element) {
                let labels = searchableLabels(of: current.element).map(normalize)
                let score = labels.map { label -> Int in
                    if label == wanted { return 3 }
                    if label.hasPrefix(wanted) || wanted.hasPrefix(label) { return 2 }
                    if label.contains(wanted) || wanted.contains(label) { return 1 }
                    return 0
                }.max() ?? 0
                if score == 3 {
                    return AXUIElementPerformAction(current.element, kAXPressAction as CFString) == .success
                }
                if score > (best?.score ?? 0) { best = (current.element, score) }
            }

            guard current.depth < 18 else { continue }
            queue.append(contentsOf: children(of: current.element).map { ($0, current.depth + 1) })
        }

        guard let best, best.score > 0 else { return false }
        return AXUIElementPerformAction(best.element, kAXPressAction as CFString) == .success
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else { return [] }
        return children
    }

    private static func searchableLabels(of element: AXUIElement) -> [String] {
        [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXHelpAttribute,
            kAXValueAttribute,
            kAXRoleDescriptionAttribute
        ].compactMap { stringAttribute($0 as CFString, of: element) }
    }

    private static func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let string = value as? String,
              !string.isEmpty else { return nil }
        return string
    }

    private static func supportsPress(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
              let actions = names as? [String] else { return false }
        return actions.contains(kAXPressAction)
    }

    private static func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
