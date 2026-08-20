# Automation health

Neloa checks saved automations before a model is loaded or a run is planned. The indicator in **My automations** and the automation detail card use the same deterministic preflight as the final run preview.

## States

- **Ready**: the current control permission, captured applications, and saved replay data pass the structural checks.
- **Review recommended**: replay is structurally possible, but one or more clicks use saved screen positions or a text action depends on an earlier action focusing the correct field.
- **Needs attention**: replay is blocked by missing control permission, an unavailable captured app, an empty workflow, or incomplete action data.

The library does not load Qwen to calculate health. Results come only from local permission state, installed-app lookup, and the saved action graph.

## Checks

For the unchanged saved workflow, Neloa verifies:

- Accessibility permission is active for replay.
- Each captured app with an identity is installed or currently running.
- An app-opening action names an app or bundle identifier.
- A web action contains an HTTP or HTTPS address.
- A click has either a semantic control target or a complete saved position.
- A text action contains text; actions without a semantic target or position receive a focus-dependency warning.
- A keyboard action has a saved key code.
- Google Sheets cell navigation is grounded to Chrome and uses a valid cell address.
- The workflow contains at least one saved step.

Approval gates and required-app names are summarized alongside the result. Issues preserve the same categories and wording used in run preview.

## Recovery

Permission blockers offer **Grant control access** and **Open Neloa Settings**. Application, action, target, coordinate, and focus issues offer **Review & repair**, which re-teaches only the selected fragile action while preserving the rest of the workflow.

Neloa evaluates health again after any permission or workflow change. It also evaluates the exact customized plan in the run preview, immediately before the cancellation countdown.

## Limits

Health is a structural readiness signal, not a promise that an external interface or its data is unchanged. An app may redesign a correctly named control after the check. Coordinate-based actions still depend on display arrangement and layout. Users should review warnings, supervise replay, and keep approval gates around consequential actions.

`make test` covers ready, warning, permission-blocked, missing-app, and malformed-action states and verifies that library health retains the run preflight’s exact issue categories.
