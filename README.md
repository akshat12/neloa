# humana

Humana is a private, voice-first Mac app for automating work that changes a little every time. Show a workflow once, explain the decisions out loud, then run it later by saying only what is different.

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

## Build and run

Requirements: macOS 15 or newer and the Apple Command Line Tools (full Xcode also works).

```sh
make test
make agent-test
make app
open dist/Humana.app
```

`make test` runs deterministic workflow checks. `make agent-test` makes a real request to Apple's on-device model and verifies the resulting executable change plan.

The app asks for Screen Recording, Input Monitoring, Accessibility, Microphone, and Speech Recognition permissions. macOS may require reopening Humana after Input Monitoring or Accessibility is granted.

## Local models

On macOS 26 with Apple Intelligence enabled, Humana uses Apple's on-device Foundation Model automatically. No model installation is needed.

For Macs where that model is unavailable, optionally install a Qwen fallback:

Install [Ollama](https://ollama.com), then run:

```sh
ollama pull qwen3-vl:4b
```

Humana connects only to `http://127.0.0.1:11434`. The model name can be changed in Settings. Without Ollama, explicit date, amount, percentage, quoted-value, and “replace X with Y” variations continue to work locally.

## Privacy and safety

Workflow recordings and definitions are saved in the current user's Application Support directory. Humana does not upload them. Run plans are previewed before execution, there is a three-second cancellation window, and approval steps pause execution.

This repository currently uses ad-hoc signing for local development. Distribution will require an Apple Developer identity, hardened runtime, notarization, and a privacy review.
