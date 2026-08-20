# Product roadmap

Neloa’s next features are ranked by whether they make a demonstrated automation more trustworthy, repairable, and broadly useful without turning the local model into an unbounded computer-use agent.

## Now: readiness, repair, reviewed triggers, diagnostics, evaluation, and safe sharing

Before replay, Neloa performs a deterministic preflight over the exact reviewed plan. It checks:

- Accessibility permission is active.
- Captured applications are still installed.
- Web addresses use a supported HTTP or HTTPS scheme.
- Clicks have either a semantic control name or a complete saved position.
- Text and key actions contain the data needed to execute.
- Structured Google Sheets navigation has both Chrome grounding and a valid cell address.
- Coordinate-only clicks and focus-dependent typing are clearly identified as reliability warnings.

Blocking problems prevent the countdown and explain what must be fixed. Warnings remain runnable but visible. “Run the original” also bypasses Qwen entirely because no model is needed to reproduce an unchanged, already reviewed plan.

The workflow library and review timeline also offer focused re-teaching:

1. Select a broken or coordinate-only action.
2. Bring the target app to the front.
3. Perform just that action again.
4. Compare the new semantic target with the old one.
5. Preview and save the replacement without relearning the rest of the workflow.

The replacement preserves the original action ID, timeline position, variable policy, and approval gate. For text fields, Neloa records both the accessible field identity and a click-position fallback, then attempts to focus the accessible field before replay. This makes application redesigns recoverable and steadily replaces fragile coordinates with accessibility-backed targets.

Neloa also supports daily, weekday, and weekly local reminders. A reminder notification carries only the saved workflow ID and opens the normal “What should change this time?” sheet. User-invoked `neloa://run/…` links provide the same reviewed entry point for Apple Shortcuts and launchers.

For workflows with a demonstrated flexible file input, Neloa can watch one selected local folder while the app is open. It filters partial downloads, waits for a matching file to settle, and queues the exact path as a proposed one-time input change. Reminders, shortcut links, and file arrivals share one FIFO queue; none plans or executes in the background. The exact changes, readiness checks, approvals, and cancellation countdown remain mandatory.

For early support and issue reports, Settings can generate a local diagnostics report that the user inspects before saving. It includes only versions, permission and model state, safe structural counts, readiness categories, and aggregate run outcomes. Recordings, OCR, user-authored content, paths, coordinates, application identities, UUIDs, timestamps from saved work, and raw failures are excluded by construction and regression tests.

Model, prompt, quantization, evidence, and planning changes use a comprehensive local Qwen benchmark. Baseline and candidate JSON reports can now be compared case by case, with newly failing assertions, resolved failures, score changes, and runtime changes preserved in JSON and Markdown. Comparisons reject altered test contracts instead of presenting incomparable scores as an improvement.

Reusable templates let one person share an automation’s teaching outline without exporting a runnable workflow. The format contains only a consciously entered public title, generic action kinds and order, flexible-input flags, and approval flags. It excludes recordings, narration, OCR, workflow names, instructions, values, URLs, paths, app identities, accessibility targets, coordinates, keyboard data, schedules, triggers, identifiers, and timestamps.

An imported template is deliberately non-executable. Neloa previews the generic guide, then requires the recipient to demonstrate the task on their own Mac and review the new capture. Strict schema allowlists, file-size and step-count limits, title validation, hostile-field rejection, deterministic secret-equivalence tests, and a real-file import/teaching smoke test keep this boundary enforceable.

## Defining milestone: bounded live work

Neloa should eventually support a reviewed runtime step such as “summarize the article that is open now” or “extract the total from this month’s report.” This is different from static replay and requires:

- fresh, scoped visual or accessibility evidence;
- an explicit source and destination;
- a typed output contract;
- no authority to invent new navigation;
- a preview or approval before generated content is used.

The first version should support one bounded read/transform/write step inside an otherwise deterministic workflow, not unrestricted autonomous browsing.

## Later: community discovery

- A curated gallery of privacy-safe templates after the local file format and guided teaching flow have proven stable.

## Product gates

Every roadmap feature must preserve these invariants:

- Recordings, narration, OCR, and model inference stay on the Mac by default.
- The local model may interpret evidence but may not silently expand replay authority.
- Consequential actions retain approval checkpoints.
- A user can inspect the exact plan before execution and stop at any time.
- The default experience remains viable on a 16 GB Apple-silicon Mac.
