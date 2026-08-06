# Neloa

Neloa is a private, voice-first Mac app for automating work that changes a little every time. Show a workflow once, explain the decisions out loud, then run it later by saying only what is different.

## What works

- Records the primary display and optional system audio using ScreenCaptureKit.
- Records and transcribes microphone narration using Apple's on-device speech recognition when available.
- Learns mouse clicks, typed text, key presses, and app changes.
- Samples salient video frames, reads visible interface text with Apple Vision, and uses an in-app Qwen3-VL model to label captured actions and narrated rules.
- Turns the demonstration into an editable, locally saved workflow.
- Lets users add typed or spoken instructions at any recording timestamp: approval wording creates a hard gate, while other free-form guidance becomes an explicit review checkpoint.
- Replays the workflow under user supervision with the signature “Again, but…” interaction.
- Accepts instructions such as “Replace June with July” or “use amount $750.”
- Lets each change be used once, saved as a variant, or made the new default.
- Uses one primary local model—Qwen3-VL 4B at 4-bit—for visual workflow learning and custom run planning, with Apple's on-device model and a narrow deterministic planner as safe fallbacks.
- Pauses at spoken approval rules such as “always ask me before sending.”
- Keeps a local activity receipt showing what ran and what changed.
- Uses the Lagoon visual identity with persistent System, Light, and Dark appearance choices.

## Build and run

Requirements for the complete app: macOS 15 or newer, Apple silicon, 16 GB of memory, and full Xcode. Xcode is free; an Apple Developer Program membership is not required. The Metal compiler included with Xcode builds the local ML runtime.

```sh
make setup-signing
make test
make agent-test
make app
open dist/Neloa.app
```

`make setup-signing` is a one-time development setup that creates a local signing identity in your login Keychain. The first signed build may ask for your Mac login password; choose **Always Allow** so later builds can sign without prompting. Keeping the same identity across builds lets macOS retain Neloa’s privacy permissions. `make test` runs deterministic workflow checks. `make agent-test` makes a real request to Apple's on-device model and verifies the resulting executable change plan.

For UI work on a Mac that only has the Apple Command Line Tools, `make basic-app` creates a build without Qwen. Complete local builds and GitHub releases always enable Qwen.

The app asks for Screen Recording, Accessibility, Microphone, and Speech Recognition permissions. Accessibility lets Neloa learn clicks and typing during a demonstration and replay only the actions you approve. macOS may require reopening Neloa after it is granted.

## Install an unsigned preview

Unsigned Apple silicon ZIPs are published on the GitHub Releases page. Because these previews are not notarized by Apple, macOS will block the first launch until you explicitly approve it:

1. Download the ZIP and move `Neloa.app` to Applications.
2. Try to open Neloa once, then dismiss the security warning.
3. Open **System Settings → Privacy & Security**.
4. Scroll to **Security**, choose **Open Anyway**, authenticate, and confirm **Open**.

Only use a download from the official Neloa repository. Each release includes a `.sha256` file so the download can be checked with `shasum -a 256 -c <checksum-file>`. macOS may ask for Neloa's recording and control permissions again after an update because these previews do not have a stable Apple-issued Developer ID.

Maintainers can reproduce the downloadable artifacts locally with:

```sh
make unsigned-release RELEASE_VERSION=0.2.17 BUILD_NUMBER=20
```

Release packaging stages its ad-hoc app separately and does not overwrite `dist/Neloa.app`. The local app therefore keeps its stable development signature and its macOS privacy permissions.

See the [distribution plan](docs/DISTRIBUTION.md) for the release workflow, limitations, and the future path to signed builds.

## Local model

Neloa offers a one-click, resumable first-time download of Qwen3-VL 4B Instruct (4-bit), approximately 3.1 GB. It is stored under Neloa's Application Support directory and runs directly on the Apple GPU through MLX Swift. There is no Ollama installation, Terminal command, local server, account, or cloud API.

The model receives only a small set of salient recording frames, locally recognized interface text, captured actions, and narration. Model output may improve action names and add clearly narrated rules, but it cannot add replayable clicks or keystrokes: Neloa preserves the deterministic capture as the execution authority. The model can be removed from Settings without deleting automations or recordings.

If the model is skipped or unavailable, Neloa still records and replays captured actions, handles explicit value replacements locally, and can use Apple's on-device language model as a planning fallback on supported macOS versions.

## Privacy and safety

Workflow recordings and definitions are saved in the current user's Application Support directory. Neloa does not upload them. Run plans are previewed before execution, there is a three-second cancellation window, and approval steps pause execution.

Local builds use a dedicated development identity when one is installed. That identity is only for development; never distribute a build signed with it.

## Building on Neloa

Forks and derivative work are welcome under the Apache License 2.0. If you build something based on Neloa, please message the maintainer and tell us what you are making—we would genuinely like to hear about it and explore ways to work together. This is a friendly request, not a condition of the open-source license.

The Neloa name, logo, app icon, and visual identity are reserved for the official project. Derivative products should use their own name and branding unless written permission has been granted. See [TRADEMARKS.md](TRADEMARKS.md) for details.

## License

Neloa is licensed under the [Apache License 2.0](LICENSE). Distributed copies and derivative works must preserve the applicable license, copyright, and attribution notices described in [NOTICE](NOTICE).
