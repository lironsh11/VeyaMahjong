#!/usr/bin/env bash
# Builds the LiShiStoreKit Godot iOS plugin (macOS + Xcode only):
#   ios/plugins/LiShiStoreKit/LiShiStoreKit.debug.xcframework
#   ios/plugins/LiShiStoreKit/LiShiStoreKit.release.xcframework
# The StoreKit 2 code is Swift in the local CocoaPod native/storekit/ios/pod, installed into the
# exported Xcode project by native/levelplay/ios/scripts/prepare_xcode_project.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../../levelplay/ios/scripts/common.sh
source "$ROOT/native/levelplay/ios/scripts/common.sh"

require_macos
ensure_godot_headers
build_gdip_xcframeworks LiShiStoreKit "$ROOT/ios/plugins/LiShiStoreKit" "$HERE/godot" \
    "$HERE/godot/lishi_storekit.mm"
