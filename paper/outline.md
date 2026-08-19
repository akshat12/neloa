# Working paper outline

## Title candidates

1. **Bounded Adaptation: Local Multimodal Programming by Demonstration for Everyday Desktop Work**
2. **Teach Once, Change the Details: Privacy-Preserving Agentic Automation from Demonstration and Voice**
3. **Neloa: A Local, User-Governed Agent for Adaptive Desktop Automation**

The first title makes the research claim rather than the product name the focus.

## Working abstract

Desktop automation tools usually require programming or reproduce a rigid sequence, while general computer-use agents can adapt but may act beyond what a user demonstrated. We present Neloa, a macOS programming-by-demonstration system for workflows whose route remains stable while values such as dates, amounts, files, and recipients vary. Neloa aligns screen recording, interface and input events, and timestamped spoken explanation; a local quantized vision-language model converts that evidence into a reviewable workflow. Its bounded-adaptation architecture separates interpretation from authority: model output may label actions and propose changes to reviewed parameters, but only captured actions can be executed, and consequential controls retain approval gates. We propose a reproducible benchmark spanning complete, partial, and video-only evidence; ablations of event, visual, and narration inputs; local deployment measurements; and a controlled study with non-programmers. **Measured results will replace this final sentence before submission.**

## Research questions

- **RQ1 — Reconstruction:** How accurately does aligned event, visual, and narration evidence reconstruct the demonstrated action graph under complete and incomplete capture?
- **RQ2 — Adaptation:** How accurately can a local model map natural-language variations to the intended parameters and targets without changing unrelated steps?
- **RQ3 — Safety:** Does separating interpretation from execution authority prevent invented actions and preserve consequential approval gates under unsupported or adversarial requests?
- **RQ4 — Local feasibility:** What accuracy, planning latency, energy, and peak-memory trade-offs result from 4-bit and 8-bit variants on a 16 GB Apple-silicon Mac?
- **RQ5 — Human factors:** Can non-programmers teach, adapt, inspect, and repair workflows more effectively than with exact replay, and do they understand what the automation is authorized to do?

## Claimed contributions, pending evidence

1. A multimodal desktop teaching pipeline that puts video frames, OCR, accessibility/input events, app context, and word-level narration timestamps on a shared session clock.
2. A bounded-adaptation architecture in which a generative model interprets demonstrations and variation requests but cannot expand the deterministic replay authority or remove approval gates.
3. A local deployment design using one vision-language model family with two quantization tiers, plus deterministic operation when the model is unnecessary or unavailable.
4. A reproducible evaluation suite for reconstruction, partial-capture repair, parameter adaptation, unsafe-request resistance, resource use, and end-user repair.

These are hypotheses until the corresponding implementation and evaluation are complete. In particular, “private” should mean that normal inference and stored evidence remain on the Mac; it must not imply formal confidentiality or resistance to every local compromise.

## Section plan

### 1. Introduction

- Tension between rigid macros and open-ended computer-use agents.
- Motivating workflow: demonstrate a recurring report once, then request a new date and amount.
- Failure modes that matter to non-programmers: wrong target, invented action, missing approval, stale coordinate, and private evidence leaving the device.
- Thesis and contributions.

### 2. Related work

- Programming by demonstration and end-user development.
- Multimodal teaching with natural language and GUI structure, especially SUGILITE and its repair/privacy extensions.
- Computer-use agents and execution-based benchmarks such as OSWorld.
- GUI grounding, screen representations, and accessibility trees.
- Local/on-device GUI agents and privacy-preserving interaction.
- Mixed-initiative repair, approval, explainability, and appropriate reliance.

The novelty review must explicitly distinguish Neloa from SUGILITE: voice plus demonstration and parameter inference already exist. The paper should instead test whether shared-clock desktop evidence, local visual inference, and a hard authority boundary create a useful and safer form of adaptive automation.

### 3. Design goals and threat model

- Non-programmer teachability.
- Bounded variation rather than arbitrary autonomy.
- Local-first evidence and inference.
- Review before replay and approval before consequences.
- Threats: prompt injection in visible content, ambiguous narration, missing events, layout drift, focus drift, malicious variation requests, and model hallucination.
- Out of scope: hostile local processes, compromised operating system, and arbitrary live research/synthesis in the current version.

### 4. System

- Capture sources and shared timestamp representation.
- Salient frame selection and OCR.
- Action graph, semantic targets, flexible inputs, and approval nodes.
- Qwen3-VL inference, schemas, 4-bit/8-bit tiers, and deterministic fallbacks.
- Plan preview, readiness preflight, countdown, supervised replay, receipts, and single-step repair.
- Authority invariant: every executable action must trace to captured evidence or an explicitly supported deterministic transformation of a captured action.

### 5. Benchmark and method

- Task taxonomy and frozen fixtures.
- Ground-truth workflow annotation.
- Reconstruction and adaptation conditions.
- Baselines and ablations.
- Safety attack set.
- Local performance measurement.
- Human-study design and analysis plan.

### 6. Results

- Reconstruction and repair accuracy.
- Adaptation and safety outcomes.
- Quantization/resource trade-offs.
- Human task performance and qualitative themes.
- All tables generated from committed analysis scripts; no manually transcribed numbers.

### 7. Discussion

- Where bounded adaptation is more useful than a macro.
- Where a general computer-use agent remains necessary.
- Cost of keeping execution authority narrow.
- Accessibility-tree availability and coordinate fallbacks.
- Privacy benefits and limitations of local inference.
- Transfer beyond macOS.

### 8. Limitations, ethics, and responsible use

- Small local models and visual grounding errors.
- Platform and hardware scope.
- Recording sensitivity and consent.
- Misuse and unintended actions.
- Study sample limitations and researcher positionality.
- Open-source benefits and risks.

### 9. Conclusion

- Restate only findings supported by the evaluation.

## Initial related-work seeds

- Li, Azaria, and Myers. “SUGILITE: Creating Multimodal Smartphone Automation by Demonstration.” CHI 2017.
- Li, Mitchell, and Myers. “Interactive Task Learning from GUI-Grounded Natural Language Instructions and Demonstrations.” ACL System Demonstrations 2020.
- Xie et al. “OSWorld: Benchmarking Multimodal Agents for Open-Ended Tasks in Real Computer Environments.” NeurIPS 2024.
- Hu et al. “PrivAuto: Practical Insights of On-Device Privacy-Preserving Agentic Systems for Mobile GUI Automation.” UISE at ICSE 2026.

These are starting points, not a complete literature review.
