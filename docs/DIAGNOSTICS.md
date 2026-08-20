# Diagnostics privacy contract

Neloa can create a technical JSON report for issue triage without exporting the work a person taught it. The report is generated locally, shown in full, and saved only after the user chooses **Save diagnostics…**. Neloa never uploads it automatically.

## User journey

1. Open **Settings**.
2. Find **Support & diagnostics** and select **Preview diagnostics**.
3. Review the included and excluded categories and inspect the exact selectable JSON.
4. Close the preview, or select **Save diagnostics…** and choose a local destination.
5. Open the saved file before attaching it to an issue or sharing it with anyone.

## Included

- Neloa version, build, and build mode.
- macOS version, CPU architecture, and rounded physical-memory capacity.
- Screen Recording, Accessibility, Microphone, and Speech Recognition state.
- Qwen family, tier, precision, pinned revision, installation, eligibility, and sanitized lifecycle state.
- Automation counts and, for each unnamed automation, action-type counts, grounding counts, approval and flexible-input counts, recording-presence booleans, trigger-presence booleans, and readiness issue categories and counts.
- Aggregate completed, stopped, and failed run counts.
- Whether Neloa currently has a storage issue, without its message or path.

## Excluded

- Screen recordings, audio recordings, screenshots, OCR, or extracted evidence.
- Workflow names, transcripts, narration text, saved instructions, action titles, action details, or control labels.
- Typed values, before/after changes, URLs, file paths, folder paths, recording paths, or storage paths.
- Click coordinates, display identifiers, timestamps from workflows or runs, confidence values, or keyboard data.
- Application names, bundle identifiers, automation IDs, action IDs, run IDs, or other UUIDs.
- Run instructions, summaries, failure messages, model error text, or storage error details.

The JSON does state whether a recording, transcript, reminder, or watched folder exists because those booleans help diagnose missing capabilities without revealing their contents or configuration.

## Verification

The deterministic self-test constructs two fixtures with different secret workflow names, transcripts, narration, URLs, typed values, file paths, folder paths, app identities, coordinates, display IDs, UUIDs, timestamps, changes, run messages, and model failure text. When their safe structure and health are the same, their diagnostics reports must be byte-for-byte identical. The test also rejects private sentinels, paths, coordinates, UUID-shaped text, and identifier field names, then round-trips the report through JSON decoding.

This is a structural allowlist, not a best-effort text scrubber: report fields are populated from counts, booleans, public version constants, and fixed status codes. User-authored strings and machine-specific paths are never passed into the encoded model.
