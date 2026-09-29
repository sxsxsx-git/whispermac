# FAQ

## Is WhisperMac free?

Yes. The repository is open source and licensed under `MIT`.

## Does WhisperMac send audio to a server?

No. The app is designed for local-first transcription and runs `whisper.cpp`
locally on your Mac.

## Which Macs are supported?

The current target is Apple Silicon on `macOS 14+`. Intel Macs are not the
focus of this project.

## Does ANE accelerate the entire pipeline?

No. In the current `whisper.cpp` architecture, the Core ML path typically
accelerates the encoder. Decoding and other stages still use GPU and CPU
resources.

## Do I need FFmpeg?

No. WhisperMac uses macOS built-in `afconvert` for audio preprocessing.

## Does the app download models?

Yes. The app can download the default Whisper model and Core ML encoder. The
optional Silero VAD model has its own download action and does not trigger a
Whisper model or encoder download. You can also select local model files in
Settings.

## What does Silero VAD do?

It detects speech regions before Whisper transcribes them, which can save work
on audio with long silences. It is disabled by default. Its defaults are
threshold `0.50`, minimum speech `250 ms`, minimum silence `500 ms`, and
padding `200 ms`. Since detection can miss quiet speech or singing, compare
with VAD off when completeness is important. VAD does not separate vocals from
music, create semantic sentence breaks, or correct subtitles with an LLM.

VAD runs on the CPU; this does not prevent Whisper from using Metal or its
optional Core ML encoder. The run log reports the effective acceleration mode.

## Do release downloads include the model files?

No in the current packaging flow. The release asset is app-only and strips the
`Models/` directory from the archive.

## What output formats are supported?

`txt`, `srt`, `vtt`, and `json`.

## What is the difference between `GPU only` and `GPU + ANE`?

- `GPU only` keeps the runtime on the Metal path and explicitly avoids the Core
  ML encoder when one is present.
- `GPU + ANE` uses the Core ML encoder when a compatible encoder model is
  available, otherwise it falls back to `GPU only`.

## Do I need full Xcode?

You need full Xcode if you are building the project locally and especially if
you want to generate the optional Core ML encoder with
`scripts/prepare-model.sh`. You do not need Xcode just to run a prebuilt app
bundle.

## Can I use a model other than `large-v3-turbo`?

You can manually point the app at another compatible `whisper.cpp` model file,
but this repository's default setup, docs, and Core ML preparation flow are
centered on `large-v3-turbo`.

## Is WhisperMac signed and notarized?

Not yet. That is one of the current limitations called out in the repository.
