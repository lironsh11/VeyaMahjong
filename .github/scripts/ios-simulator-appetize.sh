#!/usr/bin/env bash
# Unsigned iOS Simulator .app for Appetize. Something.app must sit at the zip root.
# Matches the simulator architecture used by .github/workflows/ios.yml (arm64).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

: "${XCODE_PROJECT_ABS:?XCODE_PROJECT_ABS is required (Godot iOS export must have succeeded)}"
if [ ! -d "$XCODE_PROJECT_ABS" ]; then
  echo "ERROR: Xcode project not found at $XCODE_PROJECT_ABS" >&2
  exit 1
fi

ci_discover_xcode_scheme
: "${XCODE_SCHEME:?}"

SIMULATOR_DERIVED_DATA="${SIMULATOR_DERIVED_DATA:-$BUILD_DIR/DerivedDataSimulator}"
APPETIZE_STAGING_DIR="${APPETIZE_STAGING_DIR:-$BUILD_DIR/appetize-staging}"
APPETIZE_ZIP="${APPETIZE_ZIP:-$BUILD_DIR/LiShiMahjong-simulator-appetize.zip}"

echo "=== Build iOS Simulator app for Appetize ==="
# shellcheck disable=SC2046
xcodebuild build \
  $(ci_xcode_container_args) \
  -scheme "$XCODE_SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -derivedDataPath "$SIMULATOR_DERIVED_DATA" \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  COMPILER_INDEX_STORE_ENABLE=NO

APP_PATH=""
while IFS= read -r candidate; do
  case "$candidate" in
    *iphonesimulator*) APP_PATH="$candidate"; break ;;
  esac
done < <(find "$SIMULATOR_DERIVED_DATA/Build/Products" -type d -name '*.app' 2>/dev/null || true)
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
  echo "ERROR: Could not find a Simulator .app" >&2
  find "$SIMULATOR_DERIVED_DATA" -name '*.app' 2>/dev/null || true
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
echo "Simulator app: $APP_PATH"

rm -rf "$APPETIZE_STAGING_DIR"
mkdir -p "$APPETIZE_STAGING_DIR"
cp -R "$APP_PATH" "$APPETIZE_STAGING_DIR/"
STAGED_APP="$APPETIZE_STAGING_DIR/$APP_NAME"
export APPETIZE_APP_PATH="$STAGED_APP"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "APPETIZE_APP_PATH=$STAGED_APP"
    echo "APPETIZE_ZIP=$APPETIZE_ZIP"
  } >> "$GITHUB_ENV"
fi

rm -f "$APPETIZE_ZIP"
(
  cd "$APPETIZE_STAGING_DIR"
  zip -ry "$APPETIZE_ZIP" "$APP_NAME"
)
unzip -l "$APPETIZE_ZIP" > "$BUILD_DIR/appetize-zip-listing.txt"
if ! grep -q "${APP_NAME}/Info.plist" "$BUILD_DIR/appetize-zip-listing.txt"; then
  echo "ERROR: Zip does not contain ${APP_NAME}/Info.plist at root" >&2
  exit 1
fi
echo "Appetize zip: $APPETIZE_ZIP"
ls -la "$STAGED_APP"
echo "=== Appetize package ready ==="
