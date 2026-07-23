#!/usr/bin/env bash
# 从 Sparkle GitHub Releases 下载 Sparkle.framework
# 用法: bash script/setup_sparkle.sh [version]
#   version: 默认 2.8.1，可指定其他版本

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPARKLE_VERSION="${1:-2.8.1}"
SPARKLE_DIR="$ROOT_DIR/Frameworks/Sparkle.framework"

echo "=== Setting up Sparkle.framework v${SPARKLE_VERSION} ==="

if [ -d "$SPARKLE_DIR" ]; then
    echo "✓ Sparkle.framework already exists at $SPARKLE_DIR"
    exit 0
fi

mkdir -p "$ROOT_DIR/Frameworks"

# 下载 Sparkle release
SPARKLE_TARBALL="/tmp/sparkle-${SPARKLE_VERSION}.tar.xz"
curl -L "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
    -o "$SPARKLE_TARBALL"

# 解压
tar -xJf "$SPARKLE_TARBALL" -C /tmp/

# 找到 Sparkle.framework（可能在 Sparkle*/bin/ 或 Sparkle* 根目录）
SPARKLE_SRC=""
for dir in /tmp/Sparkle-*/Sparkle.framework /tmp/Sparkle*/bin/Sparkle.framework; do
    if [ -d "$dir" ]; then
        SPARKLE_SRC="$dir"
        break
    fi
done

if [ -z "$SPARKLE_SRC" ]; then
    echo "❌ Could not find Sparkle.framework in downloaded archive"
    rm -f "$SPARKLE_TARBALL"
    exit 1
fi

cp -R "$SPARKLE_SRC" "$SPARKLE_DIR"

# 清理
rm -f "$SPARKLE_TARBALL"

echo "✓ Sparkle.framework installed to $SPARKLE_DIR"

# 验证
if [ -f "$SPARKLE_DIR/Sparkle" ]; then
    echo "✓ Binary present: $(file "$SPARKLE_DIR/Sparkle")"
else
    echo "⚠️  No binary found in framework"
fi
