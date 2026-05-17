#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="KoVim"
CONFIGURATION="release"
BUNDLE_DIR="$ROOT/.build/$APP_NAME.app"
CONTENTS="$BUNDLE_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

cd "$ROOT"
swift build -c "$CONFIGURATION" --product kovim-agent
swift build -c "$CONFIGURATION" --product kovim-im

rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$ROOT/.build/$CONFIGURATION/kovim-agent" "$MACOS/KoVim"
cp "$ROOT/.build/$CONFIGURATION/kovim-im" "$MACOS/kovim-im"

# ── Resources ────────────────────────────────────────────────────────────────
cp "$ROOT/assets/AppIcon.icns"  "$RESOURCES/AppIcon.icns"
cp "$ROOT/assets/menubar.png"   "$RESOURCES/menubar.png"
cp "$ROOT/assets/menubar@2x.png" "$RESOURCES/menubar@2x.png"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>KoVim</string>
  <key>CFBundleIdentifier</key>
  <string>works.earendil.kovim</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>KoVim</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>KoVim can open Terminal to list installed macOS input sources.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>KoVim listens for Escape and Control-[ in configured editor apps to switch the keyboard input source back to English.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$BUNDLE_DIR" >/dev/null

echo "Built $BUNDLE_DIR"
echo "Open it with: open '$BUNDLE_DIR'"
