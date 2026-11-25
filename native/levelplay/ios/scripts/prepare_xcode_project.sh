#!/usr/bin/env bash
# Run after `godot --export-debug "iOS" <dir>/LiShiMahjong.ipa` (export_project_only=true) on a
# Mac: adds $(inherited), localized InfoPlist.strings and a shared scheme to the generated
# project, writes the Podfile (LevelPlay + Meta adapter + the two local bridge pods) and
# runs `pod install`. Afterwards open <dir>/LiShiMahjong.xcworkspace (not the .xcodeproj).
#
#   native/levelplay/ios/scripts/prepare_xcode_project.sh <export_dir>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
EXPORT_DIR="${1:?usage: prepare_xcode_project.sh <export_dir>}"
EXPORT_DIR="$(cd "$EXPORT_DIR" && pwd)"

command -v pod >/dev/null || { echo "CocoaPods not found: brew install cocoapods" >&2; exit 1; }

ruby "$HERE/prepare_xcode_project.rb" "$EXPORT_DIR" "$ROOT"
(cd "$EXPORT_DIR" && pod install --repo-update)
# FBAudienceNetwork's xcframework has both an arm64 device slice and an arm64
# simulator slice. CocoaPods puts the device folder on FRAMEWORK_SEARCH_PATHS
# first, so an arm64 simulator link loads the device dylib and fails. Drop only
# the device folder; leave ios-arm64_x86_64-simulator in place.
if [ "${LISHI_SIMULATOR_ARM64:-}" = "1" ]; then
  python3 - "$EXPORT_DIR/Pods" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
pat = re.compile(r'"[^"]*?\.xcframework/ios-arm64"')
n = 0
for cfg in root.rglob("*.xcconfig"):
    text = cfg.read_text()
    new, k = pat.subn("", text)
    if k:
        cfg.write_text(new)
        n += k
        print(f"[prepare] {cfg.name}: removed {k} device xcframework path(s)")
print(f"[prepare] simulator link: removed {n} device slice search path(s)")
PY
fi
if ! grep -R -q 'LiShiStoreKitBridge' "$EXPORT_DIR/Pods/Target Support Files" ; then
  echo "[prepare] LiShiStoreKitBridge is not in the Pods xcconfigs" >&2
  exit 1
fi
echo "[prepare] Done. Open $(ls -d "$EXPORT_DIR"/*.xcworkspace | head -n 1)"
