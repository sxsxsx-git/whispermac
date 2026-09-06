#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version-tag>" >&2
  exit 1
fi

VERSION_TAG="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_SRC="$DIST_DIR/WhisperMac.app"
ASSET_DIR="$DIST_DIR/release-assets"
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/whispermac-release-stage.XXXXXX")"
APP_STAGE="$STAGE_ROOT/WhisperMac.app"
ZIP_PATH="$ASSET_DIR/WhisperMac-${VERSION_TAG}-app-only-macos-arm64.zip"
SHA_PATH="$ASSET_DIR/WhisperMac-${VERSION_TAG}-app-only-macos-arm64.sha256"

cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

if [[ ! -d "$APP_SRC" ]]; then
  echo "App bundle not found: $APP_SRC" >&2
  echo "Run scripts/build-app-bundle.sh first." >&2
  exit 1
fi

rm -rf "$ASSET_DIR"
mkdir -p "$ASSET_DIR"

cp -R "$APP_SRC" "$APP_STAGE"
rm -rf "$APP_STAGE/Contents/Resources/runtime/Models"

# Stripping Resources/runtime/Models invalidates the resource seal of any
# signature applied earlier, so re-sign the staged app ad-hoc. The zip
# below then ships with a valid signature.
codesign --force --deep -s - "$APP_STAGE"
codesign --verify --deep --strict "$APP_STAGE"

ditto -c -k --sequesterRsrc --keepParent "$APP_STAGE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

# Prove the shipped artifact is signed: unzip and verify the extracted app.
ZIP_CHECK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/whispermac-zip-check.XXXXXX")"
unzip -q "$ZIP_PATH" -d "$ZIP_CHECK_DIR"
codesign --verify --deep --strict "$ZIP_CHECK_DIR/WhisperMac.app"
rm -rf "$ZIP_CHECK_DIR"
echo "Extracted app from zip passed codesign verification."

echo "Release assets created:"
echo "  $ZIP_PATH"
echo "  $SHA_PATH"
