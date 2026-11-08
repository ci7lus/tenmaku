#!/bin/zsh
# Assemble Tenmaku.app and sign it with Developer ID and Hardened Runtime.
# Usage: scripts/build.sh
# Environment variables: SIGN_IDENTITY (signing certificate), VERSION, BUILD_NUMBER
set -euo pipefail

ROOT=${0:A:h:h}
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application signing identity}"
VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-0}

APP="$ROOT/build/Tenmaku.app"
HELPER_APP="$APP/Contents/Library/Helpers/TenmakuHelper.app"

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64
BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources" \
         "$APP/Contents/Library/LaunchAgents" \
         "$APP/Contents/Library/LaunchDaemons" \
         "$HELPER_APP/Contents/MacOS"

cp Bundle/Tenmaku-Info.plist "$APP/Contents/Info.plist"
cp Bundle/TenmakuHelper-Info.plist "$HELPER_APP/Contents/Info.plist"
cp Bundle/LaunchAgents/*.plist "$APP/Contents/Library/LaunchAgents/"
cp Bundle/LaunchDaemons/*.plist "$APP/Contents/Library/LaunchDaemons/"
for plist in "$APP/Contents/Info.plist" "$HELPER_APP/Contents/Info.plist"; do
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$plist"
done

xcrun actool Bundle/Assets.xcassets assets/Tenmaku.icon \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --accent-color AccentColor \
  --app-icon Tenmaku \
  --output-partial-info-plist "$ROOT/.build/assets-info.plist" \
  --output-format human-readable-text --errors --warnings

cp "$BIN/Tenmaku" "$BIN/TenmakuGamma" "$BIN/TenmakuCover" "$APP/Contents/MacOS/"
cp "$BIN/TenmakuHelper" "$HELPER_APP/Contents/MacOS/"

sign() {
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@"
}

# Sign nested components before the outer bundle.
sign --identifier jp.pronama.tenmaku.gamma "$APP/Contents/MacOS/TenmakuGamma"
sign --identifier jp.pronama.tenmaku.cover "$APP/Contents/MacOS/TenmakuCover"
sign "$HELPER_APP"
sign "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "$APP"
