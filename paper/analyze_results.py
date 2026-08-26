#!/usr/bin/env python3
"""Aggregate Neloa's machine-readable model-evaluation reports."""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from collections import defaultdict
from pathlib import Path


def mean(values: list[float]) -> float | None:
    return statistics.fmean(values) if values else None


def sample_sd(values: list[float]) -> float | None:
    return statistics.stdev(values) if len(values) > 1 else None


def rounded(value: float | None, digits: int = 3) -> float | None:
    return round(value, digits) if value is not None else None


def load_manifest(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def load_reports(directory: Path) -> list[dict]:
    reports = []
    for path in sorted(directory.glob("*.json")):
        with path.open(encoding="utf-8") as handle:
            report = json.load(handle)
        report["_source"] = path.name
        reports.append(report)
    if not reports:
        raise SystemExit(f"No JSON reports found in {directory}")
    return reports


def validate(reports: list[dict], manifest: dict) -> None:
    expected_cases = {item["id"] for item in manifest["cases"]}
    expected_tiers = {item["precision"]: item for item in manifest["tiers"]}
    grouped = defaultdict(list)
    for report in reports:
        precision = report["precision"]
        if precision not in expected_tiers:
            raise SystemExit(f"Unexpected precision in {report['_source']}: {precision}")
        expected = expected_tiers[precision]
        if report["modelID"] != expected["modelID"] or report["modelRevision"] != expected["modelRevision"]:
            raise SystemExit(f"Model provenance mismatch in {report['_source']}")
        if {item["id"] for item in report["cases"]} != expected_cases:
            raise SystemExit(f"Case-set mismatch in {report['_source']}")
        grouped[precision].append(report)
    for precision in expected_tiers:
        actual = len(grouped[precision])
        expected_count = manifest["trialsPerTier"]
        if actual != expected_count:
            raise SystemExit(f"Expected {expected_count} {precision} reports; found {actual}")


def summarize(reports: list[dict], manifest: dict) -> dict:
    class_by_case = {item["id"]: item["class"] for item in manifest["cases"]}
    grouped: dict[str, list[dict]] = defaultdict(list)
    for report in reports:
        grouped[report["precision"]].append(report)

    tiers = []
    case_rows = []
    for precision in [item["precision"] for item in manifest["tiers"]]:
        tier_reports = grouped[precision]
        scores = [float(item["score"]) for item in tier_reports]
        durations = [float(item["durationSeconds"]) for item in tier_reports]
        setups = [float(item["modelSetupSeconds"]) for item in tier_reports if item.get("modelSetupSeconds") is not None]
        peaks = [int(item["peakResidentMemoryBytes"]) for item in tier_reports if item.get("peakResidentMemoryBytes") is not None]
        critical_failures = [
            {"trial": report.get("trialID"), "case": case["id"], "assertion": assertion["name"]}
            for report in tier_reports
            for case in report["cases"]
            for assertion in case["assertions"]
            if assertion["critical"] and not assertion["passed"]
        ]
        all_cases = [case for report in tier_reports for case in report["cases"]]
        model_cases = [case for case in all_cases if class_by_case[case["id"]] == "model"]
        deterministic_cases = [case for case in all_cases if class_by_case[case["id"]] == "deterministic"]
        tiers.append({
            "precision": precision,
            "trials": len(tier_reports),
            "reportsPassed": sum(bool(item["passed"]) for item in tier_reports),
            "weightedScoreMean": rounded(mean(scores)),
            "weightedScoreSD": rounded(sample_sd(scores)),
            "casePassRate": rounded(sum(bool(case["passed"]) for case in all_cases) / len(all_cases)),
            "modelCasePassRate": rounded(sum(bool(case["passed"]) for case in model_cases) / len(model_cases)),
            "deterministicCasePassRate": rounded(sum(bool(case["passed"]) for case in deterministic_cases) / len(deterministic_cases)),
            "criticalFailureCount": len(critical_failures),
            "criticalFailures": critical_failures,
            "modelSetupSecondsMean": rounded(mean(setups), 2),
            "modelSetupSecondsSD": rounded(sample_sd(setups), 2),
            "evaluationSecondsMean": rounded(mean(durations), 2),
            "evaluationSecondsSD": rounded(sample_sd(durations), 2),
            "peakResidentMemoryBytesMax": max(peaks) if peaks else None,
            "modelDiskBytes": tier_reports[0].get("modelDiskBytes"),
            "operatingSystem": tier_reports[0]["operatingSystem"],
            "physicalMemoryBytes": tier_reports[0]["physicalMemoryBytes"],
            "processorCount": tier_reports[0].get("processorCount"),
            "gitCommits": sorted({item.get("gitCommit") for item in tier_reports}),
        })

        cases_by_id = defaultdict(list)
        for report in tier_reports:
            for case in report["cases"]:
                cases_by_id[case["id"]].append(case)
        for case_id in [item["id"] for item in manifest["cases"]]:
            cases = cases_by_id[case_id]
            case_rows.append({
                "precision": precision,
                "case": case_id,
                "class": class_by_case[case_id],
                "passes": sum(bool(case["passed"]) for case in cases),
                "trials": len(cases),
                "scoreMean": rounded(mean([float(case["score"]) for case in cases])),
                "durationSecondsMean": rounded(mean([float(case["durationSeconds"]) for case in cases]), 2),
                "criticalFailures": sum(
                    bool(assertion["critical"] and not assertion["passed"])
                    for case in cases for assertion in case["assertions"]
                ),
            })

    return {
        "benchmark": manifest["benchmark"],
        "frozenCommit": manifest["frozenCommit"],
        "reportCount": len(reports),
        "tiers": tiers,
        "cases": case_rows,
        "interpretationBoundary": manifest["purpose"],
        "knownLimits": manifest["knownLimits"],
    }


def write_outputs(summary: dict, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    with (output / "summary.json").open("w", encoding="utf-8") as handle:
        json.dump(summary, handle, indent=2, sort_keys=True)
        handle.write("\n")

    tier_fields = [
        "precision", "trials", "reportsPassed", "weightedScoreMean", "weightedScoreSD",
        "casePassRate", "modelCasePassRate", "deterministicCasePassRate", "criticalFailureCount",
        "modelSetupSecondsMean", "modelSetupSecondsSD", "evaluationSecondsMean",
        "evaluationSecondsSD", "peakResidentMemoryBytesMax", "modelDiskBytes",
    ]
    with (output / "summary.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=tier_fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(summary["tiers"])

    case_fields = ["precision", "case", "class", "passes", "trials", "scoreMean", "durationSecondsMean", "criticalFailures"]
    with (output / "case-results.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=case_fields)
        writer.writeheader()
        writer.writerows(summary["cases"])

    lines = [
        "| Tier | Runs passing | Weighted score | Cases passing | Model cases passing | Critical failures | Setup | Evaluation | Peak memory | Model files |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for tier in summary["tiers"]:
        score = f"{tier['weightedScoreMean'] * 100:.1f}%"
        score_sd = tier["weightedScoreSD"]
        if score_sd is not None:
            score += f" ± {score_sd * 100:.1f} pp"
        lines.append(
            f"| {tier['precision']} | {tier['reportsPassed']}/{tier['trials']} | {score} | "
            f"{tier['casePassRate'] * 100:.1f}% | {tier['modelCasePassRate'] * 100:.1f}% | "
            f"{tier['criticalFailureCount']} | {tier['modelSetupSecondsMean']:.1f} s | "
            f"{tier['evaluationSecondsMean']:.1f} s | {tier['peakResidentMemoryBytesMax'] / 2**30:.2f} GiB | "
            f"{tier['modelDiskBytes'] / 10**9:.2f} GB |"
        )
    (output / "results-table.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("evaluation-manifest.json"))
    args = parser.parse_args()
    manifest = load_manifest(args.manifest)
    reports = load_reports(args.input)
    validate(reports, manifest)
    write_outputs(summarize(reports, manifest), args.output)


if __name__ == "__main__":
    main()
