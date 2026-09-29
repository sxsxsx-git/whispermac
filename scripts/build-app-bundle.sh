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
WHISPER_BIN_DIR="$ROOT/.build-tools/whisper.cpp/build/bin"

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

# Copy .lproj directories directly so Bundle.main can find them in distributed apps.
for LPROJ_DIR in "$ROOT"/Sources/whispermac/Resources/*.lproj; do
  rsync -a "$LPROJ_DIR" "$RESOURCES_DIR/"
done

if [ ! -f "$WHISPER_BIN_DIR/whisper-cli" ]; then
  echo "Bundled runtime binary is missing: $WHISPER_BIN_DIR/whisper-cli" >&2
  echo "Run ./scripts/setup-whispercpp.sh first." >&2
  exit 1
fi

cp "$WHISPER_BIN_DIR/whisper-cli" "$RUNTIME_DIR/bin/"
shopt -s nullglob
for DYLIB in "$WHISPER_BIN_DIR"/*.dylib; do
  # -P preserves versioned dylib symlinks alongside their real files.
  cp -P "$DYLIB" "$RUNTIME_DIR/bin/"
done
shopt -u nullglob

# Rewrite all whisper.cpp dependencies to resolve beside the loading binary.
# System libraries remain system references; every other dependency must be
# present in the app runtime directory or packaging fails immediately.
while IFS= read -r BINARY; do
  [ -n "$BINARY" ] || continue
  while IFS= read -r DEPENDENCY; do
    [ -n "$DEPENDENCY" ] || continue
    case "$DEPENDENCY" in
      /System/Library/*|/usr/lib/*) continue ;;
    esac
    DEPENDENCY_NAME="$(basename "$DEPENDENCY")"
    if [ ! -e "$RUNTIME_DIR/bin/$DEPENDENCY_NAME" ]; then
      echo "Unbundled non-system dependency: $DEPENDENCY ($BINARY)" >&2
      exit 1
    fi
    case "$DEPENDENCY" in
      "@rpath/$DEPENDENCY_NAME") ;;
      *) install_name_tool -change "$DEPENDENCY" "@rpath/$DEPENDENCY_NAME" "$BINARY" ;;
    esac
  done < <(otool -L "$BINARY" | tail -n +2 | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//')

  if [[ "$BINARY" == *.dylib ]]; then
    install_name_tool -id "@rpath/$(basename "$BINARY")" "$BINARY"
  fi

  if ! otool -l "$BINARY" | grep -Fq 'path @loader_path'; then
    install_name_tool -add_rpath '@loader_path' "$BINARY"
  fi

  while IFS= read -r OLD_RPATH; do
    case "$OLD_RPATH" in
      "$ROOT"/*|*"/.build-tools/whisper.cpp/"*)
        install_name_tool -delete_rpath "$OLD_RPATH" "$BINARY"
        ;;
    esac
  done < <(otool -l "$BINARY" | awk '/cmd LC_RPATH/{getline; getline; sub(/^[[:space:]]*path /, ""); sub(/ \(offset.*/, ""); print}')
done < <(find "$RUNTIME_DIR/bin" -type f \( -name 'whisper-cli' -o -name '*.dylib' \) -print)

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

# Sign nested code from the inside out so every rewritten dylib and executable
# is sealed before the containing application is signed.
find "$RUNTIME_DIR/bin" -type f -name '*.dylib' -print0 | while IFS= read -r -d '' DYLIB; do
  codesign --force --sign - "$DYLIB"
done
codesign --force --sign - "$RUNTIME_DIR/bin/whisper-cli"
codesign --force --sign - "$MACOS_DIR/WhisperMac"
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Relocation smoke test: a copied app must launch its CLI without reaching
# back into this checkout or depending on a build-machine install name.
MIGRATION_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/whispermac-migration.XXXXXX")"
trap 'rm -rf "$MIGRATION_ROOT"' EXIT
MIGRATED_APP="$MIGRATION_ROOT/WhisperMac.app"
ditto "$APP_DIR" "$MIGRATED_APP"
MIGRATED_CLI="$MIGRATED_APP/Contents/Resources/runtime/bin/whisper-cli"
"$MIGRATED_CLI" --help >/dev/null
if otool -L "$MIGRATED_CLI" | grep -F "$ROOT/.build-tools/" >/dev/null; then
  echo "Migrated CLI still references the checkout runtime." >&2
  exit 1
fi
codesign --verify --deep --strict "$MIGRATED_APP"
echo "Ad-hoc signature and relocated CLI verified: $APP_DIR"

echo
echo "App bundle created:"
echo "  $APP_DIR"
echo "  version: $VERSION"
echo "  build:   $BUILD_NUMBER"
