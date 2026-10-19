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
if ! grep -R -q 'LiShiStoreKitBridge' "$EXPORT_DIR/Pods/Target Support Files" ; then
  echo "[prepare] LiShiStoreKitBridge is not in the Pods xcconfigs" >&2
  exit 1
fi
echo "[prepare] Done. Open $(ls -d "$EXPORT_DIR"/*.xcworkspace | head -n 1)"
