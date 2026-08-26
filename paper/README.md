# Neloa research paper

This directory contains a submission-ready formative paper and its reproducibility
package. It keeps measured findings separate from future-study plans and does not use
personal recordings, live accounts, or human-participant data.

## Research claim

**Bounded adaptation can give programming by demonstration useful flexibility without
granting a generative model open-ended authority over the computer.**

Neloa aligns screen evidence, application/input events, OCR, and timestamped narration.
A local vision-language model interprets that evidence. During teaching, any inferred
missing actions remain evidence-grounded drafts that require user review. During later
runs, model output may replace only validated values on reviewed variable steps; action
identifiers and approval gates remain fixed. Explicitly implemented deterministic
transforms handle the few supported structural changes.

## Current submission paths

1. **HCII 2027 AI-HCI proposal:** an 800-word proposal due 9 October 2026. The
   conference advertises online participation, but remote presentation eligibility for
   an accepted regular paper must be confirmed with the program chairs.
2. **Interacting with Computers:** rolling journal fallback. Its Short Research Paper
   format is a close fit for the present 3,000–5,000-word manuscript.

The current venue comparison and official links are in
[`docs/CONFERENCE_VENUES.md`](../docs/CONFERENCE_VENUES.md). The IUI 2027 demo is a
secondary option because accepted demos require in-person presentation in Helsinki.

## Current evidence

The frozen synthetic benchmark contains 15 cases, 61 weighted assertions, and 59
critical assertions. Five cases are deterministic and ten invoke Qwen3-VL. Three fresh
processes were run for each pinned 4-bit and 8-bit tier. All six trials passed all cases,
with no critical assertion failures. The 4-bit tier reached the same measured ceiling
with a smaller model and lower peak process memory, so the paper recommends it as the
default only within this tested boundary.

This is formative evidence about executable assertions and local feasibility. It is not
evidence that Neloa works for arbitrary workflows, succeeds against live applications,
is usable by non-programmers, or is safe against indirect prompt injection.

## Reproduce the paper results

From repository root:

```sh
./scripts/run-paper-evaluation.sh
python3 paper/analyze_results.py \
  --input paper/results/raw/frozen-2026-08-25 \
  --output paper/results
python3 paper/finalize_submission.py
```

The collection script intentionally refuses to overwrite an existing report set. Move
or remove an existing frozen-results directory only when deliberately starting a new
study. The finalization script is idempotent and derives every manuscript number from
`paper/results/summary.json`.

Key files:

- `evaluation-manifest.json` — frozen cases, models, revisions, and interpretation limits
- `results/raw/frozen-2026-08-25/` — all six machine-readable and human-readable reports
- `analyze_results.py` — validation and aggregate table generation
- `finalize_submission.py` — mechanical manuscript result insertion
- `submission/short-paper.md` — anonymized short-paper manuscript
- `submission/hcii-2027-proposal.md` — first-stage conference proposal
- `submission/SUBMISSION_CHECKLIST.md` — remaining author and venue steps

## Research integrity rules

- Never extend a performance, reliability, usability, safety, or privacy claim beyond
  its measurement.
- Report model-only and deterministic cases separately, and list every critical failure.
- Record model repository, revision, quantization, prompt/schema version, source commit,
  hardware, and operating system for every run.
- Do not recruit or record participants until the applicable ethics review and consent
  process is established.
- Use clean study accounts and synthetic data; do not publish personal desktop evidence,
  credentials, or identifiable participant content.
- Disclose the public repository, prior dissemination, and generative-AI assistance as
  required by the selected venue.
- Treat the human author as responsible for reviewing every claim, citation, result,
  license, and conclusion.

## What remains before upload

The scientific package is complete for the frozen formative study. The author must add
their name, affiliation, correspondence details, ORCID, funding statement, and conflict
statement; confirm the desired venue; and complete a final human review. See the
submission checklist for the exact fields.

