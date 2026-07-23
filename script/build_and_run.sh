#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="EasyPaste"
BUNDLE_ID="com.easypaste.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
swift build
rm -rf "$APP_BUNDLE"
mkdir -p "$(dirname "$APP_BINARY")"
cp "$(swift build --show-bin-path)/$APP_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# A stable ad-hoc signature gives macOS one persistent accessibility identity
# across rebuilds of this local development app.
/usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"

case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug|debug) lldb -- "$APP_BINARY" ;;
  --logs|logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry|telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify|verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
