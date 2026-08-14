import Foundation

enum NarrationTimeline {
    static func utterances(from segments: [NarrationSegment]) -> [NarrationSegment] {
        let ordered = segments
            .map(cleaned)
            .filter { !$0.text.isEmpty }
            .sorted { lhs, rhs in
                if lhs.time == rhs.time { return lhs.endTime < rhs.endTime }
                return lhs.time < rhs.time
            }
        guard var current = ordered.first else { return [] }

        var result: [NarrationSegment] = []
        for segment in ordered.dropFirst() {
            let gap = segment.time - current.endTime
            let sentenceEnded = current.text.last.map { ".!?".contains($0) } ?? false
            let utteranceIsLong = current.endTime - current.time >= 8
            if gap > 1.15 || sentenceEnded || utteranceIsLong {
                result.append(current)
                current = segment
                continue
            }

            current.text = joined(current.text, segment.text)
            current.duration = max(current.endTime, segment.endTime) - current.time
            current.confidence = combinedConfidence(current.confidence, segment.confidence)
        }
        result.append(current)
        return result
    }

    static func promptLines(for workflow: Workflow) -> String {
        let utterances = utterances(from: workflow.narrationSegments ?? [])
        guard !utterances.isEmpty else {
            return workflow.transcript.isEmpty ? "No narration was captured." : workflow.transcript
        }
        return utterances.map {
            "[\(clock($0.time))–\(clock($0.endTime))] \($0.text)"
        }.joined(separator: "\n")
    }

    static func context(around time: TimeInterval, in workflow: Workflow, radius: TimeInterval = 3.5) -> String? {
        let utterances = utterances(from: workflow.narrationSegments ?? [])
        guard !utterances.isEmpty else { return workflow.transcript.isEmpty ? nil : workflow.transcript }
        let nearby = utterances.filter { $0.endTime >= time - radius && $0.time <= time + radius }
        if !nearby.isEmpty { return nearby.map(\.text).joined(separator: " ") }
        return utterances.min(by: {
            distance(from: time, to: $0) < distance(from: time, to: $1)
        })?.text
    }

    private static func cleaned(_ segment: NarrationSegment) -> NarrationSegment {
        var value = segment
        value.text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
        value.time = max(0, segment.time)
        value.duration = max(0, segment.duration)
        return value
    }

    private static func joined(_ lhs: String, _ rhs: String) -> String {
        guard let first = rhs.first else { return lhs }
        let punctuation = CharacterSet.punctuationCharacters.contains(first.unicodeScalars.first!)
        return punctuation ? lhs + rhs : lhs + " " + rhs
    }

    private static func combinedConfidence(_ lhs: Double?, _ rhs: Double?) -> Double? {
        switch (lhs, rhs) {
        case let (.some(left), .some(right)): (left + right) / 2
        case let (.some(value), .none), let (.none, .some(value)): value
        case (.none, .none): nil
        }
    }

    private static func distance(from time: TimeInterval, to segment: NarrationSegment) -> TimeInterval {
        if time < segment.time { return segment.time - time }
        if time > segment.endTime { return time - segment.endTime }
        return 0
    }

    private static func clock(_ time: TimeInterval) -> String {
        let safe = max(0, time)
        return String(format: "%02d:%05.2f", Int(safe) / 60, safe.truncatingRemainder(dividingBy: 60))
    }
}
