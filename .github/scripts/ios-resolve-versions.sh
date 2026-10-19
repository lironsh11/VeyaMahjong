#!/usr/bin/env bash
# Resolve CFBundleVersion (build) and CFBundleShortVersionString (marketing).
# Apple requires CFBundleVersion to be strictly higher than any uploaded build.
# Source this script so BUILD_NUMBER / MARKETING_VERSION export to the caller.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

_ci_int() {
  local v="${1:-0}"
  if [[ "$v" =~ ^[0-9]+$ ]]; then
    echo "$v"
  else
    echo 0
  fi
}

IDENTITY_NAME="$(ci_read_marketing_version)"
IDENTITY_CODE="$(_ci_int "$(ci_read_version_code)")"

ci_install_cli_tools
ci_verify_asc_secrets

APPLE_ID="${APP_STORE_APPLE_ID:-}"
if [ -z "$APPLE_ID" ]; then
  echo "APP_STORE_APPLE_ID unset — looking up App Store Connect app for $BUNDLE_ID..."
  APPLE_ID="$(
    app-store-connect apps --json 2>/dev/null | python3 -c "
import json, sys
bundle = sys.argv[1]
raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    sys.exit(0)
if isinstance(data, list):
    apps = data
elif isinstance(data, dict):
    apps = data.get('data') or data.get('apps') or []
else:
    apps = []
for app in apps:
    if not isinstance(app, dict):
        continue
    attrs = app.get('attributes') if isinstance(app.get('attributes'), dict) else app
    bid = str(attrs.get('bundleId') or attrs.get('bundle_id') or '')
    if bid == bundle:
        print(app.get('id') or attrs.get('id') or '')
        break
" "$BUNDLE_ID" || true
  )"
  if [ -n "$APPLE_ID" ]; then
    echo "Looked up App Store Apple ID $APPLE_ID for $BUNDLE_ID"
    export APP_STORE_APPLE_ID="$APPLE_ID"
  elif [ -n "${GITHUB_ACTIONS:-}" ]; then
    echo "::warning::Could not resolve APP_STORE_APPLE_ID for $BUNDLE_ID. Create the app in App Store Connect, or set APP_STORE_APPLE_ID. Build number falls back to the run number."
  else
    echo "WARN: Could not resolve APP_STORE_APPLE_ID for $BUNDLE_ID. Create the app in App Store Connect if upload fails."
  fi
fi

latest=0
if [ -n "${APPLE_ID:-}" ]; then
  echo "Querying latest uploaded iOS build for App Store Connect app id $APPLE_ID..."
  parsed="$(_ci_int "$(app-store-connect get-latest-testflight-build-number "$APPLE_ID" --platform IOS 2>/dev/null | tail -n 1 || true)")"
  if [ "$parsed" -eq 0 ]; then
    parsed="$(_ci_int "$(app-store-connect get-latest-testflight-build-number "$APPLE_ID" 2>/dev/null | tail -n 1 || true)")"
  fi
  store_parsed="$(_ci_int "$(app-store-connect get-latest-app-store-build-number "$APPLE_ID" --platform IOS 2>/dev/null | tail -n 1 || true)")"
  if [ "$store_parsed" -gt "$parsed" ]; then
    parsed="$store_parsed"
  fi
  latest="$parsed"
  if [ "$latest" -gt 0 ]; then
    echo "Latest uploaded iOS build number: $latest"
  else
    echo "WARN: could not parse latest uploaded build number; falling back to run number / floor"
  fi
fi

FLOOR="${IOS_BUILD_NUMBER_FLOOR:-}"
FLOOR="$(_ci_int "$FLOOR")"
if [ "$FLOOR" -lt 1 ]; then
  FLOOR="$IDENTITY_CODE"
  if [ "$FLOOR" -lt 1 ]; then
    FLOOR=1
  fi
fi

OFFSET="${IOS_BUILD_NUMBER_OFFSET:-0}"
OFFSET="$(_ci_int "$OFFSET")"
RUN_NUM="$(_ci_int "${GITHUB_RUN_NUMBER:-${PROJECT_BUILD_NUMBER:-1}}")"
existing="$(_ci_int "${BUILD_NUMBER:-0}")"

candidate=$((RUN_NUM + OFFSET))
if [ "$existing" -gt "$candidate" ]; then
  candidate="$existing"
fi
if [ "$latest" -gt 0 ]; then
  next=$((latest + 1))
  if [ "$next" -gt "$candidate" ]; then
    candidate="$next"
  fi
fi
if [ "$candidate" -lt "$FLOOR" ]; then
  candidate="$FLOOR"
fi
if [ "$latest" -gt 0 ] && [ "$candidate" -le "$latest" ]; then
  candidate=$((latest + 1))
fi

export BUILD_NUMBER="$candidate"
MARKETING="${IOS_MARKETING_VERSION:-${MARKETING_VERSION:-$IDENTITY_NAME}}"
export MARKETING_VERSION="$MARKETING"
export IOS_MARKETING_VERSION="$MARKETING"

echo "Resolved BUILD_NUMBER=$BUILD_NUMBER (floor=$FLOOR, run=$RUN_NUM offset=$OFFSET existing=$existing tf_latest=$latest)"
echo "Resolved MARKETING_VERSION=$MARKETING_VERSION"

if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "BUILD_NUMBER=$BUILD_NUMBER"
    echo "MARKETING_VERSION=$MARKETING_VERSION"
    echo "IOS_MARKETING_VERSION=$IOS_MARKETING_VERSION"
    if [ -n "${APPLE_ID:-}" ]; then
      echo "APP_STORE_APPLE_ID=$APPLE_ID"
    fi
  } >> "$GITHUB_ENV"
fi
