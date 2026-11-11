#!/bin/zsh
# Create and notarize a distribution DMG from a signed Tenmaku.app.
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  echo "Usage: NOTARY_PROFILE=<profile> scripts/dmg.sh <Tenmaku.app> [output.dmg]" >&2
  exit 1
fi

APP=${1:A}
OUTPUT=${2:-"${APP:h}/Tenmaku.dmg"}
OUTPUT=${OUTPUT:A}
if [[ "${APP:t}" != Tenmaku.app || ! -f "$APP/Contents/Info.plist" ]]; then
  echo "Tenmaku.app not found: $APP" >&2
  exit 1
fi
if [[ "$OUTPUT" != *.dmg || -e "$OUTPUT" || -L "$OUTPUT" ]]; then
  echo "Specify a new output path ending in .dmg: $OUTPUT" >&2
  exit 1
fi

: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to the name of a saved notarytool credentials profile}"
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application signing identity}"
codesign --verify --deep --strict --verbose=2 \
  -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP"

mkdir -p "${OUTPUT:h}"
STAGING_DIR=$(mktemp -d "${OUTPUT:h}/.tenmaku-dmg.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
mkdir "$STAGING_DIR/volume"
ditto "$APP" "$STAGING_DIR/volume/Tenmaku.app"
ln -s /Applications "$STAGING_DIR/volume/Applications"

DMG="$STAGING_DIR/${OUTPUT:t}"
hdiutil create -volname Tenmaku -fs HFS+ -format UDZO -srcfolder "$STAGING_DIR/volume" "$DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp --identifier jp.pronama.tenmaku "$DMG"
codesign --verify --verbose=2 "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

mv -n "$DMG" "${OUTPUT:h}/"
if [[ -e "$DMG" ]]; then
  echo "Output path already exists: $OUTPUT" >&2
  exit 1
fi
echo "$OUTPUT"
