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
STAGE_DIR="$ASSET_DIR/stage"
APP_STAGE="$STAGE_DIR/WhisperMac.app"
ZIP_PATH="$ASSET_DIR/WhisperMac-${VERSION_TAG}-app-only-macos-arm64.zip"
SHA_PATH="$ASSET_DIR/WhisperMac-${VERSION_TAG}-app-only-macos-arm64.sha256"

if [[ ! -d "$APP_SRC" ]]; then
  echo "App bundle not found: $APP_SRC" >&2
  echo "Run scripts/build-app-bundle.sh first." >&2
  exit 1
fi

rm -rf "$ASSET_DIR"
mkdir -p "$STAGE_DIR"

cp -R "$APP_SRC" "$APP_STAGE"
rm -rf "$APP_STAGE/Contents/Resources/runtime/Models"

ditto -c -k --sequesterRsrc --keepParent "$APP_STAGE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH" > "$SHA_PATH"

echo "Release assets created:"
echo "  $ZIP_PATH"
echo "  $SHA_PATH"
