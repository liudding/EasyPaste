#!/usr/bin/env bash
# Creates a macOS DMG installer with a drag-to-Applications-folder layout.
# Uses `dmgbuild` (which emits a Finder-valid .DS_Store) instead of hand-rolling
# the DS_Store via the ds_store library -- a hand-rolled root entry name ('')
# is ignored by Finder, so the window size / icon positions were never honored.
#
# Usage: bash script/create_dmg.sh

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/dist/EasyPaste.app"
DMG_VOLNAME="EasyPaste"
DMG_PATH="$PROJECT_DIR/dist/EasyPasteInstaller.dmg"
PYTHON="/Users/ding/.workbuddy/binaries/python/envs/default/bin/python3"

echo "=== EasyPaste DMG Installer Builder (dmgbuild) ==="

# ── 1. Generate background image ──
echo "[1/3] Generating background image..."
$PYTHON "$PROJECT_DIR/script/generate_dmg_background.py"

# ── 2. Build the DMG (staging + layout + compress) via dmgbuild ──
echo "[2/3] Building DMG with dmgbuild..."
rm -f "$DMG_PATH"
$PYTHON -m dmgbuild -s "$PROJECT_DIR/script/dmgbuild_settings.py" "$DMG_VOLNAME" "$DMG_PATH"

# ── 3. Cleanup ──
echo "[3/3] Cleaning up..."
rm -f "$PROJECT_DIR/dist/dmg_background.png"

FINAL_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "=== Done! ==="
echo "DMG: $DMG_PATH ($FINAL_SIZE)"
