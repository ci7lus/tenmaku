#!/bin/zsh
# Test the guide using dialog selections without changing displays or input.
set -euo pipefail
ROOT=${0:A:h:h}
PROBE=$(mktemp -d "${TMPDIR:-/tmp}/tenmaku-unlock-guide.XXXXXX")
trap 'rm -rf "$PROBE"' EXIT
python3 "$ROOT/scripts/generate-strings.py" --check
swiftc -swift-version 6 -target "$(uname -m)-apple-macos13.0" -module-cache-path "$PROBE/ModuleCache" \
  "$ROOT/Sources/Tenmaku/Strings.swift" "$ROOT/Sources/Tenmaku/UnlockGuide.swift" \
  "$ROOT/Tests/UnlockGuideCheck.swift" -o "$PROBE/UnlockGuideCheck"
"$PROBE/UnlockGuideCheck"
