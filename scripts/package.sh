#!/usr/bin/env bash
#
# Package EasyPaste into a signed .app + .dmg for one architecture.
#
# Why a script (instead of inline CI steps):
#   - `swift build` (SwiftPM) drops products in `.build/<arch>-apple-macosx/<config>`,
#     NOT the legacy `.build/release`. We read the binary from the triple path.
#   - SwiftPM resource bundles (e.g. the L10n localization, produced by
#     `.process("L10n")`) MUST be copied into the app bundle or `Bundle.module`
#     lookups fail at runtime. We glob every *.bundle from the build dir.
#   - The repo's Info.plist uses Xcode build variables ($(EXECUTABLE_NAME), …)
#     that are never substituted under `swift build`, so we generate a concrete
#     Info.plist here with real values (incl. the Sparkle SUPublicEDKey).
#
# Usage:
#   ARCH=arm64|$(uname -m) CONFIGURATION=release DIST_DIR=dist \
#   SPARKLE_FRAMEWORK=/path/to/Sparkle.framework VERSION=1.2.3 \
#   bash scripts/package.sh
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="EasyPaste"
EXECUTABLE_NAME="EasyPaste"
DEFAULT_BUNDLE_ID="com.easypaste.app"
MIN_SYSTEM_VERSION="15.0"
SPARKLE_PUBLIC_ED_KEY="jlED6oIY6bkrmxl4bLOhAKU5hacnHckznYYgYNLBilU="

ARCH="${ARCH:-$(uname -m)}"
CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE_ID="${BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
SPARKLE_FRAMEWORK="${SPARKLE_FRAMEWORK:-}"

BUILD_DIR="$ROOT_DIR/.build/${ARCH}-apple-macosx/${CONFIGURATION}"
PRODUCT_BINARY="$BUILD_DIR/$EXECUTABLE_NAME"
ICON_FILE="$ROOT_DIR/AppIcon.icns"

resolve_version() {
  if [[ -n "${VERSION:-}" ]]; then
    printf '%s\n' "$VERSION"
    return 0
  fi
  if git -C "$ROOT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
    local tag
    tag="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 2>/dev/null || true)"
    tag="${tag#v}"
    if [[ -n "$tag" ]]; then
      printf '%s\n' "$tag"
      return 0
    fi
  fi
  echo "VERSION is not set and no git tag was found." >&2
  echo "Use: ARCH=arm64 VERSION=1.2.3 bash scripts/package.sh" >&2
  exit 1
}

VERSION="$(resolve_version)"
APP_DIR="$DIST_DIR/${APP_NAME}.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}-${ARCH}.dmg"
STAGING_DIR="$DIST_DIR/.dmg-staging"

printf '[package] building %s %s (%s)\n' "$APP_NAME" "$VERSION" "$ARCH"
swift build -c "$CONFIGURATION" --arch "$ARCH"

if [[ ! -x "$PRODUCT_BINARY" ]]; then
  echo "Built binary not found: $PRODUCT_BINARY" >&2
  exit 1
fi

# Glob every *.bundle produced by SwiftPM resource targets. Hard-coding names
# silently misses new SPM dependencies and crashes Bundle.module at runtime.
RESOURCE_BUNDLES=("$BUILD_DIR"/*.bundle)
if [[ ! -d "${RESOURCE_BUNDLES[0]}" ]]; then
  echo "No SwiftPM resource bundles found in $BUILD_DIR" >&2
  exit 1
fi

if [[ ! -f "$ICON_FILE" ]]; then
  echo "App icon not found: $ICON_FILE" >&2
  exit 1
fi

rm -rf "$APP_DIR" "$STAGING_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks" "$DIST_DIR"

cp "$PRODUCT_BINARY" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$ICON_FILE" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Resource bundles go in Contents/Resources so the bundle structure is valid.
# SwiftPM's Bundle.module will find them by walking up from the executable.
for bundle in "${RESOURCE_BUNDLES[@]}"; do
  cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP_DIR/Contents/Frameworks/"
  codesign --force --sign - "$APP_DIR/Contents/Frameworks/Sparkle.framework" 2>/dev/null || true
fi

CURRENT_YEAR="$(date +%Y)"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>zh-Hans</string>
    <string>zh-Hant</string>
    <string>ja</string>
    <string>ko</string>
    <string>fr</string>
    <string>es</string>
    <string>pt</string>
    <string>ru</string>
    <string>de</string>
  </array>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_SYSTEM_VERSION}</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>EasyPaste needs accessibility permission to simulate keyboard paste, allowing clipboard content to be pasted into the target application.</string>
  <key>NSHumanReadableCopyright</key>
  <string>© ${CURRENT_YEAR} EasyPaste. All rights reserved.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeDescription</key>
      <string>EasyPaste Clip</string>
      <key>UTTypeIdentifier</key>
      <string>com.easypaste.clip</string>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <string>easypaste</string>
      </dict>
    </dict>
  </array>
  <key>SUPublicEDKey</key>
  <string>${SPARKLE_PUBLIC_ED_KEY}</string>
</dict>
</plist>
EOF

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  printf '[package] codesigning app bundle with identity\n'
  codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"
else
  printf '[package] codesigning app bundle (ad-hoc)\n'
  codesign --force --deep --sign - "$APP_DIR"
fi

mkdir -p "$STAGING_DIR"
cp -R "$APP_DIR" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

printf '[package] creating dmg %s\n' "$(basename "$DMG_PATH")"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

printf '[package] app: %s\n' "$APP_DIR"
printf '[package] dmg: %s\n' "$DMG_PATH"
