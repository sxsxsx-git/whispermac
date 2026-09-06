#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_DIR="$ROOT/.build-tools/whisper.cpp"

# Pin whisper.cpp to a fixed upstream tag so releases stay reproducible.
# Override with WHISPERCPP_VERSION=<tag> to build a different version.
WHISPERCPP_VERSION="${WHISPERCPP_VERSION:-v1.9.3}"

if ! command -v git >/dev/null 2>&1; then
  echo "git is required"
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required. Install it with: brew install cmake"
  exit 1
fi

if [ ! -d "$WHISPER_DIR/.git" ]; then
  git clone --depth 1 --branch "$WHISPERCPP_VERSION" \
    https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
else
  # Fetch the pinned tag and force-checkout so switching versions is
  # deterministic (a plain pull would follow the upstream default branch).
  git -C "$WHISPER_DIR" fetch --depth 1 origin "$WHISPERCPP_VERSION"
  git -C "$WHISPER_DIR" checkout --force FETCH_HEAD
fi

cmake -S "$WHISPER_DIR" \
  -B "$WHISPER_DIR/build" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DWHISPER_COREML=ON \
  -DWHISPER_COREML_ALLOW_FALLBACK=ON

cmake --build "$WHISPER_DIR/build" --config Release -j

echo
echo "whisper.cpp is ready (pinned at $WHISPERCPP_VERSION):"
echo "  $WHISPER_DIR/build/bin/whisper-cli"
