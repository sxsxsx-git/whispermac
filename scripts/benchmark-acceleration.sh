#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "Usage: $0 <input-media-path> [cooldown-seconds] [measured-rounds]" >&2
  exit 1
fi

INPUT_PATH="$1"
COOLDOWN_SECONDS="${2:-120}"
MEASURED_ROUNDS="${3:-2}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_RUNTIME="$ROOT/dist/WhisperMac.app/Contents/Resources/runtime"
CLI_PATH="$APP_RUNTIME/bin/whisper-cli"
MODEL_PATH="$APP_RUNTIME/Models/ggml-large-v3-turbo.bin"

if [[ ! -f "$INPUT_PATH" ]]; then
  echo "Input file not found: $INPUT_PATH" >&2
  exit 1
fi

if [[ ! -x "$CLI_PATH" ]]; then
  echo "whisper-cli not found: $CLI_PATH" >&2
  exit 1
fi

if [[ ! -f "$MODEL_PATH" ]]; then
  echo "Model file not found: $MODEL_PATH" >&2
  exit 1
fi

BENCH_DIR="$(mktemp -d /tmp/whispermac-bench.XXXXXX)"
WAV_PATH="$BENCH_DIR/input.wav"
OUTPUT_DIR="$BENCH_DIR/out"
GPU_ONLY_MODEL_PATH="$BENCH_DIR/ggml-large-v3-turbo-gpu-only.bin"

mkdir -p "$OUTPUT_DIR"
ln -sf "$MODEL_PATH" "$GPU_ONLY_MODEL_PATH"

extract_audio() {
  local log_path="$BENCH_DIR/audio-prep.stderr.log"

  echo "=== PREPARE_AUDIO start=$(date '+%F %T') ==="
  /usr/bin/time -p afconvert \
    -f WAVE \
    -d LEI16@16000 \
    -c 1 \
    "$INPUT_PATH" \
    "$WAV_PATH" \
    > /dev/null \
    2> "$log_path"

  echo "AUDIO_WAV=$WAV_PATH"
  echo "AUDIO_LOG=$log_path"
  awk '/^real / || /^user / || /^sys / { print "AUDIO_" toupper($1) "=" $2 }' "$log_path"
}

run_one() {
  local mode="$1"
  local run_id="$2"
  local model_path="$3"
  local prefix="$OUTPUT_DIR/${mode}-${run_id}"
  local log_path="$OUTPUT_DIR/${mode}-${run_id}.stderr.log"

  rm -f "${prefix}.txt" "$log_path"

  echo "=== RUN_START mode=${mode} run=${run_id} at=$(date '+%F %T') ==="
  /usr/bin/time -p "$CLI_PATH" \
    -m "$model_path" \
    -f "$WAV_PATH" \
    -l auto \
    -otxt \
    -of "$prefix" \
    -pp \
    > /dev/null \
    2> "$log_path"

  local exit_code=$?
  local real_time
  local user_time
  local sys_time

  real_time="$(awk '/^real / { print $2 }' "$log_path" | tail -n 1)"
  user_time="$(awk '/^user / { print $2 }' "$log_path" | tail -n 1)"
  sys_time="$(awk '/^sys / { print $2 }' "$log_path" | tail -n 1)"

  echo "--- KEY_LOG mode=${mode} run=${run_id} ---"
  grep -E "loading Core ML model|failed to load Core ML model|using MTL0 backend|progress = 100%|model size|total size" "$log_path" | tail -n 12 || true
  echo "RESULT mode=${mode} run=${run_id} exit=${exit_code} real=${real_time} user=${user_time} sys=${sys_time} log=${log_path}"
}

cooldown() {
  local seconds="$1"
  echo "=== COOLDOWN seconds=${seconds} at=$(date '+%F %T') ==="
  sleep "$seconds"
}

extract_audio

run_one "ane" "warmup" "$MODEL_PATH"
cooldown "$COOLDOWN_SECONDS"
run_one "gpu" "warmup" "$GPU_ONLY_MODEL_PATH"

for round in $(seq 1 "$MEASURED_ROUNDS"); do
  cooldown "$COOLDOWN_SECONDS"
  run_one "ane" "measure${round}" "$MODEL_PATH"
  cooldown "$COOLDOWN_SECONDS"
  run_one "gpu" "measure${round}" "$GPU_ONLY_MODEL_PATH"
done

echo "=== BENCHMARK_DIR $BENCH_DIR ==="
