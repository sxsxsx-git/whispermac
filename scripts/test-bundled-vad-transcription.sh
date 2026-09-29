#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 WhisperMac.app whisper-model.bin input-audio vad-model.bin" >&2
  exit 2
fi

SOURCE_APP="$1"
WHISPER_MODEL="$2"
INPUT_AUDIO="$3"
VAD_MODEL="$4"

for path in "$SOURCE_APP" "$WHISPER_MODEL" "$INPUT_AUDIO" "$VAD_MODEL"; do
  if [[ ! -e "$path" ]]; then
    echo "Required path does not exist: $path" >&2
    exit 2
  fi
done

WORK_DIR="$(mktemp -d "${WHISPERMAC_SMOKE_TMPDIR:-${TMPDIR:-/tmp}}/whispermac-bundled-vad.XXXXXX")"
APP_COPY="$WORK_DIR/WhisperMac.app"
CLI="$APP_COPY/Contents/Resources/runtime/bin/whisper-cli"
RESULTS="$WORK_DIR/results"
mkdir -p "$RESULTS"
ditto "$SOURCE_APP" "$APP_COPY"

if [[ ! -x "$CLI" ]]; then
  echo "App bundle does not contain an executable whisper-cli: $CLI" >&2
  exit 1
fi

BUNDLED_MODEL="$APP_COPY/Contents/Resources/runtime/Models/$(basename "$WHISPER_MODEL")"
if [[ ! -s "$BUNDLED_MODEL" ]]; then
  echo "App bundle does not contain the requested Whisper model: $BUNDLED_MODEL" >&2
  exit 1
fi
WHISPER_MODEL="$BUNDLED_MODEL"

run_transcription() {
  local name="$1"
  shift
  "$CLI" -m "$WHISPER_MODEL" -f "$INPUT_AUDIO" \
    -of "$RESULTS/$name" -otxt -osrt -t "${WHISPERMAC_SMOKE_THREADS:-4}" "$@" \
    >"$RESULTS/$name.log" 2>&1
  test -s "$RESULTS/$name.txt"
  test -s "$RESULTS/$name.srt"
  grep -Eq "Core ML model loaded" "$RESULTS/$name.log"
}

run_transcription vad-off -l "${WHISPERMAC_SMOKE_LANGUAGE:-zh}"
run_transcription vad-on -l "${WHISPERMAC_SMOKE_LANGUAGE:-zh}" \
  --vad -vm "$VAD_MODEL" -vt 0.5 -vspd 250 -vsd 500 -vp 200

grep -Eq "VAD version|model version|VAD model" "$RESULTS/vad-on.log"
echo "Relocated bundled CLI completed VAD-off/on TXT+SRT transcriptions."
echo "Logs and outputs: $RESULTS"
