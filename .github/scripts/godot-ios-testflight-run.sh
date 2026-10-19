#!/usr/bin/env bash
# Godot 4.7.2 iOS: plugins → export Xcode project → sign → archive → IPA.
# Publish is host-specific:
#   Codemagic → codemagic.yaml publishing.app_store_connect
#   GitHub Actions → ios-publish-testflight.sh
set -euxo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

bash "$SCRIPT_DIR/select-xcode-26.sh"
ci_install_build_tools
ci_install_cli_tools
ci_verify_asc_secrets
export APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY

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

echo "=== Resolve iOS build and marketing version ==="
# shellcheck source=ios-resolve-versions.sh
source "$SCRIPT_DIR/ios-resolve-versions.sh"
echo "Marketing version: $MARKETING_VERSION, build: $BUILD_NUMBER"

ci_godot_import "$GODOT_BIN"

echo "=== Godot iOS export (Xcode project) ==="
ci_patch_export_presets_team_id
ci_patch_export_presets_ios_versions
mkdir -p "$(dirname "$IOS_EXPORT_ABS")"
set +e
"$GODOT_BIN" --headless --path "$REPO_ROOT" --export-release "$IOS_EXPORT_PRESET" "$IOS_EXPORT_ABS" \
  > "$BUILD_DIR/godot-export.log" 2>&1
EXPORT_STATUS=$?
set -e
if [ "$EXPORT_STATUS" -ne 0 ]; then
  echo "::error::Godot iOS export failed with exit code $EXPORT_STATUS" >&2
  tail -n 80 "$BUILD_DIR/godot-export.log" >&2 || true
  exit "$EXPORT_STATUS"
fi
tail -n 40 "$BUILD_DIR/godot-export.log" || true

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

fetch_signing_files() {
  keychain initialize
  openssl genrsa -out /tmp/certificate_key.pem 2048
  app-store-connect fetch-signing-files "$BUNDLE_ID" \
    --type IOS_APP_STORE \
    --create \
    --certificate-key @file:/tmp/certificate_key.pem \
    --verbose
  keychain add-certificates
  xcode-project use-profiles \
    --project "$XCODE_PROJECT_ABS" \
    --archive-method app-store \
    --export-options-plist "$HOME/export_options.plist" \
    --code-signing-setup-verbose-logging \
    --verbose
}

# Apple caps distribution certificates. Same purge as Riftstrike: revoke, then create one.
purge_distribution_certs() {
  echo "=== Purge Distribution certificates ==="
  local cert_type json ids_file cert_id
  ids_file="$(mktemp)"
  for cert_type in DISTRIBUTION IOS_DISTRIBUTION; do
    json=$(app-store-connect certificates list --type "$cert_type" --json 2>/dev/null || true)
    if [ -z "${json:-}" ]; then
      continue
    fi
    printf '%s' "$json" | python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    raise SystemExit(0)
if isinstance(data, dict):
    data = data.get("data") or data.get("certificates") or []
if not isinstance(data, list):
    raise SystemExit(0)
for item in data:
    if isinstance(item, dict) and item.get("id"):
        print(item["id"])
' > "$ids_file" || true
    while read -r cert_id; do
      [ -z "$cert_id" ] && continue
      echo "Revoking $cert_type certificate: $cert_id"
      app-store-connect certificates delete "$cert_id" --ignore-not-found || true
    done < "$ids_file"
  done
  rm -f "$ids_file"
}

echo "=== Fetch and install code signing files ==="
cp "$REPO_ROOT/ios/exportOptions.plist" "$HOME/export_options.plist"
purge_distribution_certs
fetch_signing_files
ci_patch_xcode_project_versions

if ! grep -q 'PROVISIONING_PROFILE' "$XCODE_PROJECT_ABS/project.pbxproj"; then
  echo "::error::xcode-project use-profiles did not set PROVISIONING_PROFILE." >&2
  ls -la "$HOME/Library/MobileDevice/Provisioning Profiles" 2>/dev/null || true
  exit 1
fi

echo "=== Resolve Swift packages ==="
# shellcheck disable=SC2046
xcodebuild -resolvePackageDependencies \
  $(ci_xcode_container_args) \
  -scheme "$XCODE_SCHEME" \
  -derivedDataPath "$BUILD_DIR/DerivedData" || true

echo "=== Archive ==="
mkdir -p "$BUILD_DIR/DerivedData"
set +e
# shellcheck disable=SC2046
xcodebuild archive \
  $(ci_xcode_container_args) \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$BUILD_DIR/build.xcarchive" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -jobs "$(sysctl -n hw.ncpu)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="$APPLE_DEVELOPMENT_TEAM" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | tee "$BUILD_DIR/xcodebuild-archive.log"
ARCHIVE_STATUS=${PIPESTATUS[0]}
set -e
if [ "$ARCHIVE_STATUS" -ne 0 ]; then
  echo "::error::xcodebuild archive failed with exit code $ARCHIVE_STATUS"
  grep -E 'error:|fatal error:|BUILD FAILED|Undefined symbols|clang: error|Swift Compiler Error|provisioning profile' \
    "$BUILD_DIR/xcodebuild-archive.log" | tail -n 80 || true
  tail -n 30 "$BUILD_DIR/xcodebuild-archive.log" || true
  exit "$ARCHIVE_STATUS"
fi

APP_PATH="$BUILD_DIR/build.xcarchive/Products/Applications/${XCODE_SCHEME}.app"
if [ ! -d "$APP_PATH" ]; then
  APP_PATH=""
  for candidate in "$BUILD_DIR/build.xcarchive/Products/Applications/"*.app; do
    if [ -d "$candidate" ]; then
      APP_PATH="$candidate"
      break
    fi
  done
fi
test -n "$APP_PATH"
test -d "$APP_PATH"
ARCHIVED_BUNDLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
ARCHIVED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Info.plist")"
ARCHIVED_MARKETING="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Info.plist")"
echo "Archived app: $APP_PATH (id=$ARCHIVED_BUNDLE CFBundleShortVersionString=$ARCHIVED_MARKETING CFBundleVersion=$ARCHIVED_BUILD)"
if [ "$ARCHIVED_BUNDLE" != "$BUNDLE_ID" ]; then
  echo "::error::Archived bundle id is '$ARCHIVED_BUNDLE', expected '$BUNDLE_ID'." >&2
  exit 1
fi
if [ "$ARCHIVED_BUILD" != "$BUILD_NUMBER" ]; then
  echo "::error::Archived CFBundleVersion is '$ARCHIVED_BUILD', expected '$BUILD_NUMBER'." >&2
  exit 1
fi
if [ "$ARCHIVED_MARKETING" != "$MARKETING_VERSION" ]; then
  echo "::error::Archived CFBundleShortVersionString is '$ARCHIVED_MARKETING', expected '$MARKETING_VERSION'." >&2
  exit 1
fi
/usr/libexec/PlistBuddy -c 'Print :NSUserTrackingUsageDescription' "$APP_PATH/Info.plist" >/dev/null

echo "=== Export IPA ==="
mkdir -p "$BUILD_DIR/ios/ipa"
xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/build.xcarchive" \
  -exportPath "$BUILD_DIR/ios/ipa" \
  -exportOptionsPlist "$HOME/export_options.plist"

echo "=== iOS TestFlight pipeline finished ==="
ls -la "$BUILD_DIR/ios/ipa"/*.ipa
