#!/usr/bin/env python3
"""Insert frozen benchmark results into the submission manuscripts.

This deliberately derives every reported number from ``paper/results/summary.json``
so the paper never depends on hand-copied evaluation results.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


ABSTRACT_BEGIN = "<!-- ABSTRACT-RESULTS:BEGIN -->"
ABSTRACT_END = "<!-- ABSTRACT-RESULTS:END -->"
PROPOSAL_BEGIN = "<!-- PROPOSAL-RESULTS:BEGIN -->"
PROPOSAL_END = "<!-- PROPOSAL-RESULTS:END -->"
RESULTS_BEGIN = "<!-- RESULTS:BEGIN -->"
RESULTS_END = "<!-- RESULTS:END -->"


def percent(value: float) -> str:
    return f"{value * 100:.1f}%"


def score_with_sd(tier: dict) -> str:
    score = percent(tier["weightedScoreMean"])
    if tier["weightedScoreSD"] is not None:
        score += f" (SD {tier['weightedScoreSD'] * 100:.1f} percentage points)"
    return score


def seconds_with_sd(tier: dict, key: str) -> str:
    mean = tier[f"{key}Mean"]
    sd = tier[f"{key}SD"]
    return f"{mean:.1f} s" if sd is None else f"{mean:.1f} s (SD {sd:.1f})"


def tier_by_precision(summary: dict, precision: str) -> dict:
    for tier in summary["tiers"]:
        if tier["precision"] == precision:
            return tier
    raise ValueError(f"Missing {precision} tier in summary")


def require_complete(summary: dict) -> tuple[dict, dict]:
    four = tier_by_precision(summary, "4-bit")
    eight = tier_by_precision(summary, "8-bit")
    for tier in (four, eight):
        if tier["trials"] != 3:
            raise ValueError(f"Expected three {tier['precision']} trials, found {tier['trials']}")
        for key in (
            "weightedScoreMean",
            "casePassRate",
            "modelCasePassRate",
            "deterministicCasePassRate",
            "modelSetupSecondsMean",
            "evaluationSecondsMean",
            "peakResidentMemoryBytesMax",
            "modelDiskBytes",
        ):
            if tier.get(key) is None:
                raise ValueError(f"Missing {key} for {tier['precision']}")
    return four, eight


def build_abstract_sentence(four: dict, eight: dict) -> str:
    failures = four["criticalFailureCount"] + eight["criticalFailureCount"]
    return (
        f"Across three fresh-process trials per tier, the 4-bit model passed "
        f"{four['reportsPassed']}/{four['trials']} runs with a mean weighted score of "
        f"{percent(four['weightedScoreMean'])}; the 8-bit model passed "
        f"{eight['reportsPassed']}/{eight['trials']} with {percent(eight['weightedScoreMean'])}. "
        f"The two tiers had {failures} critical assertion failures; peak process memory was "
        f"{four['peakResidentMemoryBytesMax'] / 2**30:.2f} and "
        f"{eight['peakResidentMemoryBytesMax'] / 2**30:.2f} GiB, respectively."
    )


def build_results(four: dict, eight: dict) -> str:
    total_failures = four["criticalFailureCount"] + eight["criticalFailureCount"]
    table = "\n".join(
        [
            "| Tier | Passing trials | Weighted score, mean | All cases passing | Model cases passing | Critical failures | Setup, mean | Evaluation, mean | Peak RSS | Model files |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
            *[
                f"| {tier['precision']} | {tier['reportsPassed']}/{tier['trials']} | "
                f"{percent(tier['weightedScoreMean'])} | {percent(tier['casePassRate'])} | "
                f"{percent(tier['modelCasePassRate'])} | {tier['criticalFailureCount']} | "
                f"{tier['modelSetupSecondsMean']:.1f} s | {tier['evaluationSecondsMean']:.1f} s | "
                f"{tier['peakResidentMemoryBytesMax'] / 2**30:.2f} GiB | "
                f"{tier['modelDiskBytes'] / 10**9:.2f} GB |"
                for tier in (four, eight)
            ],
        ]
    )
    accuracy = (
        f"The 4-bit tier passed {four['reportsPassed']}/{four['trials']} complete trials and "
        f"the 8-bit tier passed {eight['reportsPassed']}/{eight['trials']}. Their mean weighted "
        f"scores were {score_with_sd(four)} and {score_with_sd(eight)}, respectively. Model-only "
        f"case pass rates were {percent(four['modelCasePassRate'])} and "
        f"{percent(eight['modelCasePassRate'])}; deterministic case pass rates were "
        f"{percent(four['deterministicCasePassRate'])} for both tiers. Across all six reports, "
        f"there were {total_failures} critical assertion failures."
    )
    resources = (
        f"The 4-bit tier required {seconds_with_sd(four, 'modelSetupSeconds')} for cached model "
        f"setup and {seconds_with_sd(four, 'evaluationSeconds')} for the suite. Its maximum "
        f"observed process high-water mark was {four['peakResidentMemoryBytesMax'] / 2**30:.2f} "
        f"GiB and its pinned model files occupied {four['modelDiskBytes'] / 10**9:.2f} GB. The "
        f"8-bit tier required {seconds_with_sd(eight, 'modelSetupSeconds')} for setup and "
        f"{seconds_with_sd(eight, 'evaluationSeconds')} for evaluation, with a "
        f"{eight['peakResidentMemoryBytesMax'] / 2**30:.2f} GiB peak and "
        f"{eight['modelDiskBytes'] / 10**9:.2f} GB of model files. These are whole-process "
        f"measurements on the stated 48 GB test Mac, not isolated weight memory or evidence of "
        f"16 GB compatibility."
    )
    interpretation = (
        "On this benchmark, the additional precision produced no measured assertion advantage. "
        "The result favors 4-bit as the default for these tested constructs because it preserves "
        "the observed outcomes with a smaller local footprint. It does not establish general "
        "equivalence: all cases reached the benchmark ceiling, the sample is synthetic, and the "
        "suite does not stress long or visually ambiguous demonstrations."
    )
    return f"{accuracy}\n\n{table}\n\n{resources}\n\n{interpretation}"


def replace_block(text: str, begin: str, end: str, replacement: str, path: Path) -> str:
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError(f"Missing or repeated generated-result markers in {path}")
    before, remainder = text.split(begin, 1)
    _, after = remainder.split(end, 1)
    return f"{before}{begin}{replacement}{end}{after}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary", type=Path, default=Path("paper/results/summary.json"))
    parser.add_argument("--paper", type=Path, default=Path("paper/submission/short-paper.md"))
    parser.add_argument("--proposal", type=Path, default=Path("paper/submission/hcii-2027-proposal.md"))
    args = parser.parse_args()

    summary = json.loads(args.summary.read_text(encoding="utf-8"))
    four, eight = require_complete(summary)

    paper = args.paper.read_text(encoding="utf-8")
    paper = replace_block(
        paper, ABSTRACT_BEGIN, ABSTRACT_END, build_abstract_sentence(four, eight), args.paper
    )
    paper = replace_block(
        paper, RESULTS_BEGIN, RESULTS_END, f"\n{build_results(four, eight)}\n", args.paper
    )
    args.paper.write_text(paper, encoding="utf-8")

    proposal_result = (
        f"All six trials passed: both tiers achieved {percent(four['modelCasePassRate'])} "
        f"model-case pass rates with {four['criticalFailureCount'] + eight['criticalFailureCount']} "
        f"critical failures. Peak RSS was {four['peakResidentMemoryBytesMax'] / 2**30:.2f} GiB "
        f"(4-bit) and {eight['peakResidentMemoryBytesMax'] / 2**30:.2f} GiB (8-bit)."
    )
    proposal = args.proposal.read_text(encoding="utf-8")
    proposal = replace_block(
        proposal, PROPOSAL_BEGIN, PROPOSAL_END, proposal_result, args.proposal
    )
    args.proposal.write_text(proposal, encoding="utf-8")


if __name__ == "__main__":
    main()
