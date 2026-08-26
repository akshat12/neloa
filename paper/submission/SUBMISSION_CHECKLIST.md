# Submission checklist

This directory contains two submission paths built from the same frozen study.
Complete the author-only fields below before uploading either package.

## Author details still required

Copy `author-metadata.example.json` to the ignored file `author-metadata.json`, replace
the example values, set `is_example` to `false`, and run:

```sh
python3 paper/render_submission_metadata.py \
  --metadata paper/submission/author-metadata.json
```

The command validates the ORCID checksum and required declarations, then creates a
private journal title-page PDF, cover letter, HCII CMS entry, and personalized remote-
presentation inquiry under `output/submission/identifying/`.

- [ ] Full author name exactly as it should appear in publication
- [ ] Institutional or independent-researcher affiliation
- [ ] City and country for the affiliation
- [ ] Corresponding email address
- [ ] Corresponding postal address and telephone number
- [ ] ORCID (required by *Interacting with Computers*)
- [ ] Funding statement, including “no external funding” when applicable
- [ ] Conflict-of-interest statement
- [ ] Acknowledgements, if any

Do not add identifying details to the anonymized manuscript used for double-anonymous
review. Enter them in the journal submission system and on a separate title page when
the venue requests one.

## HCII 2027 AI-HCI proposal

- [ ] Confirm with `program@2027.hci.international` that an accepted paper can be
      presented remotely; the conference advertises online participation but does not
      state the paper-presenter rule on the regular-paper page.
- [ ] Keep the proposal at no more than 800 words, excluding references.
- [ ] Supply title, author details, keywords, and proposal through the CMS.
- [ ] Submit by 9 October 2026, anywhere on Earth.
- [ ] If invited, expand the manuscript to the required 10–20 pages (typically 12)
      and apply the conference template by 29 January 2027.
- [ ] Budget for at least one author registration if accepted.

## Interacting with Computers short research paper

- [ ] Keep the main text within the journal’s 3,000–5,000-word guidance.
- [ ] Upload the anonymized PDF as the main manuscript.
- [ ] Generate and upload `output/submission/identifying/iwc-title-page.pdf` as the
      separate title page.
- [ ] Confirm that the abstract is 150–200 words, no more than six keywords are present,
      and the references, figure caption, and figure alt text are included.
- [ ] Confirm that the review manuscript contains no public repository URL or other
      identifying metadata; upload identifying information only as the Title Page.
- [ ] Upload the three research highlights from `research-highlights.txt` when asked.
- [ ] Include data/software availability, funding, conflicts, and AI-assistance
      disclosures in the submission metadata or manuscript as required.
- [ ] Select standard publication if avoiding an open-access fee; open access is
      optional for this journal.

## Reproducibility and integrity

- [ ] Run `./scripts/run-paper-evaluation.sh` only when intentionally collecting a new
      frozen result set; the script refuses to overwrite existing reports.
- [ ] Run `python3 paper/analyze_results.py` and
      `python3 paper/finalize_submission.py` from repository root.
- [ ] Run `python3 paper/build_pdf.py` and confirm both PDFs appear in `output/pdf/`.
- [ ] Confirm that no result placeholders remain in the manuscript or proposal.
- [ ] Confirm all six raw JSON reports, the manifest, summary files, analysis code,
      and exact model revisions are committed.
- [ ] Build the application and run the self-test.
- [ ] Rebuild the PDF and inspect every rendered page.
- [ ] Review every factual claim and citation as the human author before submission.

## Generated files

- `output/pdf/neloa-short-paper.pdf` — anonymized journal-style manuscript
- `output/pdf/neloa-hcii-2027-proposal.pdf` — anonymized first-stage proposal
- `output/submission/identifying/iwc-title-page.pdf` — private identifying title page
- `output/submission/identifying/iwc-cover-letter.txt` — personalized cover letter
- `output/submission/identifying/hcii-cms-metadata.md` — author/CMS handoff
- `output/submission/identifying/hcii-remote-presentation-inquiry.txt` — personalized
  remote-presentation inquiry
- `iwc-title-page-template.md` — identifying metadata kept separate from review copy
- `iwc-cover-letter.md` — editable journal cover letter
- `research-highlights.txt` — three journal highlights, each under 100 characters
