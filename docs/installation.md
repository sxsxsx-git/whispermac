# Installation Guide

This guide is for people who want to try WhisperMac as quickly as possible
without guessing which pieces are bundled and which are not.

## Before You Start

- Supported platform: `macOS 14+` on Apple Silicon
- The app expects a `whisper.cpp` model file such as
  `ggml-large-v3-turbo.bin`
- Silero VAD is optional and disabled by default. Enabling it requires
  `ggml-silero-v6.2.0.bin`.
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
9. Add media files or drag a folder into the workspace; folders are scanned
   recursively for supported media. Choose output formats and start transcribing.

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
  Models/ggml-silero-v6.2.0.bin (optional)
```

WhisperMac can also point to model files outside the app bundle, which is why
the release archive works even when models are not packaged inside the app.

## Media Folder Drop

Drop one or more media files, folders, or a mixture onto the workspace. Each
folder is scanned recursively and supported files are added to the queue in a
stable path order. Hidden items, package contents, and symlink directories are
skipped. The scanner runs in the background, so large folders do not block the
interface. Existing queue entries and duplicate paths are ignored.

## Silero VAD

VAD is off by default so existing installations keep their previous
transcription behavior. In the workspace, turn on **Voice Activity Detection**
to see whether the model is available. Use **Download Silero VAD** to fetch it
from the [`ggml-org/whisper-vad` Hugging Face repository](https://huggingface.co/ggml-org/whisper-vad).
The app checks the download size and, when repository metadata is available,
verifies its SHA-256. It only downloads this small VAD model; it does not
replace the Whisper model or Core ML encoder.

The default model location is:

```text
~/Library/Application Support/WhisperMac/runtime/Models/ggml-silero-v6.2.0.bin
```

With the VAD model path left on automatic detection, Settings displays the
resolved file path without changing the saved preference. Use **Choose…** to
select a model manually, or **Restore automatic detection** to return to the
default/bundled model search.

### Hugging Face download sources

In **Settings → Model Downloads**, select **Official Hugging Face** (the
default), **HF-Mirror**, or **Custom** and enter an HTTP/HTTPS base URL. This
single endpoint is used for Whisper model files, Core ML encoder archives,
Silero VAD, and repository checksum metadata. A custom URL must include a host;
invalid URLs disable downloads instead of silently falling back to the official
host. Existing installations that stored the legacy `hfEndpoint` setting are
migrated automatically. The environment variable
`WHISPERMAC_HF_ENDPOINT` overrides the UI selection for all of these downloads.

You can select a model at another path in **Settings → Transcription Paths →
VAD Model**, or download it manually:

```bash
mkdir -p "$HOME/Library/Application Support/WhisperMac/runtime/Models"
curl -L \
  "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v6.2.0.bin?download=true" \
  -o "$HOME/Library/Application Support/WhisperMac/runtime/Models/ggml-silero-v6.2.0.bin"
```

Default VAD parameters are threshold `0.50`, minimum speech duration `250 ms`,
minimum silence duration `500 ms`, and speech padding `200 ms`. The threshold
controls how confidently a frame must be classified as speech. The advanced
settings let you tune duration filters and padding around detected regions.

VAD runs on the CPU. Whisper's Metal GPU mode and optional Core ML encoder still
run independently; the task log reports their actual initialization and the
effective acceleration mode. A VAD detection miss can omit quiet speech or
singing, so compare the result with VAD off when completeness matters. VAD does
not separate vocals from music, find semantic sentence boundaries, or perform
LLM subtitle correction.

### Minimal CLI example

The CLI accepts WAV input. This example assumes a 16 kHz mono WAV and the
WhisperMac runtime paths above:

```bash
WHISPER_CLI="$HOME/Library/Application Support/WhisperMac/custom-runtime/bin/whisper-cli"
WHISPER_MODEL="$HOME/Library/Application Support/WhisperMac/runtime/Models/ggml-large-v3-turbo.bin"
VAD_MODEL="$HOME/Library/Application Support/WhisperMac/runtime/Models/ggml-silero-v6.2.0.bin"

"$WHISPER_CLI" \
  -m "$WHISPER_MODEL" \
  -f input.wav \
  -of output \
  -l zh \
  -otxt -osrt \
  --vad -vm "$VAD_MODEL" \
  -vt 0.50 -vspd 250 -vsd 500 -vp 200
```

To run from source, prepare the pinned runtime with
`./scripts/setup-whispercpp.sh`, launch the GUI with `swift run`, or create
`dist/WhisperMac.app` with `./scripts/build-app-bundle.sh`. The bundle script
copies and rewrites the CLI's dylib paths, signs nested code, then copies the
app to a temporary location and runs its CLI help as a relocation check.
