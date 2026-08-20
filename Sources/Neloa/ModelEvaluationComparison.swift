import Foundation

enum ModelEvaluationComparisonStatus: String, Codable, Sendable {
    case unchanged
    case improved
    case regressed
}

struct ModelEvaluationRunSummary: Codable, Equatable, Sendable {
    var gitCommit: String?
    var modelID: String
    var modelRevision: String
    var precision: String
    var score: Double
    var passed: Bool
    var durationSeconds: Double
    var caseCount: Int

    nonisolated init(report: ModelEvaluationReport) {
        gitCommit = report.gitCommit
        modelID = report.modelID
        modelRevision = report.modelRevision
        precision = report.precision
        score = report.score
        passed = report.passed
        durationSeconds = report.durationSeconds
        caseCount = report.cases.count
    }
}

struct ModelEvaluationCaseComparison: Codable, Equatable, Sendable {
    var id: String
    var category: String
    var baselineScore: Double
    var candidateScore: Double
    var scoreDelta: Double
    var baselineDurationSeconds: Double
    var candidateDurationSeconds: Double
    var durationDeltaSeconds: Double
    var baselinePassed: Bool
    var candidatePassed: Bool
    var status: ModelEvaluationComparisonStatus
    var regressedAssertions: [String]
    var improvedAssertions: [String]
}

enum ModelEvaluationRegressionKind: String, Codable, Sendable {
    case incompatibleReports
    case candidateFailed
    case overallScoreDropped
    case caseRegressed
    case assertionRegressed
}

struct ModelEvaluationRegression: Codable, Equatable, Sendable {
    var kind: ModelEvaluationRegressionKind
    var caseID: String?
    var assertionName: String?
    var detail: String
}

struct ModelEvaluationComparisonReport: Codable, Equatable, Sendable {
    static let formatVersion = 1

    var schemaVersion = Self.formatVersion
    var generatedAt: Date
    var compatible: Bool
    var baseline: ModelEvaluationRunSummary
    var candidate: ModelEvaluationRunSummary
    var scoreDelta: Double
    var durationDeltaSeconds: Double
    var cases: [ModelEvaluationCaseComparison]
    var regressions: [ModelEvaluationRegression]
    var passed: Bool
}

enum ModelEvaluationComparison {
    struct WrittenReport: Sendable {
        var report: ModelEvaluationComparisonReport
        var jsonURL: URL
        var markdownURL: URL
    }

    nonisolated static func compare(
        baseline: ModelEvaluationReport,
        candidate: ModelEvaluationReport,
        generatedAt: Date = Date()
    ) -> ModelEvaluationComparisonReport {
        let normalizedGeneratedAt = Date(
            timeIntervalSince1970: floor(generatedAt.timeIntervalSince1970)
        )
        let compatibilityIssues = compatibilityIssues(baseline: baseline, candidate: candidate)
        let compatible = compatibilityIssues.isEmpty
        let baselineByID = Dictionary(grouping: baseline.cases, by: \.id).compactMapValues(\.first)
        let candidateByID = Dictionary(grouping: candidate.cases, by: \.id).compactMapValues(\.first)
        let sharedIDs = Set(baselineByID.keys).intersection(candidateByID.keys).sorted()

        var regressions = compatibilityIssues.map {
            ModelEvaluationRegression(
                kind: .incompatibleReports,
                caseID: nil,
                assertionName: nil,
                detail: $0
            )
        }
        if !candidate.passed {
            regressions.append(ModelEvaluationRegression(
                kind: .candidateFailed,
                caseID: nil,
                assertionName: nil,
                detail: "The candidate report does not meet its own quality gate."
            ))
        }
        let scoreDelta = candidate.score - baseline.score
        if scoreDelta < -0.000_001 {
            regressions.append(ModelEvaluationRegression(
                kind: .overallScoreDropped,
                caseID: nil,
                assertionName: nil,
                detail: "Overall score dropped from \(percent(baseline.score)) to \(percent(candidate.score))."
            ))
        }

        let caseComparisons = sharedIDs.compactMap { id -> ModelEvaluationCaseComparison? in
            guard let previous = baselineByID[id], let current = candidateByID[id] else { return nil }
            let previousAssertions = Dictionary(grouping: previous.assertions, by: \.name).compactMapValues(\.first)
            let currentAssertions = Dictionary(grouping: current.assertions, by: \.name).compactMapValues(\.first)
            let sharedAssertions = Set(previousAssertions.keys).intersection(currentAssertions.keys).sorted()
            let regressed = sharedAssertions.filter {
                previousAssertions[$0]?.passed == true && currentAssertions[$0]?.passed == false
            }
            let improved = sharedAssertions.filter {
                previousAssertions[$0]?.passed == false && currentAssertions[$0]?.passed == true
            }

            if previous.passed && !current.passed {
                regressions.append(ModelEvaluationRegression(
                    kind: .caseRegressed,
                    caseID: id,
                    assertionName: nil,
                    detail: "Case \(id) changed from passing to failing."
                ))
            }
            for assertion in regressed {
                regressions.append(ModelEvaluationRegression(
                    kind: .assertionRegressed,
                    caseID: id,
                    assertionName: assertion,
                    detail: "A previously passing assertion now fails."
                ))
            }

            let delta = current.score - previous.score
            let status: ModelEvaluationComparisonStatus
            if delta < -0.000_001 || (previous.passed && !current.passed) || !regressed.isEmpty {
                status = .regressed
            } else if delta > 0.000_001 || (!previous.passed && current.passed) || !improved.isEmpty {
                status = .improved
            } else {
                status = .unchanged
            }
            return ModelEvaluationCaseComparison(
                id: id,
                category: current.category,
                baselineScore: previous.score,
                candidateScore: current.score,
                scoreDelta: delta,
                baselineDurationSeconds: previous.durationSeconds,
                candidateDurationSeconds: current.durationSeconds,
                durationDeltaSeconds: current.durationSeconds - previous.durationSeconds,
                baselinePassed: previous.passed,
                candidatePassed: current.passed,
                status: status,
                regressedAssertions: regressed,
                improvedAssertions: improved
            )
        }

        return ModelEvaluationComparisonReport(
            generatedAt: normalizedGeneratedAt,
            compatible: compatible,
            baseline: ModelEvaluationRunSummary(report: baseline),
            candidate: ModelEvaluationRunSummary(report: candidate),
            scoreDelta: scoreDelta,
            durationDeltaSeconds: candidate.durationSeconds - baseline.durationSeconds,
            cases: caseComparisons,
            regressions: regressions,
            passed: compatible && candidate.passed && regressions.isEmpty
        )
    }

    nonisolated static func run(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> WrittenReport {
        let baselineURL = try requiredURL(named: "NELOA_MODEL_EVAL_BASELINE", environment: environment)
        let candidateURL = try requiredURL(named: "NELOA_MODEL_EVAL_CANDIDATE", environment: environment)
        let outputURL = environment["NELOA_MODEL_EVAL_COMPARISON_REPORT"]
            .flatMap(clean)
            .map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".build/model-eval/reports/comparison.json")
        let decoder = JSONDecoder.neloa
        let baseline = try decoder.decode(ModelEvaluationReport.self, from: Data(contentsOf: baselineURL))
        let candidate = try decoder.decode(ModelEvaluationReport.self, from: Data(contentsOf: candidateURL))
        let report = compare(baseline: baseline, candidate: candidate)
        let markdownURL = outputURL.deletingPathExtension().appendingPathExtension("md")
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try JSONEncoder.neloa.encode(report).write(to: outputURL, options: .atomic)
        try markdown(report).write(to: markdownURL, atomically: true, encoding: .utf8)
        return WrittenReport(report: report, jsonURL: outputURL, markdownURL: markdownURL)
    }

    nonisolated static func markdown(_ report: ModelEvaluationComparisonReport) -> String {
        var lines = [
            "# Neloa model evaluation comparison",
            "",
            "- Result: **\(report.passed ? "PASS" : "FAIL")**",
            "- Comparable: **\(report.compatible ? "Yes" : "No")**",
            "- Score: \(percent(report.baseline.score)) → \(percent(report.candidate.score)) (\(signedPercent(report.scoreDelta)))",
            "- Runtime: \(seconds(report.baseline.durationSeconds)) → \(seconds(report.candidate.durationSeconds)) (\(signedSeconds(report.durationDeltaSeconds)))",
            "- Baseline: \(runLabel(report.baseline))",
            "- Candidate: \(runLabel(report.candidate))",
            "",
            "| Case | Category | Baseline | Candidate | Change | Runtime change | Result |",
            "| --- | --- | ---: | ---: | ---: | ---: | --- |"
        ]
        for item in report.cases {
            lines.append(
                "| `\(escape(item.id))` | \(escape(item.category)) | \(percent(item.baselineScore)) | \(percent(item.candidateScore)) | \(signedPercent(item.scoreDelta)) | \(signedSeconds(item.durationDeltaSeconds)) | \(item.status.rawValue.capitalized) |"
            )
        }
        if !report.regressions.isEmpty {
            lines.append(contentsOf: ["", "## Regressions", ""])
            for regression in report.regressions {
                let scope = [regression.caseID, regression.assertionName]
                    .compactMap { $0 }
                    .map { "`\($0)`" }
                    .joined(separator: " / ")
                lines.append("- **\(regressionLabel(regression.kind))**\(scope.isEmpty ? "" : " — \(scope)"): \(regression.detail)")
            }
        }
        let improvements = report.cases.flatMap { item in
            item.improvedAssertions.map { (item.id, $0) }
        }
        if !improvements.isEmpty {
            lines.append(contentsOf: ["", "## Improvements", ""])
            for (caseID, assertion) in improvements {
                lines.append("- `\(caseID)` / `\(assertion)` now passes.")
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }

    nonisolated static func consoleSummary(_ written: WrittenReport) -> String {
        let report = written.report
        return [
            "Neloa model comparison \(report.passed ? "PASSED" : "FAILED") — \(percent(report.baseline.score)) → \(percent(report.candidate.score))",
            "Comparable: \(report.compatible ? "yes" : "no")",
            "Regressions: \(report.regressions.count)",
            "JSON report: \(written.jsonURL.path)",
            "Markdown report: \(written.markdownURL.path)"
        ].joined(separator: "\n")
    }

    private struct AssertionDefinition: Equatable {
        var critical: Bool
        var weight: Double
        var expected: String
    }

    private nonisolated static func compatibilityIssues(
        baseline: ModelEvaluationReport,
        candidate: ModelEvaluationReport
    ) -> [String] {
        var issues: [String] = []
        if baseline.schemaVersion != ModelEvaluationReport.formatVersion ||
            candidate.schemaVersion != ModelEvaluationReport.formatVersion {
            issues.append("A report uses an unsupported schema. Rerun both evaluations with this Neloa checkout.")
        } else if baseline.schemaVersion != candidate.schemaVersion {
            issues.append("Report schema changed. Rerun both evaluations with the same Neloa checkout.")
        }
        if !nearlyEqual(baseline.minimumScore, candidate.minimumScore) {
            issues.append("The overall minimum score changed. Rerun both evaluations with the same quality gate.")
        }
        issues.append(contentsOf: integrityIssues(report: baseline, label: "baseline"))
        issues.append(contentsOf: integrityIssues(report: candidate, label: "candidate"))
        let baselineByID = uniqueCases(baseline.cases, label: "baseline", issues: &issues)
        let candidateByID = uniqueCases(candidate.cases, label: "candidate", issues: &issues)
        let baselineIDs = Set(baselineByID.keys)
        let candidateIDs = Set(candidateByID.keys)
        if baselineIDs != candidateIDs {
            let missing = baselineIDs.subtracting(candidateIDs).sorted()
            let added = candidateIDs.subtracting(baselineIDs).sorted()
            issues.append("Case set changed\(listChange(missing: missing, added: added)). Rerun both evaluations with the same case selection and checkout.")
        }
        for id in baselineIDs.intersection(candidateIDs).sorted() {
            guard let previous = baselineByID[id], let current = candidateByID[id] else { continue }
            if previous.category != current.category {
                issues.append("Case \(id) changed category from \(previous.category) to \(current.category).")
            }
            var assertionIssues: [String] = []
            let previousDefinitions = assertionDefinitions(previous.assertions, caseID: id, label: "baseline", issues: &assertionIssues)
            let currentDefinitions = assertionDefinitions(current.assertions, caseID: id, label: "candidate", issues: &assertionIssues)
            issues.append(contentsOf: assertionIssues)
            if previousDefinitions != currentDefinitions {
                issues.append("Case \(id) changed its assertion names, weights, critical gates, or expected values.")
            }
        }
        return Array(Set(issues)).sorted()
    }

    private nonisolated static func integrityIssues(
        report: ModelEvaluationReport,
        label: String
    ) -> [String] {
        var issues: [String] = []
        for testCase in report.cases {
            let computed = ModelEvaluationCase(
                id: testCase.id,
                category: testCase.category,
                durationSeconds: testCase.durationSeconds,
                assertions: testCase.assertions
            )
            if !nearlyEqual(testCase.earnedScore, computed.earnedScore) ||
                !nearlyEqual(testCase.maximumScore, computed.maximumScore) ||
                !nearlyEqual(testCase.score, computed.score) ||
                testCase.passed != computed.passed {
                issues.append("The \(label) report has inconsistent computed results for case \(testCase.id).")
            }
        }
        let earned = report.cases.reduce(0) { $0 + $1.earnedScore }
        let maximum = report.cases.reduce(0) { $0 + $1.maximumScore }
        let score = maximum > 0 ? earned / maximum : 0
        let passed = score >= report.minimumScore && report.cases.allSatisfy(\.passed)
        if !nearlyEqual(report.earnedScore, earned) ||
            !nearlyEqual(report.maximumScore, maximum) ||
            !nearlyEqual(report.score, score) ||
            report.passed != passed {
            issues.append("The \(label) report has inconsistent aggregate results.")
        }
        return issues
    }

    private nonisolated static func uniqueCases(
        _ cases: [ModelEvaluationCase],
        label: String,
        issues: inout [String]
    ) -> [String: ModelEvaluationCase] {
        let grouped = Dictionary(grouping: cases, by: \.id)
        let duplicates = grouped.filter { $0.value.count > 1 }.keys.sorted()
        if !duplicates.isEmpty {
            issues.append("The \(label) report repeats case IDs: \(duplicates.joined(separator: ", ")).")
        }
        return grouped.compactMapValues(\.first)
    }

    private nonisolated static func assertionDefinitions(
        _ assertions: [ModelEvaluationAssertion],
        caseID: String,
        label: String,
        issues: inout [String]
    ) -> [String: AssertionDefinition] {
        let grouped = Dictionary(grouping: assertions, by: \.name)
        let duplicates = grouped.filter { $0.value.count > 1 }.keys.sorted()
        if !duplicates.isEmpty {
            issues.append("The \(label) report repeats assertions in \(caseID): \(duplicates.joined(separator: ", ")).")
        }
        return grouped.compactMapValues { values in
            values.first.map {
                AssertionDefinition(critical: $0.critical, weight: $0.weight, expected: $0.expected)
            }
        }
    }

    private nonisolated static func requiredURL(
        named name: String,
        environment: [String: String]
    ) throws -> URL {
        guard let path = environment[name].flatMap(clean) else {
            throw SelfTests.Failure(description: "\(name) is required")
        }
        return URL(fileURLWithPath: path)
    }

    private nonisolated static func clean(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private nonisolated static func listChange(missing: [String], added: [String]) -> String {
        var parts: [String] = []
        if !missing.isEmpty { parts.append("missing: \(missing.joined(separator: ", "))") }
        if !added.isEmpty { parts.append("added: \(added.joined(separator: ", "))") }
        return parts.isEmpty ? "" : " (\(parts.joined(separator: "; ")))"
    }

    private nonisolated static func nearlyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 0.000_001
    }

    private nonisolated static func runLabel(_ report: ModelEvaluationRunSummary) -> String {
        let commit = report.gitCommit.map { " at `\(escape($0))`" } ?? ""
        let revision = String(report.modelRevision.prefix(12))
        return "`\(escape(report.modelID))` · \(escape(report.precision)) · revision `\(escape(revision))`\(commit)"
    }

    private nonisolated static func regressionLabel(_ kind: ModelEvaluationRegressionKind) -> String {
        switch kind {
        case .incompatibleReports: "Incompatible reports"
        case .candidateFailed: "Candidate failed"
        case .overallScoreDropped: "Overall score dropped"
        case .caseRegressed: "Case regressed"
        case .assertionRegressed: "Assertion regressed"
        }
    }

    private nonisolated static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private nonisolated static func signedPercent(_ value: Double) -> String {
        String(format: "%+.1f pp", value * 100)
    }

    private nonisolated static func seconds(_ value: Double) -> String {
        String(format: "%.1fs", value)
    }

    private nonisolated static func signedSeconds(_ value: Double) -> String {
        String(format: "%+.1fs", value)
    }

    private nonisolated static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
    }
}
