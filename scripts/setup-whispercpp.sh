#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_DIR="$ROOT/.build-tools/whisper.cpp"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required"
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required. Install it with: brew install cmake"
  exit 1
fi

if [ ! -d "$WHISPER_DIR/.git" ]; then
  git clone https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
else
  git -C "$WHISPER_DIR" pull --ff-only
fi

cmake -S "$WHISPER_DIR" \
  -B "$WHISPER_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DWHISPER_COREML=ON \
  -DWHISPER_COREML_ALLOW_FALLBACK=ON

cmake --build "$WHISPER_DIR/build" --config Release -j

echo
echo "whisper.cpp is ready:"
echo "  $WHISPER_DIR/build/bin/whisper-cli"
