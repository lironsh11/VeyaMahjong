#!/usr/bin/env bash
# Builds LiShi Mahjong's own iOS export template (tools/godot_build/lishi_ios_custom.py) from the
# Godot source the iOS plugins compile against, so engine and plugins share generated headers.
# Cached by Godot tag + profile hash. Prints the directory holding libgodot.ios.*.a and the
# Xcode project skeleton (ios_xcode/) that Godot expects in a custom template.
#
# Run on macOS after install-godot-macos.sh and BEFORE the plugin builds. Takes 25-40 min on a
# Mac mini M2 the first time; cached runs take seconds.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROFILE="$REPO_ROOT/tools/godot_build/lishi_ios_custom.py"
GODOT_TAG="${GODOT_TAG:?GODOT_TAG is required (e.g. 4.7.2-stable)}"
GODOT_SRC="${GODOT_SRC:-$HOME/.cache/lishi-godot/$GODOT_TAG}"

hash="$( (echo "$GODOT_TAG"; cat "$PROFILE") | shasum -a 256 | cut -c1-16)"
OUT="$HOME/.cache/lishi-godot/templates/$hash"
if [[ -f "$OUT/godot_ios.zip" ]]; then
  echo "Custom iOS template cached: $OUT" >&2
  echo "$OUT"
  exit 0
fi

if [[ ! -f "$GODOT_SRC/SConstruct" ]]; then
  mkdir -p "$(dirname "$GODOT_SRC")"
  git clone --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$GODOT_SRC"
fi
command -v scons >/dev/null || pip3 install --quiet scons

jobs="$(sysctl -n hw.ncpu)"
cd "$GODOT_SRC"
rm -f bin/godot_ios.zip
echo "=== scons template_debug (profile $(basename "$PROFILE")) ===" >&2
scons platform=ios target=template_debug arch=arm64 profile="$PROFILE" -j"$jobs" >&2
echo "=== scons template_release + bundle ===" >&2
# generate_bundle=yes packs both libraries into bin/godot_ios.zip like the official template.
scons platform=ios target=template_release arch=arm64 profile="$PROFILE" generate_bundle=yes -j"$jobs" >&2 || true

mkdir -p "$OUT"
if [[ -f bin/godot_ios.zip ]]; then
  cp bin/godot_ios.zip "$OUT/godot_ios.zip"
else
  # Fallback: package by hand (the official layout: Xcode skeleton + one xcframework per target).
  echo "generate_bundle produced no zip; packaging manually" >&2
  stage="$(mktemp -d)"
  cp -R misc/dist/apple_embedded_xcode/. "$stage/" 2>/dev/null || cp -R misc/dist/ios_xcode/. "$stage/"
  for target in template_release template_debug; do
    lib="$(ls bin/libgodot.ios."$target".arm64*.a | head -n1)"
    [[ -f "$lib" ]] || { echo "::error::missing $target library" >&2; exit 1; }
    dest="libgodot.ios.${target#template_}.xcframework/ios-arm64/libgodot.a"
    mkdir -p "$stage/$(dirname "$dest")"
    cp "$lib" "$stage/$dest"
  done
  (cd "$stage" && zip -qr "$OUT/godot_ios.zip" .)
  rm -rf "$stage"
fi
echo "Custom iOS template built: $OUT/godot_ios.zip ($(du -h "$OUT/godot_ios.zip" | cut -f1))" >&2
echo "$OUT"
