#!/bin/zsh
# Sign Tenmaku.app inside an XCArchive or sign a standalone Tenmaku.app.
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: scripts/resign.sh <Tenmaku.xcarchive | Tenmaku.app>" >&2
  exit 1
fi

APP=${1:A}
if [[ "$APP" == *.xcarchive ]]; then
  APP="$APP/Products/Applications/Tenmaku.app"
fi
if [[ "${APP:t}" != Tenmaku.app || ! -f "$APP/Contents/Info.plist" ]]; then
  echo "Tenmaku.app not found: $APP" >&2
  exit 1
fi

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application signing identity}"
HELPERS="$APP/Contents/Library/Helpers"
bundles=("$HELPERS/TenmakuGamma.app" "$HELPERS/TenmakuCover.app"
         "$HELPERS/TenmakuHelper.app" "$HELPERS/TenmakuInput.app" "$APP")
for bundle in "${bundles[@]}"; do
  if [[ ! -f "$bundle/Contents/Info.plist" ]]; then
    echo "Bundle not found: $bundle" >&2
    exit 1
  fi
done

# Sign the embedded bundles before signing the main app.
for bundle in "${bundles[@]}"; do
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$bundle"
done
codesign --verify --deep --strict --verbose=2 "$APP"
echo "$APP"
