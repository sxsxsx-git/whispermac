#!/bin/zsh
# Build the debug executable and refresh the double-clickable app bundle at
# the repository root, so manual testing never involves the hidden .build
# folder. Run this instead of `swift build`; it performs the same build and
# then copies the executable plus its SPM resource bundle into WhisperMac.app.
set -euo pipefail
cd "$(dirname "$0")"

swift build

APP="WhisperMac.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/debug/whispermac "$APP/Contents/MacOS/WhisperMac"
cp -R .build/debug/whispermac_whispermac.bundle "$APP/Contents/Resources/"
cp Sources/whispermac/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0-dev</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
</dict>
</plist>
PLIST

echo "Built $PWD/$APP"
