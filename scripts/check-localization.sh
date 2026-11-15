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
  "$ROOT/Sources/Tenmaku/LocalizationResources.swift" \
  "$ROOT/Tests/LocalizationCheck.swift" -o "$APP/Contents/MacOS/LocalizationCheck"
for language in ja en fr; do
  "$APP/Contents/MacOS/LocalizationCheck" "$language" -AppleLanguages "($language)" -AppleLocale "$language"
done

for resource in ja.lproj/Localizable.strings en.lproj/Localizable.strings en.lproj/Localizable.stringsdict; do
  mv "$APP/Contents/Resources/$resource" "$PROBE/removed"
  probe_exit=0
  output=$("$APP/Contents/MacOS/LocalizationCheck" ja -AppleLanguages '(ja)' -AppleLocale ja 2>&1) || probe_exit=$?
  if [[ "$probe_exit" != 1 || "$output" != *"$resource"* ]]; then
    print -u2 -- "The app did not report the missing translation resource and exit: $resource (exit code $probe_exit)"
    print -u2 -- "$output"
    exit 1
  fi
  mv "$PROBE/removed" "$APP/Contents/Resources/$resource"
done
print -- 'Launch correctly refused when translation resources were missing'
