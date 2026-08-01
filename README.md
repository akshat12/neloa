# humana

Humana is a local-first Mac app for teaching agentic automations by demonstration. Record a workflow, explain the decisions out loud, review what Humana learned, and run it later with a one-time spoken or typed variation.

## What works

- Records the primary display and optional system audio using ScreenCaptureKit.
- Records and transcribes microphone narration using Apple's on-device speech recognition when available.
- Learns mouse clicks, typed text, key presses, and app changes.
- Turns the demonstration into an editable, locally saved workflow.
- Replays the workflow under user supervision.
- Accepts instructions such as “Replace June with July” or “use amount $750.”
- Uses a local Qwen3-VL model through Ollama when available, with a narrow built-in fallback.
- Pauses at spoken approval rules such as “always ask me before sending.”

## Build and run

Requirements: macOS 15 or newer and the Apple Command Line Tools (full Xcode also works).

```sh
make test
make app
open dist/Humana.app
```

The app asks for Screen Recording, Input Monitoring, Microphone, and Speech Recognition permissions. macOS may require reopening Humana after Input Monitoring is granted.

## Optional local model

Install [Ollama](https://ollama.com), then run:

```sh
ollama pull qwen3-vl:4b
```

Humana connects only to `http://127.0.0.1:11434`. The model name can be changed in Settings. Without Ollama, explicit date, amount, percentage, quoted-value, and “replace X with Y” variations continue to work locally.

## Privacy and safety

Workflow recordings and definitions are saved in the current user's Application Support directory. Humana does not upload them. Run plans are previewed before execution, there is a three-second cancellation window, and approval steps pause execution.

This repository currently uses ad-hoc signing for local development. Distribution will require an Apple Developer identity, hardened runtime, notarization, and a privacy review.
