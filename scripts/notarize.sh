#!/bin/zsh
# Submit the Tenmaku.app built by scripts/build.sh for notarization, staple the ticket, and verify Gatekeeper assessment.
# Usage: NOTARY_PROFILE=<name> scripts/notarize.sh
# NOTARY_PROFILE is the name of the credentials saved in Keychain with `xcrun notarytool store-credentials <name>`.
set -euo pipefail

ROOT=${0:A:h:h}
APP="$ROOT/build/Tenmaku.app"
ZIP="$ROOT/build/Tenmaku.zip"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to the name of your notarytool credentials.}"

[[ -d "$APP" ]] || { echo "$APP is missing. Run scripts/build.sh first." >&2; exit 1; }

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

for code in "$APP" \
            "$APP/Contents/Library/Helpers/TenmakuHelper.app"; do
  spctl --assess --type execute --verbose=4 "$code"
done

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$ZIP"
