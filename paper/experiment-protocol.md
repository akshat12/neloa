# Proposed next-phase experiment protocol

The short paper’s frozen 15-case formative benchmark and six completed reports are in
`evaluation-manifest.json` and `results/`. This document describes the larger follow-up
study needed before making claims about live-task reliability, modality effects, 16 GB
feasibility, or end-user outcomes. It is not a description of the evidence reported in
the current short paper.

This protocol is preregistration-shaped: decisions should be fixed before collecting paper results, but values marked **proposed** may change during pilot work.

## Study A: workflow reconstruction benchmark

### Corpus

Create **30 proposed workflows** across the currently supported product boundary:

- 6 spreadsheet edits;
- 6 report/filter/download tasks;
- 6 forms, invoices, or expenses;
- 6 approval-controlled draft/submission tasks;
- 6 known-data transfers across apps.

Each workflow should have a clean initial state, a demonstration script, expected action graph, flexible-input schema, approval expectations, and execution-independent grader. Use local fixtures or dedicated study accounts. Do not depend on a participant's real documents or credentials.

### Evidence conditions

Run every workflow under:

1. captured events only;
2. events + selected video frames/OCR;
3. events + frames/OCR + timestamped narration;
4. partial event capture + frames/OCR + narration;
5. video/OCR + narration without native input events.

The last two conditions test graceful degradation; they should not be pooled with ordinary capture when reporting headline performance.

### Metrics

- Executable action precision, recall, and order-sensitive F1.
- Semantic target accuracy.
- Flexible-input role precision, recall, and F1.
- Approval-gate recall; a missing required gate is a critical failure.
- Unsupported invented executable actions; any occurrence is a critical failure.
- Coordinate-only fallback rate.
- Human correction count and time.

Use two independent annotators for a held-out subset. Define matching and disagreement resolution before annotation.

## Study B: variation planning and safety

For each workflow, prepare four held-out requests:

- unchanged replay;
- one supported parameter change;
- multiple supported parameter changes;
- unsupported, ambiguous, or adversarial change.

Add a separate adversarial set covering visible prompt injection, requests to remove approval, requests to add an uncaptured recipient/navigation step, malformed cells or URLs, and application/permission drift.

### Metrics

- Correct changed parameter/target set.
- Unrelated-step preservation.
- Correct clarification or refusal.
- Approval preservation.
- Action-authority violations.
- Readiness-blocker precision and recall.
- Preview latency.

Report exact critical failures in addition to averages. A model cannot compensate for one invented destructive action by scoring well elsewhere.

## Study C: local model and systems ablation

Compare:

- deterministic compiler without model inference;
- Qwen3-VL 4B 4-bit;
- Qwen3-VL 4B 8-bit;
- input ablations from Study A.

Keep the model family, revision, prompts, generation parameters, frame budget, and scoring fixed when comparing quantization. Warm and cold runs should be reported separately.

Measure on at least one 16 GB Apple-silicon Mac:

- model download and on-disk size;
- peak resident memory;
- time to first preview and total planning time;
- tokens or generated fields where available;
- thermal/energy proxy if a repeatable macOS measurement can be established;
- quality metrics from Studies A and B.

An optional cloud or larger-model result may be reported as an offline upper bound, but it is not part of the product path and must not receive private recordings.

## Study D: controlled study with non-programmers

### Design

**Proposed:** 24 participants in a counterbalanced within-subject study. Compare:

- exact replay that requires re-recording when details change;
- Neloa's bounded text/voice adaptation with plan preview.

Participants teach one workflow, repeat it unchanged, adapt values, diagnose a deliberately stale target, and encounter an approval-controlled action. Use study-owned accounts and synthetic data.

### Measures

- successful teaching and adapted-run completion;
- time and interventions;
- incorrect or unintended actions;
- ability to predict what the automation is authorized to do;
- correction/re-teaching success;
- perceived control, workload, trust, and willingness to use;
- interview themes about privacy, voice, preview, repair, and appropriate reliance.

Pilot the protocol before freezing it. Counterbalance task order and condition order. Specify exclusions, missing-data handling, hypotheses, and statistical tests before the main study.

### Ethics and data handling

- Establish the applicable ethics review before recruitment.
- Obtain informed consent for screen and audio recording.
- Do not capture passwords, personal accounts, or personal documents.
- Give participants a visible stop control and a deletion option.
- Store participant data separately from the public benchmark.
- Define retention, access, redaction, and deletion procedures in the consent materials.
- Publish only consented, de-identified aggregates and excerpts.

## Artifact package

The submission artifact should include:

- frozen task manifests and synthetic fixtures;
- expected action graphs and scoring rubric;
- prompt/schema versions and model revision hashes;
- commands for 4-bit and 8-bit runs;
- environment and hardware capture;
- raw machine-readable outputs that contain no private data;
- analysis scripts that regenerate all tables and figures;
- failure examples, including every critical safety failure;
- study materials, questionnaires, codebook, and de-identified data when consent and policy allow.

The existing frozen benchmark is sufficient for the deliberately narrow formative
paper, but not for a general performance claim. A future full study needs the larger task
set, independent ground truth, live postcondition graders, baseline and modality
ablations, a 16 GB test machine, and human-subject evidence described above. Inferential
statistics should be chosen only after a sampling design supports them.
