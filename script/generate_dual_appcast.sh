#!/usr/bin/env bash
# 生成「国内(阿里云 OSS) + 海外(GitHub Releases)」两份 appcast.xml
# 两份均用同一把 Sparkle EdDSA 私钥签名（对应 Info.plist 里的 SUPublicEDKey），
# 这样客户端无论命中哪个源，都能通过同一把公钥校验。
#
# 依赖：
#   - Sparkle 的 sign_update 工具（读取 EdDSA 私钥 seed 文件）
#   - 私钥默认从 script/keys/ed25519_private.key 读取（32 字节 seed 的 base64），
#     可用环境变量 SPARKLE_ED_KEY_FILE 覆盖路径，用 SIGN_UPDATE_TOOL 覆盖 sign_update 路径。
#   - 用法：
#       OSS_BASE="https://easypaste-updates.oss-cn-hangzhou.aliyuncs.com" \
#       ./script/generate_dual_appcast.sh <version> <path/to/EasyPaste.dmg>
#
# 产物（OUT_DIR，默认 ./appcast-out）：
#   - appcast-domestic.xml       → 上传到 OSS 根目录并改名为 appcast.xml
#   - appcast-international.xml  → 作为 GitHub Release 资产（命名 appcast.xml）上传
set -euo pipefail

VERSION="${1:?用法: generate_dual_appcast.sh <version> <dmg-path>}"
DMG="${2:?用法: generate_dual_appcast.sh <version> <dmg-path>}"
PRIVATE_KEY_FILE="${SPARKLE_ED_KEY_FILE:-script/keys/ed25519_private.key}"
SIGN_UPDATE="${SIGN_UPDATE_TOOL:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
[ -f "$PRIVATE_KEY_FILE" ] || { echo "❌ 找不到 EdDSA 私钥文件: $PRIVATE_KEY_FILE（应含 32 字节 seed 的 base64）"; exit 1; }
[ -x "$SIGN_UPDATE" ] || { echo "❌ 找不到 sign_update 工具: $SIGN_UPDATE（先 swift build，或用 SIGN_UPDATE_TOOL 指定）"; exit 1; }

OSS_BASE="${OSS_BASE:-https://easypaste-updates.oss-cn-hangzhou.aliyuncs.com}"
GH_BASE="${GH_BASE:-https://github.com/liudding/EasyPaste/releases}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$VERSION}"
OUT_DIR="${OUT_DIR:-./appcast-out}"
MIN_OS="${MIN_OS:-11.0}"

mkdir -p "$OUT_DIR"

# ---- 1. 用 Sparkle sign_update 计算 EdDSA 签名（覆盖下载 URL + 长度 + 版本）----
SIGN_OUT=$("$SIGN_UPDATE" --ed-key-file "$PRIVATE_KEY_FILE" "$DMG")
ED_SIGN=$(echo "$SIGN_OUT" | sed -n 's/.*edSignature="\([^"]*\)".*/\1/p')
LENGTH=$(echo "$SIGN_OUT"  | sed -n 's/.*length="\([0-9]*\)".*/\1/p')
[ -n "$ED_SIGN" ] && [ -n "$LENGTH" ] || { echo "❌ 签名失败，请检查 sign_update 与私钥"; exit 1; }

PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

# ---- 2. 生成单份 appcast ----
gen_appcast() {
  local feed_url="$1" dmg_url="$2" out_file="$3"
  cat > "$out_file" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>EasyPaste</title>
    <description>EasyPaste 自动更新</description>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure url="$dmg_url"
                 sparkle:version="$BUNDLE_VERSION"
                 sparkle:shortVersionString="$VERSION"
                 sparkle:edSignature="$ED_SIGN"
                 length="$LENGTH"
                 type="application/octet-stream"/>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
    </item>
  </channel>
</rss>
XML
  echo "✅ 生成: $out_file"
  echo "   feed : $feed_url"
  echo "   enclosure -> $dmg_url"
}

# 国内：enclosure 指向 OSS 上的 .dmg（国内用户下载也走 OSS，可达）
gen_appcast "$OSS_BASE/appcast.xml" "$OSS_BASE/EasyPaste.dmg" "$OUT_DIR/appcast-domestic.xml"

# 海外：enclosure 指向 GitHub Release 资产（海外用户下载走 GitHub，可达）
gen_appcast "$GH_BASE/download/v$VERSION/EasyPaste.dmg" "$GH_BASE/download/v$VERSION/EasyPaste.dmg" "$OUT_DIR/appcast-international.xml"

echo ""
echo "下一步："
echo "  1) 将 appcast-domestic.xml 上传到 OSS 根目录并命名为 appcast.xml，同时上传 EasyPaste.dmg"
echo "  2) 将 appcast-international.xml 作为 GitHub Release 资产（命名 appcast.xml）上传到最新 release"
echo "  3) 在 Info.plist 启用 SUPublicEDKey（与上面签名私钥对应的公钥），无需设 SUFeedURL"
