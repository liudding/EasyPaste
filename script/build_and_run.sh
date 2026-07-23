#!/usr/bin/env bash
# EasyPaste 构建脚本（SPM 开发模式 + Xcode 分发模式）
# 
# 用法:
#   bash script/build_and_run.sh [run|debug]    # SPM 开发模式（无需 Xcode project）
#   xcodebuild -project EasyPaste.xcodeproj     # Xcode 分发模式（含 Sparkle）

set -euo pipefail

APP_NAME="EasyPaste"
BUNDLE_ID="com.easypaste.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

MODE="${1:-run}"

# ── Kill existing app ──
pkill -x "$APP_NAME" >/dev/null 2>&1 || true

# ── Build via SPM ──
echo "=== Building EasyPaste ==="
swift build --disable-sandbox

rm -rf "$APP_BUNDLE"
mkdir -p "$(dirname "$APP_BINARY")"
cp "$(swift build --show-bin-path --disable-sandbox)/$APP_NAME" "$APP_BINARY"
chmod +x "$APP_BINARY"

# ── Copy icon into Resources ──
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp "$ROOT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# ── Generate Info.plist ──
cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

# ── Setup Sparkle.framework (download if not present) ──
if [ ! -d "$ROOT_DIR/Frameworks/Sparkle.framework" ]; then
    echo "[build] Setting up Sparkle.framework..."
    bash "$ROOT_DIR/script/setup_sparkle.sh" 2>/dev/null || echo "[build] ⚠️  Sparkle setup skipped (requires network)"
fi

# ── Copy Sparkle.framework into app bundle ──
SPARKLE_SRC="$ROOT_DIR/Frameworks/Sparkle.framework"
if [ -d "$SPARKLE_SRC" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$SPARKLE_SRC" "$APP_BUNDLE/Contents/Frameworks/"
    
    # 重新签名 Sparkle 嵌套组件
    SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    find "$SPARKLE_FRAMEWORK" -type f -name "*.dylib" -exec codesign --force \
      --sign - --timestamp=none {} \; 2>/dev/null || true
    codesign --force --sign - --timestamp=none "$SPARKLE_FRAMEWORK" 2>/dev/null || true
    
    echo "[build] ✓ Sparkle.framework copied and signed"
else
    echo "[build] ⚠️  Sparkle.framework not found — run: bash script/setup_sparkle.sh"
fi

# ── Sign ──
/usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"

# ── Run / Debug ──
case "$MODE" in
  run)       /usr/bin/open -n "$APP_BUNDLE" ;;
  debug)     lldb -- "$APP_BINARY" ;;
  logs)      /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  verify)    /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *)         echo "usage: $0 [run|debug|logs|verify]" >&2; exit 2 ;;
esac
