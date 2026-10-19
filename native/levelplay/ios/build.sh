#!/usr/bin/env bash
# Builds the LevelPlayBanner Godot iOS plugin (macOS + Xcode only):
#   ios/plugins/LevelPlayBanner/LevelPlayBanner.debug.xcframework
#   ios/plugins/LevelPlayBanner/LevelPlayBanner.release.xcframework
# The .gdip next to them is committed. The SDK side (LevelPlay, ATT) is the local CocoaPod
# native/levelplay/ios/pod, installed into the exported Xcode project by
# native/levelplay/ios/scripts/prepare_xcode_project.sh. See docs/IOS_BUILD.md.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=scripts/common.sh
source "$HERE/scripts/common.sh"

require_macos
ensure_godot_headers
build_gdip_xcframeworks LevelPlayBanner "$ROOT/ios/plugins/LevelPlayBanner" "$HERE/pod/Sources" \
    "$HERE/godot/levelplay_banner.mm" \
    "$HERE/godot/levelplay_banner_module.mm"
