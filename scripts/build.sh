#!/bin/zsh
# Assemble and sign Tenmaku.app. Use --archive to create an unsigned XCArchive.
# Usage: scripts/build.sh [--archive <output.xcarchive>]
# Environment variables: SIGN_IDENTITY, VERSION, BUILD_NUMBER
# Set TENMAKU_TEST_BUILD=1 to create a display shielding test build in build/test/.
# Keep test builds for local use.
set -euo pipefail

ROOT=${0:A:h:h}
VERSION=${VERSION:-0.2.0}
BUILD_NUMBER=${BUILD_NUMBER:-1}

ARCHIVE=
SWIFT_FLAGS=()
if (( $# == 2 )) && [[ "$1" == --archive && "$2" == *.xcarchive ]]; then
  ARCHIVE=${2:A}
  if [[ -n "${TENMAKU_TEST_BUILD:-}" ]]; then
    echo "Test builds cannot be exported as an XCArchive." >&2
    exit 1
  fi
  if [[ -e "$ARCHIVE" || -L "$ARCHIVE" ]]; then
    echo "Output path already exists: $ARCHIVE" >&2
    exit 1
  fi
  mkdir -p "${ARCHIVE:h}"
  STAGING_DIR=$(mktemp -d "${ARCHIVE:h}/.tenmaku-archive.XXXXXX")
  trap 'rm -rf "$STAGING_DIR"' EXIT
  STAGED_ARCHIVE="$STAGING_DIR/${ARCHIVE:t}"
  APP="$STAGED_ARCHIVE/Products/Applications/Tenmaku.app"
elif (( $# != 0 )); then
  echo "Usage: scripts/build.sh [--archive <output.xcarchive>]" >&2
  exit 1
elif [[ -n "${TENMAKU_TEST_BUILD:-}" ]]; then
  APP="$ROOT/build/test/Tenmaku.app"
  SWIFT_FLAGS=(-Xswiftc -DTENMAKU_TEST_BUILD)
else
  APP="$ROOT/build/Tenmaku.app"
fi
if [[ -z "$ARCHIVE" ]]; then
  : "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application signing identity}"
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

if [[ -z "$ARCHIVE" ]]; then
  "$ROOT/scripts/resign.sh" "$APP"
  exit
fi

mkdir "$STAGED_ARCHIVE/dSYMs"
for bundle in "$APP" "$HELPER_APP" "$GAMMA_APP" "$COVER_APP" "$INPUT_APP"; do
  name=${${bundle:t}%.app}
  executable="$bundle/Contents/MacOS/$name"
  # Remove the ad hoc signature added by the linker.
  if codesign --display --arch arm64 "$executable" 2>/dev/null ||
     codesign --display --arch x86_64 "$executable" 2>/dev/null; then
    codesign --remove-signature "$executable"
  fi
  ditto "$BIN/$name.dSYM" "$STAGED_ARCHIVE/dSYMs/$name.dSYM"
done

INFO="$STAGED_ARCHIVE/Info.plist"
plutil -create xml1 "$INFO"
plutil -insert ArchiveVersion -integer 2 "$INFO"
plutil -insert CreationDate -date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$INFO"
plutil -insert Name -string Tenmaku "$INFO"
plutil -insert SchemeName -string Tenmaku "$INFO"
plutil -insert ApplicationProperties -dictionary "$INFO"
plutil -insert ApplicationProperties.ApplicationPath -string Applications/Tenmaku.app "$INFO"
for key in CFBundleIdentifier CFBundleShortVersionString CFBundleVersion; do
  value=$(plutil -extract "$key" raw -o - "$APP/Contents/Info.plist")
  plutil -insert "ApplicationProperties.$key" -string "$value" "$INFO"
done
plutil -insert ApplicationProperties.Architectures -json '["arm64","x86_64"]' "$INFO"

mv -n "$STAGED_ARCHIVE" "${ARCHIVE:h}/"
if [[ -e "$STAGED_ARCHIVE" ]]; then
  echo "Output path already exists: $ARCHIVE" >&2
  exit 1
fi
echo "$ARCHIVE"
