#!/usr/bin/env bash
# Official Godot iOS templates advertise an arm64 simulator slice but ship x86_64 only
# (godotengine/godot#118161). IronSource and Meta have no x86_64 simulator slice, so an
# Appetize zip that can show ads has to link arm64. This builds that missing libgodot
# (and libgodot_camera, when the module exists) from the same tag the plugins use.
#
# Prints the directory of *.arm64.simulator.a files. Cached across CI runs.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci-env.sh
source "$SCRIPT_DIR/ci-env.sh"

GODOT_TAG="${GODOT_TAG:?GODOT_TAG is required}"
GODOT_SRC="${GODOT_SRC:-$HOME/.cache/lishi-godot/$GODOT_TAG}"
OUT="${GODOT_SIM_ARM64_DIR:-$HOME/.cache/lishi-godot/sim-arm64-libs/$GODOT_TAG}"
mkdir -p "$OUT"

if [[ -f "$OUT/libgodot.ios.template_release.arm64.simulator.a" ]]; then
  echo "arm64 simulator libgodot cached: $OUT" >&2
  echo "$OUT"
  exit 0
fi

if [[ ! -f "$GODOT_SRC/SConstruct" ]]; then
  mkdir -p "$(dirname "$GODOT_SRC")"
  git clone --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$GODOT_SRC"
fi
command -v scons >/dev/null || pip3 install --quiet scons

jobs="$(sysctl -n hw.ncpu)"
echo "=== scons iOS simulator arm64 template_release ($GODOT_TAG) ===" >&2
(
  cd "$GODOT_SRC"
  scons platform=ios target=template_release arch=arm64 simulator=yes \
    production=yes verbose=no warnings=no progress=no -j"$jobs" >&2
)
shopt -s nullglob
libs=("$GODOT_SRC"/bin/*.arm64.simulator.a)
if [[ ${#libs[@]} -eq 0 ]]; then
  echo "::error::scons produced no *.arm64.simulator.a" >&2
  ls -la "$GODOT_SRC/bin" >&2 || true
  exit 1
fi
cp "${libs[@]}" "$OUT/"
echo "arm64 simulator libs:" >&2
ls -lh "$OUT" >&2
echo "$OUT"
