# Conference venue strategy

Checked against official conference calls on **August 18, 2026**. Dates are Anywhere on Earth (AoE) unless a conference says otherwise. Recheck the linked call before submitting because schedules and policies can change.

## Recommendation

Use a two-stage publication plan:

1. **Submit an IUI 2027 demo by November 10, 2026.** Neloa is already a working intelligent interface, and the demo track is explicitly for interactive prototypes. A four-page system paper and a five-minute video are realistic without pretending that the full research evaluation is finished.
2. **Prepare the archival paper for DIS 2027 or a later IUI/UIST cycle.** The central contribution should be bounded adaptation: a local vision-language model can interpret a demonstration and requested variation, but only deterministic captured actions grant execution authority.

The demo and later paper must make materially different contributions. The demo can establish the system and research questions; the archival paper should add the benchmark, ablations, deployment measurements, and human study. Disclose the earlier demo when submitting the later work.

## Shortlist

| Venue | Best submission | Deadline | Fit | Recommendation |
| --- | --- | --- | --- | --- |
| [ACM IUI 2027](https://iui.acm.org/2027/call-for-posters-demos/) | Demo, 4 pages + video up to 5 minutes | November 10, 2026 | Excellent: intelligent interfaces, democratization of AI, multimodal assistants, human control in automation, privacy, and agent steering are named topics | **Primary near-term target.** Demonstrate teaching, a changed run, approval preservation, and local inference |
| [ACM CHI 2027 Posters](https://chi2027.acm.org/authors/posters/) | Anonymous, non-archival poster paper up to 4 pages + A0 poster | January 21, 2027 | Excellent HCI audience and explicitly welcomes prototypes with or without a completed evaluation | **Best feedback target.** Non-archival status leaves the full paper path open; note the author review-responsibility requirement |
| [ACM CHI 2027 Interactive Demos](https://chi2027.acm.org/authors/interactive-demos/) | 6-page proposal + mandatory walkthrough video up to 5 minutes | January 21, 2027 | Excellent for a polished hands-on experience | Strong alternative if an in-person live demo is preferable to a poster |
| [ACM DIS 2027](https://dis.acm.org/2027/contributing/) | Archival full paper | Abstract January 11; paper January 18, 2027 (dates currently marked provisional) | Good if the contribution is framed around designing understandable, repairable, privacy-preserving agentic automation for non-programmers | **Earliest credible full-paper target**, but only if the evaluation and ethics-ready study are completed |
| [ACM CUI 2027](https://cui.acm.org/2027/) | Full/short paper, WIP, or interactive work; details pending | To be announced; conference July 26–28, 2027 | Good for the spoken teaching, clarification, and voice-repair interaction | Secondary target if the paper narrows around conversational interaction rather than the whole automation system |
| [ACM UIST 2027](https://uist.acm.org/) | Paper or demo; call not yet published | To be announced | Excellent for a technically novel interaction technique and rigorous system evaluation | Watch for the official 2027 call; do not plan around an estimated deadline |

## Deadlines not worth rushing

- [IUI 2027 full papers](https://iui.acm.org/2027/call-for-papers/) require an abstract registered by August 13, 2026; that deadline has passed. The full paper is due August 20. The work is not ready for a defensible full-paper submission on that schedule.
- [CHI 2027 full papers](https://chi2027.acm.org/authors/papers/) are due September 10, 2026. That is enough time to write, but not enough time to design, approve, run, and analyze a rigorous human study. A rushed submission would weaken the work.

## Submission packages

### IUI 2027 demo

- Four-page single-column paper, with references outside the page limit.
- Five-minute or shorter captioned video.
- Live demo script that works without personal accounts or private desktop data.
- One stable scenario and one failure/recovery scenario.
- Reproducible local-model and hardware description.
- In-person presenter for Helsinki, February 8–11, 2027.

### CHI 2027 poster

- Anonymous four-page extended abstract.
- Anonymous A0 poster.
- A concise evaluation result rather than a broad product tour.
- Key questions for discussion with the HCI community.
- Confirm the author team can satisfy the poster track's review-responsibility policy.

### Full paper

- Completed benchmark with frozen tasks and scoring.
- Ablations separating event capture, video/OCR, narration, and model effects.
- Quantization, latency, and memory results on a 16 GB Apple-silicon Mac.
- Safety evaluation including approval-removal and action-invention attacks.
- Ethics-reviewed human study, or claims explicitly limited to a system/benchmark evaluation.
- An anonymized artifact and reproducibility package.

## Cost and publication notes

ACM has moved to open-access publishing. Eligibility for institutional coverage, article-processing charges, and waivers depends on the venue, article type, corresponding author, and current ACM policy. CHI 2027 says its poster extended abstracts are not charged an APC; do not assume the same for an archival full paper. At least one author generally must register and present accepted work, so travel and registration should be included in the decision.
