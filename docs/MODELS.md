# Local model strategy

Neloa ships one visual model family so setup stays understandable and the app does not accumulate several large downloads. Both tiers use Qwen3-VL 4B Instruct and the same local MLX Swift runtime.

| Tier | Download | Recommended Mac | Purpose |
| --- | ---: | --- | --- |
| Balanced · 4-bit | about 3.1 GB | Apple silicon with 16 GB or more | Default. Faster, lighter, and sufficient for most recordings. |
| Higher precision · 8-bit | about 5.1 GB | Apple silicon with 24 GB or more | Optional. Preserves more numerical detail for ambiguous interfaces and small text. |

The 8-bit tier remains available on a 16 GB Mac, but Neloa labels 24 GB or more as the recommendation. A local end-to-end run peaked at about 6.2 GB of memory footprint for 8-bit, compared with about 4.1 GB for 4-bit. These figures cover model inference, not the whole operating system, the recorded app, and a long ScreenCaptureKit session.

Quantization affects how compactly the model's learned numbers are stored. It does not change the model's architecture or make 8-bit a new model. Eight-bit can retain subtle visual distinctions that 4-bit rounds away, but it is not guaranteed to produce a better answer on every frame. Neloa therefore keeps OCR, coordinate normalization, focused crops, consensus checks, and deterministic captured actions in both tiers.

## Why Qwen3-VL remains the default

[Qwen3-VL 4B Instruct](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct) combines screenshot understanding, interface grounding, video understanding, OCR, narration, and structured reasoning in one Apache-2.0 model. Its 4B size has practical MLX quantizations for a 16 GB Apple silicon Mac. That lets one model label actions, interpret spoken guidance, summarize a workflow, and plan a customized run without a local server.

Neloa pins the exact revision for each tier:

- [Qwen3-VL 4B Instruct MLX 4-bit](https://huggingface.co/lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit)
- [Qwen3-VL 4B Instruct MLX 8-bit](https://huggingface.co/lmstudio-community/Qwen3-VL-4B-Instruct-MLX-8bit)

## Alternatives worth benchmarking

These are research candidates, not additional downloads Neloa currently exposes:

- [UI-TARS 1.5 7B](https://huggingface.co/ByteDance-Seed/UI-TARS-1.5-7B) is the strongest next benchmark for precise GUI grounding and computer-use actions. It is larger and still needs a verified MLX Swift conversion and memory evaluation before it could be a good Mac default.
- [ShowUI 2B](https://huggingface.co/showlab/ShowUI-2B) is a smaller GUI specialist and could become a fast grounding helper. It is less suitable as Neloa's only model because workflow narration, rule extraction, and run planning require broader reasoning.
- [Fara 7B](https://huggingface.co/microsoft/Fara-7B) is specialized for web computer use. Its official local path targets PyTorch/vLLM and high-end NVIDIA hardware, so it is not currently a seamless native Mac choice.
- [MAI-UI](https://github.com/Tongyi-MAI/MAI-UI) is promising but more mobile-oriented; available 8B community MLX builds are too large to improve the 16 GB default experience.

The product rule is deliberately conservative: do not add a second shipped model unless it materially improves Neloa's own timeline-grounding and replay benchmark, runs reliably through the native Swift stack, and justifies the extra download and user-facing choice.
