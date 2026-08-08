import Foundation

enum QwenResponseSupport {
    static func jsonData(from content: String, topLevelKeys: [String]) -> Data? {
        let stripped = content
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = validObjectData(in: stripped, containingAny: topLevelKeys) {
            return data
        }

        guard let start = stripped.firstIndex(of: "{") else { return nil }
        var repaired = String(stripped[start...])

        for key in topLevelKeys {
            repaired = repaired.replacingOccurrences(of: "\"\(key):", with: "\"\(key)\":")
            repaired = replacing(
                pattern: "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*:",
                in: repaired,
                with: "\"\(key)\":"
            )
        }

        for key in topLevelKeys.dropFirst() {
            repaired = replacing(
                pattern: "(?m)\\s*^\\s*(\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:)",
                in: repaired,
                with: ",$1"
            )
        }

        repaired = closingUnbalancedContainers(in: repaired)
        return validObjectData(in: repaired, containingAny: topLevelKeys)
    }

    private static func replacing(pattern: String, in value: String, with replacement: String) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(value.startIndex..., in: value),
            withTemplate: replacement
        )
    }

    private static func validObjectData(in value: String, containingAny keys: [String]) -> Data? {
        let starts = value.indices.filter { value[$0] == "{" }.prefix(64)
        let ends = value.indices.filter { value[$0] == "}" }.suffix(64).reversed()
        for start in starts {
            for end in ends where start <= end {
                let candidate = String(value[start...end])
                guard let data = candidate.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let dictionary = object as? [String: Any],
                      keys.contains(where: { dictionary[$0] != nil }) else { continue }
                return data
            }
        }
        return nil
    }

    private static func closingUnbalancedContainers(in value: String) -> String {
        var stack: [Character] = []
        var inString = false
        var escaped = false
        for character in value {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character == "\"" {
                inString = true
            } else if character == "{" || character == "[" {
                stack.append(character)
            } else if character == "}" || character == "]" {
                let expected: Character = character == "}" ? "{" : "["
                if stack.last == expected { stack.removeLast() }
            }
        }
        return stack.reversed().reduce(value) { partial, opening in
            partial + (opening == "{" ? "}" : "]")
        }
    }
}
