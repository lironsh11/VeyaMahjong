#!/usr/bin/env bash
# Unsigned iOS Simulator .app for Appetize. Something.app must sit at the zip root.
#
# APPETIZE_WITH_ADS=1: arm64 simulator + the real LevelPlay/Meta pods. Appetize's
# Apple Silicon hosts run that binary, which is how ads show up there. The stock
# Godot template's "arm64" simulator file is actually x86_64, so the caller must
# already have installed an arm64 slice (install-godot-arm64-simulator-slice.sh).
# Without the flag this stays the x86_64 stub-ads build used beside TestFlight.
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

if [ "${APPETIZE_WITH_ADS:-}" = "1" ]; then
  APPETIZE_ARCH=arm64
  APPETIZE_EXCLUDED_ARCH=x86_64
  echo "=== Build iOS Simulator app for Appetize (arm64 + LevelPlay/Meta) ==="
else
  APPETIZE_ARCH=x86_64
  APPETIZE_EXCLUDED_ARCH=arm64
  echo "=== Build iOS Simulator app for Appetize (x86_64 + stub ads) ==="
fi
# shellcheck disable=SC2046
xcodebuild build \
  $(ci_xcode_container_args) \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -sdk iphonesimulator \
  -derivedDataPath "$SIMULATOR_DERIVED_DATA" \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  ARCHS="$APPETIZE_ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  "EXCLUDED_ARCHS=$APPETIZE_EXCLUDED_ARCH" \
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
BIN="$STAGED_APP/$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$STAGED_APP/Info.plist")"
file "$BIN"
if ! file "$BIN" | grep -q "$APPETIZE_ARCH"; then
  echo "ERROR: Simulator binary is not $APPETIZE_ARCH." >&2
  exit 1
fi
if [ "${APPETIZE_WITH_ADS:-}" = "1" ]; then
  if ! find "$STAGED_APP" \( -iname '*IronSource*' -o -iname '*FBAudienceNetwork*' -o -iname '*UnityAds*' \) | grep -q . \
    && ! nm -gU "$BIN" | grep -E -q 'IronSource|LevelPlay|FBAd|FBAudience'; then
    echo "ERROR: arm64 Appetize app has no IronSource/Meta binary. Ads will not show." >&2
    find "$STAGED_APP" -iname '*.framework' -o -iname '*.a' >&2 || true
    exit 1
  fi
  echo "Ads SDK is linked into the Appetize app."
fi
echo "Appetize zip: $APPETIZE_ZIP"
ls -la "$STAGED_APP"
echo "=== Appetize package ready ==="
