#!/bin/zsh
# Assemble Tenmaku.app and sign it with Developer ID and Hardened Runtime.
# Usage: scripts/build.sh
# Environment variables: SIGN_IDENTITY (signing certificate), VERSION, BUILD_NUMBER
#           Set TENMAKU_TEST_BUILD=1 to write a shielding test build to build/test/. Exclude it from distribution.
set -euo pipefail

ROOT=${0:A:h:h}
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application signing identity}"
VERSION=${VERSION:-0.1.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}

if [[ -n "${TENMAKU_TEST_BUILD:-}" ]]; then
  APP="$ROOT/build/test/Tenmaku.app"
  SWIFT_FLAGS=(-Xswiftc -DTENMAKU_TEST_BUILD)
else
  APP="$ROOT/build/Tenmaku.app"
  SWIFT_FLAGS=()
fi
HELPERS="$APP/Contents/Library/Helpers"
HELPER_APP="$HELPERS/TenmakuHelper.app"
GAMMA_APP="$HELPERS/TenmakuGamma.app"
COVER_APP="$HELPERS/TenmakuCover.app"
INPUT_APP="$HELPERS/TenmakuInput.app"

cd "$ROOT"
python3 scripts/generate-strings.py
swift build -c release --arch arm64 --arch x86_64 "${SWIFT_FLAGS[@]}"
BIN=$(swift build -c release --arch arm64 --arch x86_64 "${SWIFT_FLAGS[@]}" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" \
         "$APP/Contents/Resources" \
         "$APP/Contents/Library/LaunchAgents" \
         "$APP/Contents/Library/LaunchDaemons" \
         "$HELPER_APP/Contents/MacOS" \
         "$GAMMA_APP/Contents/MacOS" \
         "$COVER_APP/Contents/MacOS" \
         "$INPUT_APP/Contents/MacOS"

cp Bundle/Tenmaku-Info.plist "$APP/Contents/Info.plist"
cp Bundle/TenmakuHelper-Info.plist "$HELPER_APP/Contents/Info.plist"
cp Bundle/TenmakuGamma-Info.plist "$GAMMA_APP/Contents/Info.plist"
cp Bundle/TenmakuCover-Info.plist "$COVER_APP/Contents/Info.plist"
cp Bundle/TenmakuInput-Info.plist "$INPUT_APP/Contents/Info.plist"
cp Bundle/LaunchAgents/*.plist "$APP/Contents/Library/LaunchAgents/"
cp Bundle/LaunchDaemons/*.plist "$APP/Contents/Library/LaunchDaemons/"
for plist in "$APP/Contents/Info.plist" "$HELPER_APP/Contents/Info.plist" "$GAMMA_APP/Contents/Info.plist" "$COVER_APP/Contents/Info.plist" "$INPUT_APP/Contents/Info.plist"; do
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$plist"
  plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$plist"
done

xcrun xcstringstool compile Bundle/Localizable.xcstrings --output-directory "$APP/Contents/Resources"

xcrun actool Bundle/Assets.xcassets assets/Tenmaku.icon \
  --compile "$APP/Contents/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --accent-color AccentColor \
  --app-icon Tenmaku \
  --output-partial-info-plist "$ROOT/.build/assets-info.plist" \
  --output-format human-readable-text --errors --warnings

cp "$BIN/Tenmaku" "$APP/Contents/MacOS/"
cp "$BIN/TenmakuHelper" "$HELPER_APP/Contents/MacOS/"
cp "$BIN/TenmakuGamma" "$GAMMA_APP/Contents/MacOS/"
cp "$BIN/TenmakuCover" "$COVER_APP/Contents/MacOS/"
cp "$BIN/TenmakuInput" "$INPUT_APP/Contents/MacOS/"

sign() {
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$@"
}

# Sign nested components before the outer bundle.
sign "$GAMMA_APP"
sign "$COVER_APP"
sign "$HELPER_APP"
sign "$INPUT_APP"
sign "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "$APP"
