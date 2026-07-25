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

# ── Resolve code-signing identity ──
# 检测顺序：Developer ID Application（可分发+公证）> Apple Development（免费账号通用开发证，本地/内测可用）> Mac Developer > 退回 ad-hoc。
# 说明：ad-hoc 无身份，每次编译 cdhash 都变，TCC 辅助功能授权会失效需重授；用证书则 Team ID 稳定，无需重授。
SIGN_IDENTITY=""
for _pat in "Developer ID Application:" "Apple Development:" "Mac Developer:"; do
    if /usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep -q "$_pat"; then
        SIGN_IDENTITY=$(/usr/bin/security find-identity -v -p codesigning 2>/dev/null | grep "$_pat" | head -1 | awk -F'"' '{print $2}')
        break
    fi
done
echo "=== Code signing: ${SIGN_IDENTITY:-ad-hoc (no signing identity found)} ==="

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

# ── Copy Sparkle.framework into app bundle (from SPM build) ──
SPARKLE_SRC="$ROOT_DIR/.build/arm64-apple-macosx/debug/Sparkle.framework"

if [ -d "$SPARKLE_SRC" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$SPARKLE_SRC" "$APP_BUNDLE/Contents/Frameworks/"
    
    # Sign nested framework components
    SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    if [ -n "$SIGN_IDENTITY" ]; then
        find "$SPARKLE_FRAMEWORK" -type f -name "*.dylib" -exec codesign --force --sign "$SIGN_IDENTITY" {} \; 2>/dev/null || true
        codesign --force --sign "$SIGN_IDENTITY" "$SPARKLE_FRAMEWORK" 2>/dev/null || true
    else
        find "$SPARKLE_FRAMEWORK" -type f -name "*.dylib" -exec codesign --force --sign - --timestamp=none {} \; 2>/dev/null || true
        codesign --force --sign - --timestamp=none "$SPARKLE_FRAMEWORK" 2>/dev/null || true
    fi
    
    # Add rpath so @rpath/Sparkle.framework resolves to Contents/Frameworks/
    /usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BINARY" 2>/dev/null || true
    
    echo "[build] ✓ Sparkle.framework copied and signed"
else
    echo "[build] ⚠️  Sparkle.framework not found at $SPARKLE_SRC — run: swift build first"
fi

# ── Sign ──
# 注意：iCloud ubiquity 文件级备份（阶段一持久层迁移）要求使用 Developer ID Application
# 证书 + EasyPaste.entitlements（含 com.apple.developer.ubiquity-container-identifiers）。
# 纯 ad-hoc 签名无 iCloud 能力，运行时会拿不到 ubiquity 容器、同步不生效。
if [ -n "$SIGN_IDENTITY" ]; then
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/EasyPaste.entitlements" "$APP_BUNDLE"
else
    /usr/bin/codesign --force --sign - --timestamp=none "$APP_BUNDLE"
fi

# ── Run / Debug ──
case "$MODE" in
  run)       /usr/bin/open -n "$APP_BUNDLE" ;;
  debug)     lldb -- "$APP_BINARY" ;;
  logs)      /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  verify)    /usr/bin/open -n "$APP_BUNDLE"; sleep 1; pgrep -x "$APP_NAME" >/dev/null ;;
  *)         echo "usage: $0 [run|debug|logs|verify]" >&2; exit 2 ;;
esac
