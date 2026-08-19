# Neloa research paper

This directory is the working area for a conference paper about Neloa. It deliberately separates proposed claims from measured results.

## Working thesis

**Bounded adaptation can make programming by demonstration useful for variable everyday desktop work without granting a generative model open-ended authority over the computer.**

Neloa aligns screen evidence, accessibility and input events, and timestamped narration; uses a local vision-language model to infer meaning and parameters; and preserves the captured action graph as the only source of replay authority. Requested changes can alter reviewed values and semantic targets, but cannot silently add navigation or remove approval gates.

## Publication path

- Near term: IUI 2027 demo submission.
- Feedback option: CHI 2027 poster or interactive demo.
- Full paper: DIS 2027 only if the evaluation is complete; otherwise target a later IUI, UIST, or CHI cycle.

See [the venue strategy](../docs/CONFERENCE_VENUES.md), [paper outline](outline.md), and [experiment protocol](experiment-protocol.md).

## Research integrity rules

- Never write a performance, reliability, usability, or privacy claim before its measurement exists.
- Keep automated benchmark results separate from human-study results.
- Record model repository, revision, quantization, prompt/schema version, Neloa commit, hardware, and operating system for every run.
- Freeze evaluation tasks before collecting the results used in the paper.
- Do not recruit or record human participants until the applicable ethics review and consent process is established.
- Use clean study accounts and synthetic data; never include personal desktop recordings, credentials, or identifiable participant content in the artifact.
- Disclose Neloa's public repository and prior demo/poster publications as required by the target venue's anonymity and prior-publication policies.
- Keep a log of generative-AI assistance used in research and writing, then follow the selected venue's current authorship and disclosure policy. Those policies differ and may change before submission.

## Definition of paper-ready

- The novelty claim survives a focused related-work review.
- At least two researchers independently label a held-out portion of the benchmark, with disagreements resolved using a written rubric.
- All critical safety assertions pass; aggregate scores alone cannot hide an invented action or removed approval.
- Statistical analyses and exclusion criteria are specified before the human study begins.
- Every table and figure can be regenerated from versioned, non-private inputs.
- The artifact runs from a clean checkout and produces machine-readable and human-readable reports.

## Working schedule for the IUI demo

- **By August 28:** finish the novelty review and freeze the demo's single research claim.
- **By September 11:** expand the automated suite to at least 20 frozen workflows and write the annotation rubric.
- **By September 25:** complete pilot runs and fix benchmark—not model—ambiguities.
- **By October 9:** collect the final 4-bit results, resource measurements, and critical-failure audit.
- **By October 23:** finish the four-page draft and record a privacy-safe demo rehearsal.
- **By November 2:** complete external review, accessibility checks, captions, and artifact dry run.
- **November 10:** IUI 2027 poster/demo deadline (AoE).

The human study should not be forced into the demo schedule. Start recruitment only after ethics and consent are resolved, and use that study as evidence for the later full paper.
