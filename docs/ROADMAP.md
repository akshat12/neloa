# Product roadmap

Neloa’s next features are ranked by whether they make a demonstrated automation more trustworthy, repairable, and broadly useful without turning the local model into an unbounded computer-use agent.

## Now: readiness, repair, and reviewed run reminders

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

Neloa also supports daily, weekday, and weekly local reminders. A reminder notification carries only the saved workflow ID and opens the normal “What should change this time?” sheet. It does not plan or execute in the background, so the exact changes, readiness checks, approvals, and cancellation countdown remain mandatory.

## Next: more triggers with explicit authority

Useful recurring automations should also be invokable from a file appearing in a folder or a user-invoked shortcut. Triggers must create a prepared run—not silently take consequential actions. Every trigger should still show its changed values, readiness, approval checkpoints, and a cancellation window.

## Defining milestone: bounded live work

Neloa should eventually support a reviewed runtime step such as “summarize the article that is open now” or “extract the total from this month’s report.” This is different from static replay and requires:

- fresh, scoped visual or accessibility evidence;
- an explicit source and destination;
- a typed output contract;
- no authority to invent new navigation;
- a preview or approval before generated content is used.

The first version should support one bounded read/transform/write step inside an otherwise deterministic workflow, not unrestricted autonomous browsing.

## Later: sharing and diagnostics

- Importable automation templates that contain no recordings, secrets, or machine-specific coordinates.
- A privacy-reviewed diagnostics bundle containing workflow structure, readiness results, model version, and redacted failure details.
- Historical model-evaluation comparisons for prompts, quantization tiers, and visual-grounding changes.

## Product gates

Every roadmap feature must preserve these invariants:

- Recordings, narration, OCR, and model inference stay on the Mac by default.
- The local model may interpret evidence but may not silently expand replay authority.
- Consequential actions retain approval checkpoints.
- A user can inspect the exact plan before execution and stop at any time.
- The default experience remains viable on a 16 GB Apple-silicon Mac.
