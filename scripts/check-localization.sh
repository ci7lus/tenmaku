#!/bin/zsh
# Check translations from the app bundle without changing displays or input.
set -euo pipefail
ROOT=${0:A:h:h}
PROBE=$(mktemp -d "${TMPDIR:-/tmp}/tenmaku-localization.XXXXXX")
trap 'rm -rf "$PROBE"' EXIT
APP="$PROBE/LocalizationCheck.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
python3 "$ROOT/scripts/generate-strings.py" --check
xcrun xcstringstool compile "$ROOT/Bundle/Localizable.xcstrings" --output-directory "$APP/Contents/Resources"
cp "$ROOT/Bundle/Tenmaku-Info.plist" "$APP/Contents/Info.plist"
plutil -replace CFBundleExecutable -string LocalizationCheck "$APP/Contents/Info.plist"
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$PROBE/ModuleCache" \
  -emit-module -emit-library -module-name TenmakuShared \
  "$ROOT/Sources/TenmakuShared/LayerFailure.swift" \
  -emit-module-path "$PROBE/TenmakuShared.swiftmodule" -o "$PROBE/libTenmakuShared.dylib"
swiftc -target "$(uname -m)-apple-macos13.0" -module-cache-path "$PROBE/ModuleCache" \
  -I "$PROBE" -L "$PROBE" -lTenmakuShared -Xlinker -rpath -Xlinker "$PROBE" \
  "$ROOT/Sources/Tenmaku/Strings.swift" "$ROOT/Sources/Tenmaku/LocalizedLayerError.swift" \
  "$ROOT/Tests/LocalizationCheck.swift" -o "$APP/Contents/MacOS/LocalizationCheck"
for language in ja en fr; do
  "$APP/Contents/MacOS/LocalizationCheck" "$language" -AppleLanguages "($language)" -AppleLocale "$language"
done
