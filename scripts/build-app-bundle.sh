#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/WhisperMac.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RUNTIME_DIR="$RESOURCES_DIR/runtime"

mkdir -p "$DIST_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN_PATH="$BIN_DIR/whispermac"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$RUNTIME_DIR/bin" "$RUNTIME_DIR/Models"

cp "$BIN_PATH" "$MACOS_DIR/WhisperMac"
chmod +x "$MACOS_DIR/WhisperMac"

shopt -s nullglob
for RESOURCE_BUNDLE in "$BIN_DIR"/*.bundle; do
  rsync -a "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
done
shopt -u nullglob

if [ -f "$ROOT/.build-tools/whisper.cpp/build/bin/whisper-cli" ]; then
  cp "$ROOT/.build-tools/whisper.cpp/build/bin/whisper-cli" "$RUNTIME_DIR/bin/"
fi

if [ -f "$ROOT/Models/ggml-large-v3-turbo.bin" ]; then
  cp "$ROOT/Models/ggml-large-v3-turbo.bin" "$RUNTIME_DIR/Models/"
fi

if [ -d "$ROOT/Models/ggml-large-v3-turbo-encoder.mlmodelc" ]; then
  rsync -a "$ROOT/Models/ggml-large-v3-turbo-encoder.mlmodelc" "$RUNTIME_DIR/Models/"
fi

if [ -f "$ROOT/README.md" ]; then
  cp "$ROOT/README.md" "$RESOURCES_DIR/"
fi

if [ -f "$ROOT/CONTRIBUTING.md" ]; then
  cp "$ROOT/CONTRIBUTING.md" "$RESOURCES_DIR/"
fi

if [ -d "$ROOT/docs" ]; then
  rsync -a "$ROOT/docs" "$RESOURCES_DIR/"
fi

if [ -f "$ROOT/LICENSE" ]; then
  cp "$ROOT/LICENSE" "$RESOURCES_DIR/"
fi

if [ -f "$ROOT/THIRD_PARTY_NOTICES.md" ]; then
  cp "$ROOT/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/"
fi

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>WhisperMac</string>
  <key>CFBundleIdentifier</key>
  <string>local.whispermac.app</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>WhisperMac</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
    <string>ja</string>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo
echo "App bundle created:"
echo "  $APP_DIR"
