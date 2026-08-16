# Supported scenarios

Neloa is designed for demonstrated work whose route stays mostly stable while a bounded set of values changes. Support means Neloa can capture a reviewable action graph, identify flexible inputs, preview one-off changes, replay the captured actions, and pause before consequential controls.

## First-class scenarios

### Recurring spreadsheets

- Update known cells with new labels, dates, amounts, or thresholds.
- Retarget a demonstrated value to a different Google Sheets cell through structured Go to range navigation.
- Recover clearly visible cell edits from selected-cell and formula-bar video evidence when native input capture is incomplete.

### Reports and downloads

- Open a demonstrated report portal using a stable URL.
- Change named fields such as report month, account, region, amount, or threshold.
- Download the resulting report without adding an unnecessary approval pause.

### Forms, invoices, expenses, and client records

- Retain accessible field roles such as Client name, Invoice amount, and Due date at capture time.
- Map several requested values to the correct fields in a single run instruction.
- Keep navigation and captured actions fixed while changing only reviewed typed values.

### Approval-controlled drafts and submissions

- Preserve user-narrated rules such as “always ask before sending.”
- Automatically pause before captured Send, Share, Submit, Publish, Purchase, Pay, Delete, Remove, and Upload controls.
- Refuse a run instruction that tries to remove the pause or introduce an uncaptured side effect.

### Moving known information between apps

- Replay demonstrated app switches and keyboard shortcuts.
- Present Command-C and Command-V as Copy selected content and Paste copied content in review.
- Move the content currently selected by the demonstrated workflow; Neloa does not invent or transform that content.

## Reliability boundary

These workflows still depend on the demonstrated applications exposing useful accessibility labels or retaining compatible layouts. Neloa prefers semantic control labels when available and falls back to captured coordinates. Coordinate-only actions should be reviewed carefully after an app redesign.

## Deferred: live research and synthesis

A workflow such as “open a different article, read it, create a new summary, and paste that summary into TextEdit” is intentionally not claimed as supported yet. Today, the run agent customizes reviewed typed inputs; it does not inspect arbitrary live content and generate a new value midway through replay.

Supporting this well requires a runtime reasoning step with fresh visual evidence, explicit input/output grounding, source visibility, bounded tool authority, and a preview or approval checkpoint before generated content is used. That is a separate—and potentially defining—product milestone rather than a variation of static replay.
