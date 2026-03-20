# Positioning and Comparison

WhisperMac sits between a raw `whisper.cpp` CLI workflow and a polished
desktop transcription product.

Its goal is not to win by making bigger claims. Its goal is to be a practical,
free, Apple Silicon-native app with explicit runtime behavior.

## What WhisperMac Is

- A local-first macOS app for transcription
- Built specifically around Apple Silicon and `whisper.cpp`
- Focused on simple transcription and export
- Transparent about acceleration modes, logs, and current limitations

## What WhisperMac Is Not

- Not a full subtitle editor
- Not a cloud transcription service
- Not a signed, fully turnkey consumer app yet
- Not a broad benchmark showcase with sweeping performance claims

## Best Fit

WhisperMac is a good fit if you want:

- A free and open-source desktop app instead of a closed workflow
- Apple Silicon-aware acceleration choices
- A UI that is easier than managing the full CLI yourself
- Local processing with visible runtime paths and logs
- Simple transcript export to `txt` and `srt`

## Probably Not the Best Fit

Another tool may fit better if you want:

- A notarized drag-and-drop install with minimal setup
- Built-in model download and update management
- Subtitle editing, timeline work, or post-production tooling
- A broader cross-platform story

## Comparison by Product Shape

| Dimension | WhisperMac | Raw `whisper.cpp` CLI | More polished desktop transcription app |
| --- | --- | --- | --- |
| Local processing | Yes | Yes | Varies |
| Native macOS app UI | Yes | No | Usually yes |
| Apple Silicon tuning called out explicitly | Yes | Manual | Varies |
| Runtime transparency | High | Highest | Varies |
| Batch local files | Yes | Yes | Usually yes |
| Built-in model download | No | No | Varies |
| Subtitle editing focus | No | No | Often stronger |
| Signed / notarized distribution | Not yet | N/A | Often yes |

## Short Positioning Statement

WhisperMac is a free, local-first transcription app for Apple Silicon users who
want a native macOS workflow, practical exports, and clearer control over
Metal GPU vs `GPU + ANE` behavior than a generic desktop wrapper usually shows.
