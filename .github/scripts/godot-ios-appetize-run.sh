#!/usr/bin/env bash
# Godot 4.7.2 iOS: export Xcode project → unsigned Simulator .app for Appetize.
# No App Store Connect secrets, signing, archive, or TestFlight upload.
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

bash "$SCRIPT_DIR/select-xcode-26.sh"
ci_install_build_tools
mkdir -p "$BUILD_DIR"

# shellcheck source=install-godot-macos.sh
source "$SCRIPT_DIR/install-godot-macos.sh"
GODOT_BIN="${GODOT_BIN:-$CI_GODOT_DIR/Godot.app/Contents/MacOS/Godot}"
export GODOT_BIN
if [ ! -x "$GODOT_BIN" ]; then
  echo "::error::Godot binary missing at $GODOT_BIN" >&2
  exit 1
fi

echo "=== Build iOS plugins (LevelPlayBanner, LiShiStoreKit) ==="
export GODOT_TAG GODOT_SRC
bash "$REPO_ROOT/native/levelplay/ios/build.sh"
bash "$REPO_ROOT/native/storekit/ios/build.sh"
test -d "$REPO_ROOT/ios/plugins/LevelPlayBanner/LevelPlayBanner.release.xcframework"
test -d "$REPO_ROOT/ios/plugins/LiShiStoreKit/LiShiStoreKit.release.xcframework"

export MARKETING_VERSION="${MARKETING_VERSION:-$(ci_read_marketing_version)}"
export IOS_MARKETING_VERSION="$MARKETING_VERSION"
IDENTITY_CODE="$(ci_read_version_code)"
RUN_NUM="${GITHUB_RUN_NUMBER:-1}"
export BUILD_NUMBER="${BUILD_NUMBER:-$RUN_NUM}"
if [ "$BUILD_NUMBER" -lt "$IDENTITY_CODE" ]; then
  export BUILD_NUMBER="$IDENTITY_CODE"
fi
echo "Appetize marketing version: $MARKETING_VERSION, build: $BUILD_NUMBER"
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "BUILD_NUMBER=$BUILD_NUMBER"
    echo "MARKETING_VERSION=$MARKETING_VERSION"
  } >> "$GITHUB_ENV"
fi

ci_godot_import "$GODOT_BIN"

echo "=== Godot iOS export (Xcode project only) ==="
ci_patch_export_presets_team_id
ci_patch_export_presets_ios_versions
mkdir -p "$(dirname "$IOS_EXPORT_ABS")"
"$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "$IOS_EXPORT_PRESET" "$IOS_EXPORT_ABS"

if [ ! -d "$XCODE_PROJECT_ABS" ]; then
  echo "::error::Expected Xcode project at $XCODE_PROJECT_ABS after export." >&2
  ls -la "$(dirname "$XCODE_PROJECT_ABS")" || true
  exit 1
fi

echo "=== CocoaPods, localized ATT strings, shared scheme ==="
bash "$REPO_ROOT/native/levelplay/ios/scripts/prepare_xcode_project.sh" "$(dirname "$XCODE_PROJECT_ABS")"
ci_find_xcode_workspace
ci_patch_xcode_project_versions
ci_discover_xcode_scheme

echo "=== Package Simulator app for Appetize ==="
bash "$SCRIPT_DIR/ios-simulator-appetize.sh"

echo "=== Appetize-only pipeline finished ==="
