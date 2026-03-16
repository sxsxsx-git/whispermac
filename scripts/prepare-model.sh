#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME="${1:-large-v3-turbo}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_DIR="$ROOT/.build-tools/whisper.cpp"
MODELS_DIR="$ROOT/Models"
VENV_DIR="$ROOT/.build-tools/coreml-venv"

if [ -x /opt/homebrew/bin/python3.11 ]; then
  PYTHON_BIN=/opt/homebrew/bin/python3.11
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="$(command -v python3)"
else
  echo "python3 is required"
  exit 1
fi

if [ ! -d "$WHISPER_DIR" ]; then
  echo "whisper.cpp is missing. Run scripts/setup-whispercpp.sh first."
  exit 1
fi

mkdir -p "$MODELS_DIR"

pushd "$WHISPER_DIR" >/dev/null
./models/download-ggml-model.sh "$MODEL_NAME"
cp "./models/ggml-$MODEL_NAME.bin" "$MODELS_DIR/"
popd >/dev/null

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo
  echo "Full Xcode is not installed. The ggml model is ready, but Core ML / ANE conversion is skipped."
  echo "Install Xcode, then rerun this script to generate the encoder mlmodelc."
  exit 0
fi

rm -rf "$VENV_DIR"
"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip wheel
"$VENV_DIR/bin/pip" install --upgrade \
  "numpy<2" \
  "protobuf<=3.20.1" \
  "torch==2.5.0" \
  openai-whisper \
  coremltools
"$VENV_DIR/bin/pip" install --no-deps "ane_transformers==0.1.3"

pushd "$WHISPER_DIR" >/dev/null
PATH="$VENV_DIR/bin:$PATH" ./models/generate-coreml-model.sh "$MODEL_NAME"
popd >/dev/null

rsync -a "$WHISPER_DIR/models/ggml-$MODEL_NAME-encoder.mlmodelc" "$MODELS_DIR/"

echo
echo "Models are ready:"
echo "  $MODELS_DIR/ggml-$MODEL_NAME.bin"
echo "  $MODELS_DIR/ggml-$MODEL_NAME-encoder.mlmodelc"
