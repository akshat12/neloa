# Publication venue strategy

Checked against official venue guidance on **August 25, 2026**. Recheck policies and fees immediately before submission.

## Decision

Prepare one evidence-complete, venue-neutral short paper and use this order:

1. **HCI International 2027, AI-HCI — primary conference.** It is the clearest current conference fit that explicitly offers online participation. Submit the required 800-word proposal by October 9, 2026. If accepted, expand the same evidence into the 10–20-page LNCS camera-ready paper due January 29, 2027.
2. **Interacting with Computers — primary no-travel fallback and strongest short-paper fit.** It accepts rolling 3,000–5,000-word HCI research papers, uses double-anonymized review, and does not require open-access publication. Submit here if HCII confirms that accepted authors cannot present remotely, or if a journal is preferred.
3. **Frontiers in Computer Science, Human-Media Interaction — paid journal fallback.** Its Brief Research Report format is capped at 4,000 words and four figures/tables, but the current article-processing charge is CHF 990.
4. **ACM IUI 2027 demo — fit-first, travel-required alternative.** Its four-page demo format is excellent for Neloa, but the official call requires an in-person demo in Helsinki. Use it only if travel becomes acceptable.

The current paper should make a bounded system claim: Neloa separates model interpretation from deterministic execution authority, and a frozen synthetic benchmark measures whether supported adaptations preserve actions and approvals. It must not claim end-user usability or live-desktop task success without a human or live-task study.

## Shortlist

| Venue | Submission | Timing | Remote/travel status | Cost note | Fit and decision |
| --- | --- | --- | --- | --- | --- |
| [HCII 2027 Regular Papers](https://2027.hci.international/papers.html), [AI-HCI area](https://2027.hci.international/ai-hci) | 800-word proposal; accepted papers become 10–20 LNCS pages | Proposal Oct. 9, 2026; final Jan. 29, 2027; conference July 25–30, 2027 | [Conference homepage](https://2027.hci.international/) says on-site with an online-participation option. Confirm that this includes remote presentation before registering | One author registration is required; verify the online rate when posted | **Primary conference.** Strong fit for human-agent collaboration, speech interaction, privacy, control, and safe generative AI |
| [Interacting with Computers](https://academic.oup.com/iwc/pages/General_Instructions) | Short research paper, recommended 3,000–5,000 words | Rolling | Journal; no travel | Standard publication is available; open access is optional and charged only if selected | **Primary fallback.** Strong HCI, human-centred AI, privacy/trust, and interaction-design scope; double-anonymized review |
| [Frontiers in Computer Science: Human-Media Interaction](https://www.frontiersin.org/journals/computer-science/sections/human-media-interaction/for-authors/article-types) | Brief Research Report, up to 4,000 words and four figures/tables | Rolling | Journal; no travel | [Current B-type APC](https://www.frontiersin.org/journals/computer-science/sections/human-media-interaction/for-authors/publishing-fees): CHF 990; fee-support program exists | Good format and topical fit, but use only if the fee is acceptable |
| [ACM IUI 2027 Posters & Demos](https://iui.acm.org/2027/call-for-posters-demos/) | Four pages; demo also requires a captioned video up to five minutes | Nov. 10, 2026 | **In-person presentation required** in Helsinki, Feb. 8–11, 2027 | ACM APC/waiver and registration depend on current author circumstances | Best intellectual fit, but not remote-friendly |
| [Journal of Open Research Software](https://openresearchsoftware.metajnl.com/about/submissions) | “Issues in Research Software” article, 3,000–4,000 words | Rolling | Journal; no travel | APC applies; waiver requests are possible | Only a secondary fit: the section is about creating and evaluating reusable research software, while Neloa is primarily an HCI system |

## Venues not ready for this submission

- **JOSS:** its [current requirements](https://joss.readthedocs.io/en/latest/submitting.html) say the paper must not focus on new research results, require more than six months of public development history, and require demonstrated research impact. Neloa is not eligible yet. Revisit after sustained public use if a separate software paper becomes worthwhile.
- **IUI 2027 full paper:** the abstract and paper deadlines have passed, and accepted work requires in-person presentation.
- **A rushed human-study venue:** no usability, workload, trust, or non-programmer effectiveness claims should be added until ethics, consent, recruitment, and analysis are complete.

## Primary submission package: HCII 2027

### Proposal requirements

- 800 words, excluding references.
- PDF or DOCX; no special first-stage format.
- Objective and significance.
- Methods/approach.
- Results/findings.
- Contributions and implications.
- Single-blind review, so author details are included.

### Remote-participation check

Before paying or submitting the camera-ready paper, email `program@2027.hci.international` with this exact question:

> Does the HCII 2027 online-participation option permit the registered author of an accepted regular paper in AI-HCI to deliver the required 20-minute presentation remotely, with the paper included in the LNCS proceedings?

Do not infer the answer from the general online-participation statement alone.

## Journal fallback package: Interacting with Computers

- 3,000–5,000-word anonymized short research paper, excluding abstract and references.
- Separate title page with authors, affiliations, correspondence, and acknowledgements.
- Abstract and keywords.
- Three or four research highlights, each under roughly 100 characters.
- Data/software availability statement.
- AI-assistance disclosure in the cover letter and Methods or Acknowledgements.
- Figure legends and alt text.
- ORCID for the submitting author.
- PDF is acceptable at first submission; exact journal styling is not required.

## Evidence boundary for this draft

The frozen evaluation contains 15 synthetic, account-free cases and three trials for each local Qwen3-VL quantization tier. It measures executable invariants, model-dependent reconstruction/adaptation assertions, timing, model size, and peak resident memory. It does **not** measure:

- success on live third-party applications;
- robustness across arbitrary workflows;
- usability by non-programmers;
- human trust, workload, or comprehension;
- performance on a 16 GB Mac; or
- privacy against a compromised local machine.

These limitations belong in the abstract-adjacent framing, Results, and Discussion—not only in a final caveat.
