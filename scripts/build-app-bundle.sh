#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/WhisperMac.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
RUNTIME_DIR="$RESOURCES_DIR/runtime"
ICON_ICNS="$ROOT/Sources/whispermac/Resources/AppIcon.icns"

# App version: WHISPERMAC_VERSION env wins, else the latest git tag
# (leading "v" stripped), else a fallback for tarball builds without git.
VERSION="${WHISPERMAC_VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)}"
VERSION="${VERSION:-0.1.1}"

# Build number: commit count, with a fallback for tarball builds.
BUILD_NUMBER="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || true)"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

echo "Building WhisperMac.app version $VERSION (build $BUILD_NUMBER)"

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

if [ ! -f "$ROOT/.build-tools/whisper.cpp/build/bin/whisper-cli" ]; then
  echo "Bundled runtime binary is missing: $ROOT/.build-tools/whisper.cpp/build/bin/whisper-cli" >&2
  echo "Run ./scripts/setup-whispercpp.sh first." >&2
  exit 1
fi

cp "$ROOT/.build-tools/whisper.cpp/build/bin/whisper-cli" "$RUNTIME_DIR/bin/"

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

if [ -f "$ICON_ICNS" ]; then
  cp "$ICON_ICNS" "$RESOURCES_DIR/AppIcon.icns"
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Movie</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.movie</string>
        <string>public.mpeg-4</string>
        <string>com.apple.quicktime-movie</string>
        <string>com.apple.m4v-video</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Audio</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.audio</string>
        <string>public.mpeg-4-audio</string>
        <string>com.apple.m4a-audio</string>
        <string>public.mp3</string>
        <string>com.microsoft.waveform-audio</string>
        <string>org.xiph.flac</string>
      </array>
    </dict>
  </array>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
  <key>CFBundleVersion</key>
  <string>0</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# The heredoc above stays static; real values are injected here.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"

# Ad-hoc signing: no certificate needed, but gives the bundle a real code
# signature (including nested binaries) so Gatekeeper treats it as a
# proper app instead of unsigned garbage.
codesign --force --deep -s - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
echo "Ad-hoc code signature applied and verified: $APP_DIR"

echo
echo "App bundle created:"
echo "  $APP_DIR"
echo "  version: $VERSION"
echo "  build:   $BUILD_NUMBER"
