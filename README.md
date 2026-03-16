# WhisperMac

> Free, local-first transcription for Apple Silicon, built to make practical
> use of Metal GPU and ANE acceleration.

WhisperMac is a local macOS transcription app for converting `mp4`, `m4a`, and
other common audio/video inputs into `txt` and `srt` using `whisper.cpp`.

The goal is to make it a free, easy-to-use, Apple Silicon-native alternative to
desktop transcription apps such as Buzz and MacWhisper, with a strong focus on
practical hardware acceleration.

It is designed for Apple Silicon and supports two acceleration modes:

- `GPU only`: Metal-only inference
- `GPU + ANE`: Metal for GPU work plus Core ML encoder offload when a compatible
  encoder model is available

## Features

- Free and open-source local transcription workflow
- Native macOS app built with SwiftUI
- Batch transcription for local media files
- `txt` and `srt` export
- Default model support for `large-v3-turbo`
- Real-time progress reporting
- Filtered runtime logs for user status and debugging
- Runtime acceleration mode switch between `GPU only` and `GPU + ANE`
- Built to take advantage of Metal GPU acceleration and Core ML / ANE offload

## Positioning

WhisperMac is intended to be:

- Free to use
- Easy to understand and easy to run locally
- Optimized for Apple Silicon hardware
- Transparent about its runtime pipeline and logs

Compared with closed-source desktop transcription tools, the project prioritizes
hackability, local-first operation, and explicit control over acceleration
behavior.

## How It Works

1. The app normalizes input media to `16 kHz`, mono, PCM WAV using macOS
   built-in `afconvert`.
2. It invokes `whisper.cpp` via `whisper-cli`.
3. On Apple Silicon:
   - `GPU only` uses the Metal backend.
   - `GPU + ANE` uses Metal plus the Core ML encoder when
     `ggml-large-v3-turbo-encoder.mlmodelc` is available.

Note: ANE does not run the entire pipeline. In the current `whisper.cpp`
architecture, Core ML typically accelerates the encoder, while decoding and
other parts still use GPU and CPU resources.

## Requirements

- macOS 14 or later
- Apple Silicon Mac
- Full Xcode installation
- `cmake`

Install the build dependency:

```bash
brew install cmake
```

## Quick Start

Prepare the runtime:

```bash
./scripts/setup-whispercpp.sh
./scripts/prepare-model.sh
```

Run the app in development:

```bash
swift run
```

Build the app bundle:

```bash
./scripts/build-app-bundle.sh
```

The generated app bundle is written to:

```text
./dist/WhisperMac.app
```

## Runtime Assets

Expected default runtime assets:

- `Models/ggml-large-v3-turbo.bin`
- `Models/ggml-large-v3-turbo-encoder.mlmodelc` (optional, for `GPU + ANE`)
- `.build-tools/whisper.cpp/build/bin/whisper-cli`

If these assets exist, the bundle script copies them into the app under
`Contents/Resources/runtime`.

## Repository Layout

- `Sources/whispermac`: app source code
- `Tests/whispermacTests`: test suite
- `scripts/setup-whispercpp.sh`: build `whisper.cpp`
- `scripts/prepare-model.sh`: download model assets and prepare Core ML encoder
- `scripts/build-app-bundle.sh`: package the macOS app bundle
- `scripts/benchmark-acceleration.sh`: compare `GPU only` vs `GPU + ANE`
- `.github/workflows/swift.yml`: basic GitHub Actions CI

## Project Status

Current scope:

- Local transcription to `txt` and `srt`
- Batch file processing
- Progress UI
- Runtime log filtering
- Acceleration mode selection
- Packaged `.app` output

Not yet implemented:

- Persistent job queue
- Timeline preview and editing
- Built-in model download UI
- Release signing and notarization

## Known Limitations

- This project currently targets Apple Silicon Macs and has not been tuned for
  Intel Macs.
- `GPU + ANE` acceleration depends on a compatible Core ML encoder model being
  present next to the selected `ggml` model.
- ANE does not accelerate the full transcription pipeline; decoding and parts
  of preprocessing still use CPU and GPU resources.
- The app currently focuses on batch transcription and export, not subtitle
  editing or post-processing.
- The packaged app is suitable for local use and open-source distribution, but
  it is not yet set up as a signed release artifact.

## Development

Build and test locally:

```bash
swift build
swift test
```

Contribution guidelines are in `CONTRIBUTING.md`.

## License

- Project license: `MIT`, see `LICENSE`
- Third-party notices: see `THIRD_PARTY_NOTICES.md`

WhisperMac does not bundle or distribute FFmpeg.
