# WhisperMac

Free, local-first transcription for Apple Silicon Macs. WhisperMac turns local
audio and video into `txt` and `srt` with `whisper.cpp`, Metal GPU
acceleration, and optional Core ML / ANE encoder offload.

If this repo helps you, please star it. That is the clearest signal that the
project is useful and worth continuing.

## Why WhisperMac

- Free and open source
- Local-first: your media stays on your Mac
- Built for Apple Silicon instead of treating it as an afterthought
- Native macOS app, not just a terminal wrapper
- `txt` and `srt` export for practical transcript workflows
- Clear GPU-only vs `GPU + ANE` runtime behavior
- Honest about what is accelerated and what is not

## Quick Start for Users

1. Read the [Installation Guide](docs/installation.md).
2. If a release asset exists, download the latest app-only arm64 zip. If not,
   build from source.
3. Make sure you have `ggml-large-v3-turbo.bin`. Add
   `ggml-large-v3-turbo-encoder.mlmodelc` only if you want `GPU + ANE` mode.
4. Open WhisperMac, add your media files, pick output formats, and start
   transcribing.

Important notes before you try it:

- The project currently targets `macOS 14+` on Apple Silicon.
- Release packaging is currently `app-only`: models are not bundled.
- Signed and notarized releases are not set up yet.

## Features

- Free, open-source local transcription workflow
- Native SwiftUI macOS app
- Batch transcription for common local media files
- `txt` and `srt` export
- Default workflow centered on `large-v3-turbo`
- Real-time progress reporting
- Filtered logs for both user status and debugging
- Runtime acceleration switch between `GPU only` and `GPU + ANE`
- Uses macOS built-in `afconvert` for audio preprocessing, so FFmpeg is not
  required
- Localized UI in English, Simplified Chinese, and Japanese

## Performance Snapshot

On a single `47m 09s` sample file, using the same preprocessed WAV input and a
`120s` cooldown between runs on a passively cooled Apple Silicon MacBook Air,
the measured results were:

- `GPU + ANE`: `177.62s`
- `GPU only`: `205.22s`

In that specific run, `GPU + ANE` was about `15.5%` faster than `GPU only`.

This is not a universal benchmark. Actual speed depends on model choice, media
content, thermals, and current `whisper.cpp` behavior.

## How It Works

1. WhisperMac converts input media to `16 kHz`, mono, PCM WAV with macOS
   `afconvert`.
2. It runs `whisper.cpp` through `whisper-cli`.
3. On Apple Silicon:
   - `GPU only` uses the Metal backend.
   - `GPU + ANE` uses Metal plus a Core ML encoder when a compatible
     `ggml-large-v3-turbo-encoder.mlmodelc` is available.

Important limitation:

- ANE does not accelerate the full transcription pipeline in the current
  `whisper.cpp` architecture. The Core ML path typically accelerates the
  encoder, while decoding and other work still use GPU and CPU resources.

## Docs

- [Installation Guide](docs/installation.md)
- [FAQ](docs/faq.md)
- [Positioning and Comparison](docs/positioning.md)
- [Promotion Pack](docs/promotion-pack.md)
- [Contributing](CONTRIBUTING.md)

## Developer Setup

Install the local build dependencies:

```bash
xcode-select -s /Applications/Xcode.app
brew install cmake python@3.11
```

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

## Known Limitations

- Apple Silicon only. Intel Macs are not a current target.
- Built-in model download is not implemented yet.
- `GPU + ANE` depends on a compatible Core ML encoder being present next to the
  selected `ggml` model.
- ANE does not accelerate the full transcription pipeline.
- The app focuses on transcription and export, not subtitle editing.
- Release artifacts are not yet signed or notarized.
- The current release packaging flow creates an app-only zip and strips bundled
  models from the archive.

## Contributing and License

Build and test locally:

```bash
swift build
swift test
```

Contribution guidelines are in [CONTRIBUTING.md](CONTRIBUTING.md).

License and notices:

- Project license: `MIT`, see [LICENSE](LICENSE)
- Third-party notices: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)

WhisperMac does not bundle or distribute FFmpeg.
