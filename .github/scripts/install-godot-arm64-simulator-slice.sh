#!/usr/bin/env bash
# Drop the arm64 simulator libgodot into the exported Xcode project's xcframework.
# The stock slice is x86_64 inside a folder that claims arm64+x86_64. lipo keeps
# x86_64 and adds arm64 so `ARCHS=arm64` + iphonesimulator can link IronSource/Meta.
set -euo pipefail

LIB_DIR="${1:?directory of *.arm64.simulator.a}"
EXPORT_ROOT="${2:?exported iOS project directory}"

shopt -s nullglob
found_godot=0
for simlib in "$LIB_DIR"/*.template_release.arm64.simulator.a; do
  base="$(basename "$simlib")"
  dests=()
  if [[ "$base" == libgodot.ios.template_release.arm64.simulator.a ]]; then
    # Godot's exporter renames libgodot.ios.release.xcframework to <Project>.xcframework.
    while IFS= read -r dest; do
      [[ -n "$dest" ]] && dests+=("$dest")
    done < <(find "$EXPORT_ROOT" -path '*/ios-arm64_x86_64-simulator/libgodot.a' -type f)
  else
    xcf_name="${base/.template_release.arm64.simulator.a/.release.xcframework}"
    xcf="$(find "$EXPORT_ROOT" -type d -name "$xcf_name" | head -n 1 || true)"
    if [[ -z "$xcf" ]]; then
      echo "No $xcf_name under $EXPORT_ROOT (skip $base)"
      continue
    fi
    slice_dir="$xcf/ios-arm64_x86_64-simulator"
    dest="$slice_dir/libgodot.a"
    if [[ ! -f "$dest" ]]; then
      dest="$(find "$slice_dir" -name '*.a' | head -n 1 || true)"
    fi
    [[ -n "$dest" && -f "$dest" ]] && dests+=("$dest")
  fi
  if [[ ${#dests[@]} -eq 0 ]]; then
    echo "No simulator archive to patch for $base"
    continue
  fi
  for dest in "${dests[@]}"; do
  work="$(mktemp -d)"
  if lipo -info "$dest" | grep -q 'x86_64'; then
    if lipo -info "$dest" | grep -q 'Non-fat'; then
      cp "$dest" "$work/x86.a"
    else
      lipo -extract x86_64 "$dest" -output "$work/x86.a"
    fi
    lipo -create "$simlib" "$work/x86.a" -output "$work/fat.a"
  else
    cp "$simlib" "$work/fat.a"
  fi
  cp "$work/fat.a" "$dest"
  rm -rf "$work"
  echo "Patched $dest"
  lipo -info "$dest"
  if ! lipo -info "$dest" | grep -q 'arm64'; then
    echo "::error::$dest still has no arm64" >&2
    exit 1
  fi
    [[ "$base" == libgodot.ios.template_release.arm64.simulator.a ]] && found_godot=1
  done
done

if [[ "$found_godot" -ne 1 ]]; then
  echo "::error::libgodot.ios.release.xcframework was not patched" >&2
  find "$EXPORT_ROOT" -name '*.xcframework' -o -name 'libgodot.a' >&2 || true
  exit 1
fi
