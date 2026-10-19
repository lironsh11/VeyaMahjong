#!/usr/bin/env bash
# Shared CI environment for LiShi Mahjong (Godot iOS → TestFlight).
# Used by GitHub Actions and Codemagic (codemagic.yaml → ios-testflight).
set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export REPO_ROOT

export BUNDLE_ID="${BUNDLE_ID:-com.lishimahjong.app}"
# Same Apple team as Riftstrike / PEND. Not a secret.
export APPLE_DEVELOPMENT_TEAM="${APPLE_DEVELOPMENT_TEAM:-7BLH4NFZDD}"
export GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
export GODOT_TAG="${GODOT_TAG:-${GODOT_VERSION}-stable}"
export IOS_EXPORT_PRESET="${IOS_EXPORT_PRESET:-iOS}"
export IOS_EXPORT_PATH="${IOS_EXPORT_PATH:-build/ios/LiShiMahjong.ipa}"
export XCODE_PROJECT="${XCODE_PROJECT:-build/ios/LiShiMahjong.xcodeproj}"
export XCODE_SCHEME="${XCODE_SCHEME:-LiShiMahjong}"
# GHA sets BUILD_DIR to <workspace>/build. Codemagic sets $CM_BUILD_DIR/build.
export BUILD_DIR="${BUILD_DIR:-${CM_BUILD_DIR:+$CM_BUILD_DIR/build}}"
export BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
# Codemagic may inject PROJECT_BUILD_NUMBER. ios-resolve-versions.sh raises it
# above the latest App Store Connect build, so a missing value is fine.
if [ -n "${CM_BUILD_ID:-}" ]; then
  if [ -z "${BUILD_NUMBER:-}" ] || [ "${BUILD_NUMBER}" = "\$PROJECT_BUILD_NUMBER" ]; then
    BUILD_NUMBER="${PROJECT_BUILD_NUMBER:-1}"
  fi
  export BUILD_NUMBER
  echo "Codemagic BUILD_NUMBER=$BUILD_NUMBER"
else
  export BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
fi
export ASC_KEY_FILE="${ASC_KEY_FILE:-/tmp/AuthKey.p8}"

export CI_VENV="${CI_VENV:-$REPO_ROOT/.ci-venv}"
export CI_GODOT_DIR="${CI_GODOT_DIR:-$REPO_ROOT/.ci-godot}"
export GODOT_BIN="${GODOT_BIN:-$CI_GODOT_DIR/Godot.app/Contents/MacOS/Godot}"
export GODOT_SRC="${GODOT_SRC:-$HOME/.cache/lishi-godot/$GODOT_TAG}"
export PATH="$CI_VENV/bin:$PATH"
export XCODE_WORKSPACE_ABS="${XCODE_WORKSPACE_ABS:-}"

ci_abs_path() {
  local p="$1"
  if [[ "$p" != /* ]]; then
    echo "$REPO_ROOT/$p"
  else
    echo "$p"
  fi
}

export XCODE_PROJECT_ABS="$(ci_abs_path "$XCODE_PROJECT")"
export IOS_EXPORT_ABS="$(ci_abs_path "$IOS_EXPORT_PATH")"

ci_read_marketing_version() {
  python3 - "$REPO_ROOT/project.godot" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'(?m)^config/version="([^"]+)"', text)
print(m.group(1) if m else "0.1.0")
PY
}

ci_read_version_code() {
  python3 - "$REPO_ROOT/export_presets.cfg" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'application/version="(\d+)"', text)
print(m.group(1) if m else "1")
PY
}

# Godot refuses iOS export when app_store_team_id is empty; git keeps "" .
ci_patch_export_presets_team_id() {
  local team="${APPLE_DEVELOPMENT_TEAM:?APPLE_DEVELOPMENT_TEAM is required for Godot iOS export}"
  python3 - "$REPO_ROOT/export_presets.cfg" "$team" <<'PY'
import sys
path, team = sys.argv[1:]
text = open(path, encoding="utf-8").read()
needle = 'application/app_store_team_id=""'
have = f'application/app_store_team_id="{team}"'
if have in text:
    print(f"export_presets.cfg already has app_store_team_id={team}")
    raise SystemExit(0)
if needle not in text:
    raise SystemExit(
        f"ERROR: export_presets.cfg app_store_team_id is not empty and not {team}; refusing to patch."
    )
text = text.replace(needle, have, 1)
open(path, "w", encoding="utf-8", newline="\n").write(text)
print(f"Patched export_presets.cfg app_store_team_id for CI Godot export.")
PY
}

ci_patch_export_presets_ios_versions() {
  local ver="${BUILD_NUMBER:?BUILD_NUMBER is required to patch iOS application/version}"
  local marketing="${MARKETING_VERSION:-$(ci_read_marketing_version)}"
  python3 - "$REPO_ROOT/export_presets.cfg" "$ver" "$marketing" <<'PY'
import re, sys
path, ver, marketing = sys.argv[1:]
text = open(path, encoding="utf-8").read()
text, n_ver = re.subn(
    r'application/version="[^"]*"', f'application/version="{ver}"', text, count=1
)
text, n_name = re.subn(
    r'application/short_version="[^"]*"',
    f'application/short_version="{marketing}"',
    text,
    count=1,
)
if n_ver != 1 or n_name != 1:
    raise SystemExit(f"expected to patch iOS version once (version={n_ver} short_version={n_name})")
open(path, "w", encoding="utf-8", newline="\n").write(text)
print(f"Patched export_presets.cfg iOS application/version={ver} short_version={marketing}")
PY
}

# Godot 4 iOS projects generate Info.plist from CURRENT_PROJECT_VERSION.
ci_patch_xcode_project_versions() {
  local pbx="$XCODE_PROJECT_ABS/project.pbxproj"
  local ver="${BUILD_NUMBER:?}"
  local marketing="${MARKETING_VERSION:-$(ci_read_marketing_version)}"
  if [ ! -f "$pbx" ]; then
    echo "::warning::No project.pbxproj at $pbx; relying on xcodebuild CURRENT_PROJECT_VERSION."
    return 0
  fi
  python3 - "$pbx" "$ver" "$marketing" <<'PY'
import re, sys
path, ver, marketing = sys.argv[1:]
text = open(path, encoding="utf-8").read()
text, n_ver = re.subn(r"CURRENT_PROJECT_VERSION = [^;]+;", f"CURRENT_PROJECT_VERSION = {ver};", text)
text, n_name = re.subn(r"MARKETING_VERSION = [^;]+;", f"MARKETING_VERSION = {marketing};", text)
open(path, "w", encoding="utf-8", newline="\n").write(text)
print(f"Patched pbxproj CURRENT_PROJECT_VERSION ({n_ver}) MARKETING_VERSION ({n_name}) -> {ver} / {marketing}")
PY
}

ci_write_asc_key_file() {
  : "${APP_STORE_CONNECT_PRIVATE_KEY:?APP_STORE_CONNECT_PRIVATE_KEY is required}"
  printf '%s\n' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$ASC_KEY_FILE"
}

ci_verify_asc_secrets() {
  local v
  for v in APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_KEY_IDENTIFIER APP_STORE_CONNECT_PRIVATE_KEY; do
    if [ -z "${!v:-}" ]; then
      echo "ERROR: $v is empty." >&2
      exit 1
    fi
  done
  ci_write_asc_key_file
  local key_lines
  key_lines=$(wc -l < "$ASC_KEY_FILE" | tr -d ' ')
  echo "Issuer ID length: ${#APP_STORE_CONNECT_ISSUER_ID}, Key ID: $APP_STORE_CONNECT_KEY_IDENTIFIER, .p8 lines: $key_lines"
  if [ "$key_lines" -lt 4 ]; then
    echo "ERROR: Private key looks like one line (broken paste)." >&2
    exit 1
  fi
  if ! grep -q 'BEGIN PRIVATE KEY' "$ASC_KEY_FILE"; then
    echo "ERROR: Missing -----BEGIN PRIVATE KEY----- in .p8 file." >&2
    exit 1
  fi
}

ci_install_cli_tools() {
  if [ -x "$CI_VENV/bin/app-store-connect" ]; then
    echo "Codemagic CLI tools already installed in $CI_VENV"
    return 0
  fi
  python3 -m venv "$CI_VENV"
  "$CI_VENV/bin/pip" install --upgrade pip
  "$CI_VENV/bin/pip" install codemagic-cli-tools
  command -v app-store-connect >/dev/null
  command -v keychain >/dev/null
  command -v xcode-project >/dev/null
  echo "Codemagic CLI tools installed."
}

ci_install_build_tools() {
  if ! command -v scons >/dev/null 2>&1; then
    python3 -m pip install --break-system-packages scons || python3 -m pip install scons
  fi
  if ! command -v scons >/dev/null 2>&1; then
    local py_scripts
    py_scripts="$(python3 -c 'import sysconfig; print(sysconfig.get_path("scripts"))')"
    export PATH="$py_scripts:$PATH"
  fi
  command -v scons >/dev/null
  if ! command -v pod >/dev/null 2>&1; then
    brew install cocoapods
  fi
  command -v pod >/dev/null
  # prepare_xcode_project.rb needs the xcodeproj gem (ships with CocoaPods' Ruby).
  # Do not set GEM_HOME here: that would hide the CocoaPods gem from `pod`.
  if ! ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
    gem install xcodeproj --no-document || gem install --user-install xcodeproj --no-document
  fi
  ruby -e 'require "xcodeproj"'
}

ci_discover_xcode_scheme() {
  local discovered=""
  if [ -n "${XCODE_WORKSPACE_ABS:-}" ] && [ -d "$XCODE_WORKSPACE_ABS" ]; then
    discovered=$(xcodebuild -list -workspace "$XCODE_WORKSPACE_ABS" -json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
schemes = data.get('workspace', {}).get('schemes', [])
for s in schemes:
    if not str(s).startswith('Pods'):
        print(s)
        break
" 2>/dev/null || true)
    if [ -n "$discovered" ]; then
      export XCODE_SCHEME="$discovered"
      echo "Discovered Xcode scheme (workspace): $XCODE_SCHEME"
      if [ -n "${GITHUB_ENV:-}" ]; then
        echo "XCODE_SCHEME=$XCODE_SCHEME" >> "$GITHUB_ENV"
      fi
      return 0
    fi
  fi
  if [ ! -d "$XCODE_PROJECT_ABS" ]; then
    echo "ERROR: Xcode project not found: $XCODE_PROJECT_ABS" >&2
    exit 1
  fi
  discovered=$(xcodebuild -list -project "$XCODE_PROJECT_ABS" -json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
schemes = data.get('project', {}).get('schemes', [])
print(schemes[0] if schemes else '')
" 2>/dev/null || true)
  if [ -z "$discovered" ]; then
    discovered=$(xcodebuild -list -project "$XCODE_PROJECT_ABS" 2>/dev/null | awk '/Schemes:/{flag=1;next} flag && NF{print $1; exit}')
  fi
  if [ -n "$discovered" ]; then
    export XCODE_SCHEME="$discovered"
    echo "Discovered Xcode scheme: $XCODE_SCHEME"
  else
    echo "Using default Xcode scheme: $XCODE_SCHEME"
  fi
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "XCODE_SCHEME=$XCODE_SCHEME" >> "$GITHUB_ENV"
  fi
}

ci_xcode_container_args() {
  if [ -n "${XCODE_WORKSPACE_ABS:-}" ] && [ -d "$XCODE_WORKSPACE_ABS" ]; then
    echo "-workspace" "$XCODE_WORKSPACE_ABS"
  else
    echo "-project" "$XCODE_PROJECT_ABS"
  fi
}

ci_find_xcode_workspace() {
  local ios_dir workspace="" candidate
  ios_dir="$(dirname "$XCODE_PROJECT_ABS")"
  for candidate in "$ios_dir"/*.xcworkspace; do
    if [ -d "$candidate" ]; then
      workspace="$candidate"
      break
    fi
  done
  if [ -z "$workspace" ]; then
    echo "ERROR: Expected CocoaPods xcworkspace under $ios_dir" >&2
    ls -la "$ios_dir" >&2 || true
    exit 1
  fi
  export XCODE_WORKSPACE_ABS="$workspace"
  echo "XCODE_WORKSPACE_ABS=$XCODE_WORKSPACE_ABS"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "XCODE_WORKSPACE_ABS=$XCODE_WORKSPACE_ABS" >> "$GITHUB_ENV"
  fi
}

# Godot --import can stay alive after the import finishes. Wait, then stop it.
ci_godot_import() {
  local godot="${1:?}"
  echo "=== Godot first import (bounded) ==="
  set +e
  "$godot" --headless --path "$REPO_ROOT" --import > "$BUILD_DIR/godot-import.log" 2>&1 &
  local pid=$! waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge 480 ]; then
      echo "Godot import still running after ${waited}s; stopping it and continuing to export."
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      set -e
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  wait "$pid" 2>/dev/null || true
  set -e
  echo "Godot import exited after about ${waited}s."
}
