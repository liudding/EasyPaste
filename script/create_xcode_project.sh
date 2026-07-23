#!/usr/bin/env bash
# 为 EasyPaste 生成 Xcode project，以便集成 Sparkle SPM 依赖。
# 用法: bash script/create_xcode_project.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$ROOT_DIR"
XCODE_PROJECT="$PROJECT_DIR/EasyPaste.xcodeproj"

echo "=== Creating Xcode Project for EasyPaste ==="

# 1. 用 xcodeproj 工具生成（如果可用）
if command -v xcodeproj &>/dev/null; then
    echo "[1/3] Generating Xcode project with xcodeproj gem..."
    cd "$PROJECT_DIR"
    xcodeproj generate --scheme EasyPaste
    echo "[done]"
else
    echo "[1/3] ⚠️  xcodeproj gem not found. Install it:"
    echo "        sudo gem install xcodeproj"
    echo ""
    echo "   Or create the project manually in Xcode:"
    echo "   1. File → New → Project → macOS → App"
    echo "   2. Add existing sources from App/, Models/, Services/, Stores/, Views/"
    echo "   3. Add Sparkle via File → Add Packages → https://github.com/sparkle-project/Sparkle"
    echo "   4. Set Info.plist keys: SUFeedURL, SUPublicEDKey"
fi

echo "=== Done ==="
