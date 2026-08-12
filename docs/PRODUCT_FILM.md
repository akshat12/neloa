# Neloa product film

The product film at the top of the repository README is fully synthetic. It is drawn frame by frame from source code and does not contain a screen recording, a user account, or personal data.

## Published assets

| Asset | Purpose |
| --- | --- |
| `docs/media/neloa-preview.gif` | Inline, autoplaying README preview at 960 × 540. It shows the full story at 2× speed. |
| `docs/media/neloa-introduction.mp4` | Full 27-second H.264 film at 1280 × 720. The README preview links to it. |
| `docs/media/neloa-poster.png` | Static 1280 × 720 cover for releases, social posts, and places that do not animate GIFs. |

The film is intentionally silent so its complete message works on muted GitHub pages. Every important idea appears on screen.

## Storyboard

1. **Promise:** Show a task once, then say what changed.
2. **Teach:** Demonstrate an invented spreadsheet task while explaining the choices.
3. **Understand:** Turn low-level clicks and typing into meaningful workflow steps using local vision, actions, and voice.
4. **Adapt:** Ask for different values in natural language.
5. **Review:** Show exact before-and-after changes before anything runs.
6. **Invitation:** Automation for everyone—private, local, and open source.

The spreadsheet, values, narration, and interface shown in the film are fictional product-demo content.

## Regenerate and inspect

Run these commands from the repository root on macOS:

```sh
make product-video
make product-video-frames
```

The renderer in `scripts/render-product-video.swift` recreates all three published assets using AppKit, Core Graphics, AVFoundation, and the checked-in Neloa app icon. It does not require third-party software or network access.

The frame extractor in `scripts/extract-product-video-frames.swift` decodes representative frames into `.build/product-video-frames` for visual review. That directory is ignored by Git.

After changing the film, inspect all extracted frames, open the MP4 from beginning to end, and confirm that the GIF remains small enough to load comfortably on the repository page.
