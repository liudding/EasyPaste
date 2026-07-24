#!/usr/bin/env bash
# Creates a macOS DMG installer with drag-to-Applications-folder layout.
# Uses Python ds-store library to write .DS_Store (no AppleScript needed).
# Usage: bash script/create_dmg.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/EasyPaste.app"
# Use a volume name without spaces to avoid mount path parsing issues
DMG_VOLNAME="EasyPaste"
DMG_PATH="$PROJECT_DIR/dist/EasyPasteInstaller.dmg"
# Staging must live OUTSIDE the package directory: the Applications symlink inside
# staging would otherwise be followed by SwiftPM's package directory scan, making
# llbuild index all of /Applications (~500k files) and bloating .build/build.db
# to gigabytes (swift test/build effectively hang).
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/easypaste-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
BG_SRC="$PROJECT_DIR/dist/dmg_background.png"
PYTHON="/Users/ding/.workbuddy/binaries/python/envs/default/bin/python3"

echo "=== EasyPaste DMG Installer Builder ==="

# ── 1. Generate background image ──
echo "[1/6] Generating background image..."
$PYTHON "$PROJECT_DIR/script/generate_dmg_background.py"

# ── 2. Prepare staging directory ──
echo "[2/6] Preparing staging directory..."
cp -R "$APP_PATH" "$STAGING/EasyPaste.app"
ln -s /Applications "$STAGING/Applications"

# ── 3. Create temporary DMG ──
echo "[3/6] Creating temporary DMG..."
rm -f "$DMG_PATH"
hdiutil create -srcfolder "$STAGING" -volname "$DMG_VOLNAME" \
  -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
  -format UDRW -size 200m \
  "$DMG_PATH"

# ── 4. Mount DMG, copy background, write .DS_Store via Python ──
echo "[4/6] Mounting DMG and configuring layout..."
MOUNT_DIR="/Volumes/$DMG_VOLNAME"
hdiutil attach "$DMG_PATH" -readwrite -noverify -noautoopen

# Copy background into the DMG
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_SRC" "$MOUNT_DIR/.background/background.png"

# Write .DS_Store via Python ds-store library
$PYTHON "$PROJECT_DIR/script/write_dmg_dsstore.py" "$MOUNT_DIR"

sync

# ── 5. Detach and convert to compressed ──
echo "[5/6] Finalizing DMG..."
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed, read-only final DMG (use temp name to avoid "file exists")
TEMP_DMG="$DMG_PATH.compressed"
rm -f "$TEMP_DMG" "${TEMP_DMG}.dmg"
hdiutil convert "$DMG_PATH" -format UDZO -imagekey zlib-level=9 -o "$TEMP_DMG"
rm -f "$DMG_PATH"
# hdiutil adds .dmg extension automatically
mv "${TEMP_DMG}.dmg" "$DMG_PATH"

# ── 6. Cleanup ──
echo "[6/6] Cleaning up..."
rm -f "$BG_SRC"
# staging 目录由 trap EXIT 统一清理（含失败/中断场景）

FINAL_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "=== Done! ==="
echo "DMG: $DMG_PATH ($FINAL_SIZE)"
