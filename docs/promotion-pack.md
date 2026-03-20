# Promotion Pack

This file is for the repository owner. Everything below is written to stay
inside the project's current, verifiable scope.

## One-Line Positioning

Free, local-first transcription for Apple Silicon Macs with `whisper.cpp`,
Metal GPU acceleration, and optional Core ML / ANE encoder offload.

## Short Repo Description Options

1. Free local-first transcription app for Apple Silicon. `whisper.cpp` + Metal
   GPU + optional Core ML / ANE encoder.
2. Native macOS transcription app for Apple Silicon with local processing,
   `txt` / `srt` export, and explicit GPU vs `GPU + ANE` runtime modes.
3. Open-source Apple Silicon transcription app built around `whisper.cpp` and
   practical Metal acceleration.

## Suggested GitHub Topics

`macos`, `apple-silicon`, `swiftui`, `swift`, `whisper`, `whisper-cpp`,
`transcription`, `speech-to-text`, `metal`, `coreml`, `ane`

## README / Social Short Copy

### Option 1

WhisperMac is a free, local-first transcription app for Apple Silicon Macs.
It uses `whisper.cpp`, exports `txt` and `srt`, and lets you switch between
`GPU only` and `GPU + ANE` modes without hiding how the runtime works.

### Option 2

Built WhisperMac to make local transcription on Apple Silicon feel like a real
Mac app instead of a pile of scripts. It is free, open source, and honest about
what Metal GPU and ANE are actually accelerating.

### Option 3

If you want a native macOS wrapper around `whisper.cpp` that stays local,
exports `txt` / `srt`, and is explicit about Apple Silicon acceleration modes,
WhisperMac is the current direction.

## Launch Post Drafts

### X / Short Post

Shipping WhisperMac: a free, local-first transcription app for Apple Silicon.
Native macOS UI, `whisper.cpp`, `txt` / `srt` export, Metal GPU acceleration,
and optional Core ML / ANE encoder offload. Repo:
https://github.com/sxsxsx-git/whispermac

### Developer Audience

Built an open-source macOS transcription app around `whisper.cpp` for Apple
Silicon. The focus is practical local use, clear runtime behavior, and honest
GPU vs `GPU + ANE` handling instead of vague performance claims. Repo:
https://github.com/sxsxsx-git/whispermac

### User Audience

If you want local transcription on an Apple Silicon Mac without sending files
to a server, WhisperMac is an open-source option. It exports `txt` / `srt` and
keeps the acceleration story explicit. Repo:
https://github.com/sxsxsx-git/whispermac

## Release Title Template

`WhisperMac vX.Y.Z: local-first transcription for Apple Silicon`

## Release Notes Template

```md
## WhisperMac vX.Y.Z

WhisperMac is a free, local-first transcription app for Apple Silicon Macs.
It uses `whisper.cpp`, exports `txt` / `srt`, and supports both `GPU only` and
`GPU + ANE` runtime modes.

What to know in this release:

- Native macOS app bundle
- Local transcription workflow
- `txt` and `srt` export
- Honest `GPU only` vs `GPU + ANE` behavior

Current limitations:

- Apple Silicon only
- Release asset is app-only and does not bundle models
- Signed / notarized distribution is not set up yet
- ANE does not accelerate the full pipeline
```

## Suggested Asset Checklist

- TODO: one clean app screenshot showing the main window
- TODO: one short transcription demo GIF
- TODO: one screenshot of generated `txt` and `srt` outputs
- TODO: release page cover image sized for social previews

## Commands for a Release Pass

Build the app bundle:

```bash
./scripts/build-app-bundle.sh
```

Create the app-only release assets for a tag:

```bash
./scripts/create-release-assets.sh vX.Y.Z
```

If you are using GitHub CLI, the uploaded files are the generated zip and
sha256 file under `dist/release-assets/`.
