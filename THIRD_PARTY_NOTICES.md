# Third-Party Notices

WhisperMac ships with or depends on the following third-party components.

## whisper.cpp

- Project: `ggml-org/whisper.cpp`
- Upstream license: MIT
- Upstream source: <https://github.com/ggml-org/whisper.cpp>

WhisperMac bundles a locally built `whisper-cli` binary from `whisper.cpp`.

## OpenAI Whisper model assets

- Project: `openai/whisper`
- Upstream license: MIT
- Upstream source: <https://github.com/openai/whisper>

WhisperMac expects the `large-v3-turbo` model assets generated from the
OpenAI Whisper release ecosystem and may optionally bundle a Core ML encoder
compiled from those assets for local inference.

## Silero VAD model

- Converted model: `ggml-silero-v6.2.0.bin`
- Model repository: [`ggml-org/whisper-vad`](https://huggingface.co/ggml-org/whisper-vad)
- Original project: [`snakers4/silero-vad`](https://github.com/snakers4/silero-vad)
- License: MIT (as identified by the model repository and the Silero VAD source repository)

WhisperMac downloads this model on request; it is not bundled in the app-only
release archive. The model is converted to ggml format for use by `whisper.cpp`.

## macOS system audio conversion

WhisperMac uses the macOS built-in `afconvert` tool for audio extraction and
normalization. `afconvert` is provided by Apple as part of macOS and is not
bundled separately by this repository.

## FFmpeg

WhisperMac does not bundle or distribute FFmpeg. Older development notes or
local developer workflows may still mention FFmpeg, but it is not required for
the application runtime or app bundle produced by this repository.
