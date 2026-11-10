#!/bin/zsh
# Check menu icon drawing without shielding displays or blocking input.
set -euo pipefail
ROOT=${0:A:h:h}
APP=${1:-"$ROOT/build/Tenmaku.app"}
PROBE=$(mktemp -d "${TMPDIR:-/tmp}/tenmaku-status-menu.XXXXXX")
trap 'rm -rf "$PROBE"' EXIT
swiftc -swift-version 6 -target "$(uname -m)-apple-macos13.0" -module-cache-path "$PROBE/ModuleCache" \
  "$ROOT/Sources/Tenmaku/Strings.swift" "$ROOT/Sources/Tenmaku/StatusMenu.swift" \
  "$ROOT/Tests/StatusMenuAnimationCheck.swift" -o "$PROBE/StatusMenuAnimationCheck"
"$PROBE/StatusMenuAnimationCheck" "$APP"
