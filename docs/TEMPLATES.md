# Reusable-template privacy contract

Neloa reusable templates share the shape of a task, not the saved task itself. A template is a non-executable teaching guide. Importing one cannot open an app or web page, click, type, press a key, or create a runnable automation. The recipient must demonstrate the task on their own Mac and review the newly captured workflow before saving it.

## Inspect before saving

Open **My automations**, select an automation, and choose **More → Share reusable template…**. The export sheet starts with a blank public-title field; it never copies the private automation name. Before saving, it shows:

- the complete included-field list;
- the complete excluded-data list;
- a generic teaching outline;
- the exact JSON that will be written.

Neloa writes the file locally only after the user chooses a destination. It never uploads or sends a template automatically.

## Included schema

The version 1 JSON allowlist is intentionally small:

- `format`: the constant `neloa-template`;
- `schemaVersion`: the integer `1`;
- `title`: a consciously entered public title;
- `steps`: an ordered list containing only:
  - `kind`: a generic action category;
  - `isFlexibleInput`: whether a typed input may change between runs;
  - `requiresApproval`: whether that point requires a user checkpoint.

Generic action categories describe teaching intent, such as “Open an app,” “Choose a control,” or “Enter a value that can change.” They contain no target needed to replay the action.

## Excluded by construction

The schema has no place for:

- screen recordings, narration audio, captured frames, or OCR;
- the saved workflow name, transcript, narration, or user instructions;
- typed values, web addresses, file paths, or folder paths;
- application names, bundle identifiers, window titles, or browser tabs;
- accessibility labels, field names, control targets, or selected-cell evidence;
- screen positions, display identifiers, or coordinate fallbacks;
- key codes, modifier flags, copied content, or pasteboard data;
- schedules, watched-folder triggers, run history, or activity receipts;
- workflow, step, run, or linked-step identifiers;
- creation, edit, recording, or action timestamps.

Approval and flexible-input flags communicate safety and teaching intent only. They grant no replay authority.

## Import boundary

Choose **Import template…** in **My automations** and select a `.json` file. Neloa validates it before showing the preview:

- the file must be a regular file no larger than 256 KiB;
- the top-level and per-step key sets must exactly match the allowlist;
- the format and schema version must be supported;
- the public title must be 1–80 visible characters with no surrounding whitespace, line breaks, control characters, bidirectional formatting controls, private-use characters, or invalid Unicode;
- the guide must contain 1–80 steps and at least one demonstrable action;
- only typed-input steps may be marked flexible;
- approval steps must retain their approval flag.

Unknown fields are rejected rather than ignored. This prevents a hostile or future file from smuggling an address, value, target, or recording path into an apparently safe template.

After validation, Neloa displays the generic outline and explicitly states that it is not an executable automation. **Teach this template** carries only that outline into the normal teaching screen. The imported guide does not populate the workflow draft or supply any captured steps. Saving is possible only after a fresh local demonstration and the normal review.

## Verification

`make test` covers the format with two workflows that have identical safe structure but different sentinel secrets in every private field. Their template values and serialized bytes must be identical. The test also scans for forbidden fields, round-trips the public format, exercises real-file reads, and rejects unknown fields, executable data, oversized files, invalid step metadata, approval-only guides, and deceptive Unicode titles.

`make template-test` writes a real template file, imports it, prepares a guided teaching session, and asserts that no executable draft or replay action is created. GitHub Actions runs both checks against source and the packaged app.
