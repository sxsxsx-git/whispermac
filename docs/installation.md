# Installation Guide

This guide is for people who want to try WhisperMac as quickly as possible
without guessing which pieces are bundled and which are not.

## Before You Start

- Supported platform: `macOS 14+` on Apple Silicon
- The app expects a `whisper.cpp` model file such as
  `ggml-large-v3-turbo.bin`
- `GPU + ANE` also needs a matching Core ML encoder directory:
  `ggml-large-v3-turbo-encoder.mlmodelc`
- Current release packaging is `app-only`: the archive keeps the app and
  bundled `whisper-cli`, but does not include model files
- Current releases are ad-hoc signed but not Developer-ID-signed or
  notarized

## Option 1: Use a Published Release

Use this path if the repository owner has published a GitHub Release.

1. Download the latest `WhisperMac-<tag>-app-only-macos-arm64.zip` from the
   [Releases page](https://github.com/sxsxsx-git/whispermac/releases).
2. Unzip it and move `WhisperMac.app` wherever you want to keep it.
3. If macOS says the app is damaged or from an unidentified developer,
   either right-click the app and choose `Open`, or run:

```bash
xattr -cr /path/to/WhisperMac.app
```
4. Prepare or obtain `ggml-large-v3-turbo.bin`.
5. If you want `GPU + ANE`, also prepare
   `ggml-large-v3-turbo-encoder.mlmodelc` next to that model file.
6. Open WhisperMac.
7. Confirm the `whisper-cli` path points to the bundled runtime.
8. Use `Model File` to choose your local `ggml-large-v3-turbo.bin`.
9. Add media files, choose output formats, and start transcribing.

Notes:

- The release archive is designed to avoid shipping large model files.
- If you only provide the `.bin` model, the app can still run in `GPU only`
  mode.
- If `GPU + ANE` is selected without a matching Core ML encoder, the app will
  fall back to `GPU only`.

## Option 2: Build from Source

Use this path if no release is available yet, or if you want the repo-managed
runtime setup.

1. Install Xcode 16+ and select it:

```bash
xcode-select -s /Applications/Xcode.app
```

2. Install build dependencies:

```bash
brew install cmake python@3.11
```

3. Build `whisper.cpp` locally:

```bash
./scripts/setup-whispercpp.sh
```

4. Download the default model and build the optional Core ML encoder:

```bash
./scripts/prepare-model.sh
```

5. Build the macOS app bundle:

```bash
./scripts/build-app-bundle.sh
```

6. Open the generated app:

```bash
open ./dist/WhisperMac.app
```

## First Transcription Checklist

1. Click `Add MP4 / M4A` and choose one or more local files.
2. Leave `Output Directory` empty to save next to each input file, or choose a
   custom output folder.
3. Keep `TXT` and `SRT` enabled if you want both exports.
4. Choose `GPU only` or `GPU + ANE`.
5. Click `Start Transcription`.

## Files WhisperMac Looks For

The default runtime layout is:

```text
runtime/
  bin/whisper-cli
  Models/ggml-large-v3-turbo.bin
  Models/ggml-large-v3-turbo-encoder.mlmodelc
```

WhisperMac can also point to model files outside the app bundle, which is why
the release archive works even when models are not packaged inside the app.
