# Neloa

Neloa is a private, voice-first Mac app for automating work that changes a little every time. Show a workflow once, explain the decisions out loud, then run it later by saying only what is different.

## What works

- Records the primary display and optional system audio using ScreenCaptureKit.
- Records and transcribes microphone narration using Apple's on-device speech recognition when available.
- Learns mouse clicks, typed text, key presses, and app changes.
- Turns the demonstration into an editable, locally saved workflow.
- Replays the workflow under user supervision with the signature “Again, but…” interaction.
- Accepts instructions such as “Replace June with July” or “use amount $750.”
- Lets each change be used once, saved as a variant, or made the new default.
- Uses Apple's on-device Foundation Model on macOS 26, with local Qwen3-VL through Ollama and a narrow built-in planner as fallbacks.
- Pauses at spoken approval rules such as “always ask me before sending.”
- Keeps a local activity receipt showing what ran and what changed.
- Uses the Lagoon visual identity with persistent System, Light, and Dark appearance choices.

## Build and run

Requirements: macOS 15 or newer and the Apple Command Line Tools (full Xcode also works).

```sh
make setup-signing
make test
make agent-test
make app
open dist/Neloa.app
```

`make setup-signing` is a one-time development setup that creates a local signing identity in your login Keychain. The first signed build may ask for your Mac login password; choose **Always Allow** so later builds can sign without prompting. Keeping the same identity across builds lets macOS retain Neloa’s privacy permissions. `make test` runs deterministic workflow checks. `make agent-test` makes a real request to Apple's on-device model and verifies the resulting executable change plan.

The app asks for Screen Recording, Accessibility, Microphone, and Speech Recognition permissions. Accessibility lets Neloa learn clicks and typing during a demonstration and replay only the actions you approve. macOS may require reopening Neloa after it is granted.

## Install an unsigned preview

Unsigned universal ZIPs for Intel and Apple Silicon Macs are published on the GitHub Releases page. Because these previews are not notarized by Apple, macOS will block the first launch until you explicitly approve it:

1. Download the ZIP and move `Neloa.app` to Applications.
2. Try to open Neloa once, then dismiss the security warning.
3. Open **System Settings → Privacy & Security**.
4. Scroll to **Security**, choose **Open Anyway**, authenticate, and confirm **Open**.

Only use a download from the official Neloa repository. Each release includes a `.sha256` file so the download can be checked with `shasum -a 256 -c <checksum-file>`. macOS may ask for Neloa's recording and control permissions again after an update because these previews do not have a stable Apple-issued Developer ID.

Maintainers can reproduce the downloadable artifacts locally with:

```sh
make unsigned-release RELEASE_VERSION=0.2.17 BUILD_NUMBER=20
```

See the [distribution plan](docs/DISTRIBUTION.md) for the release workflow, limitations, and the future path to signed builds.

## Local models

On macOS 26 with Apple Intelligence enabled, Neloa uses Apple's on-device Foundation Model automatically. No model installation is needed.

For Macs where that model is unavailable, optionally install a Qwen fallback:

Install [Ollama](https://ollama.com), then run:

```sh
ollama pull qwen3-vl:4b
```

Neloa connects only to `http://127.0.0.1:11434`. The model name can be changed in Settings. Without Ollama, explicit date, amount, percentage, quoted-value, and “replace X with Y” variations continue to work locally.

## Privacy and safety

Workflow recordings and definitions are saved in the current user's Application Support directory. Neloa does not upload them. Run plans are previewed before execution, there is a three-second cancellation window, and approval steps pause execution.

Local builds use a dedicated development identity when one is installed. That identity is only for development; never distribute a build signed with it.

## Building on Neloa

Forks and derivative work are welcome under the Apache License 2.0. If you build something based on Neloa, please message the maintainer and tell us what you are making—we would genuinely like to hear about it and explore ways to work together. This is a friendly request, not a condition of the open-source license.

The Neloa name, logo, app icon, and visual identity are reserved for the official project. Derivative products should use their own name and branding unless written permission has been granted. See [TRADEMARKS.md](TRADEMARKS.md) for details.

## License

Neloa is licensed under the [Apache License 2.0](LICENSE). Distributed copies and derivative works must preserve the applicable license, copyright, and attribution notices described in [NOTICE](NOTICE).
