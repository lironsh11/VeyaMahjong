#!/usr/bin/env bash
# Shared helpers for building the project's Godot iOS (.gdip) plugins on macOS.
# Sourced by native/levelplay/ios/build.sh and native/storekit/ios/build.sh.
#
# A .gdip plugin is a static library compiled against Godot ENGINE headers (not godot-cpp), so
# it must be built from the same Godot version as the export templates, once with
# DEBUG_ENABLED (template_debug ABI) and once without (template_release ABI).
#
# Environment:
#   GODOT_TAG   Godot source tag to compile against (default 4.7.2-stable; must match the
#               export templates in use).
#   GODOT_SRC   Godot source checkout to use/create (default ~/.cache/lishi-godot/<tag>).
#   IOS_MIN     Minimum iOS version (default 15.0, same as export_presets.cfg).

set -euo pipefail

GODOT_TAG="${GODOT_TAG:-4.7.2-stable}"
GODOT_SRC="${GODOT_SRC:-$HOME/.cache/lishi-godot/$GODOT_TAG}"
IOS_MIN="${IOS_MIN:-15.0}"

# Generated engine headers a plugin needs before it can include core/object/*.h.
GODOT_GENERATED_HEADERS=(
    "core/version_generated.gen.h"
    "core/extension/gdextension_interface.gen.h"
    "core/object/gdvirtual.gen.h"
    "core/disabled_classes.gen.h"
)

log() { printf '\033[1;34m[ios-plugin]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[ios-plugin] %s\033[0m\n' "$*" >&2; exit 1; }

require_macos() {
    [[ "$(uname -s)" == "Darwin" ]] || die "iOS plugins can only be built on macOS with Xcode."
    command -v xcrun >/dev/null || die "xcrun not found: install Xcode and run xcode-select."
}

generated_headers_present() {
    local h
    for h in "${GODOT_GENERATED_HEADERS[@]}"; do
        [[ -f "$GODOT_SRC/$h" ]] || return 1
    done
    return 0
}

# Clones Godot at GODOT_TAG (shallow) and runs scons just long enough to generate the *.gen.h
# headers (the same trick godot-ios-plugins uses), then stops it.
ensure_godot_headers() {
    if [[ ! -d "$GODOT_SRC/.git" && ! -f "$GODOT_SRC/SConstruct" ]]; then
        log "Cloning Godot $GODOT_TAG into $GODOT_SRC"
        mkdir -p "$(dirname "$GODOT_SRC")"
        git clone --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$GODOT_SRC"
    fi
    if generated_headers_present; then
        log "Godot generated headers already present"
        return
    fi
    command -v scons >/dev/null || die "scons not found (pip3 install scons)."
    log "Generating Godot headers (scons runs until the *.gen.h files exist, then is stopped)"
    (
        cd "$GODOT_SRC"
        scons platform=ios target=template_release arch=arm64 -j"$(sysctl -n hw.ncpu)" >/tmp/lishi-godot-scons.log 2>&1 &
        local pid=$! waited=0
        while kill -0 "$pid" 2>/dev/null; do
            if generated_headers_present; then
                # Let scons finish the remaining generators (they all run before compiling).
                sleep 30
                break
            fi
            sleep 5
            waited=$((waited + 5))
            if (( waited > 900 )); then
                break
            fi
        done
        pkill -P "$pid" 2>/dev/null || true
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    )
    if ! generated_headers_present; then
        tail -n 40 /tmp/lishi-godot-scons.log >&2 || true
        die "Godot headers were not generated (see /tmp/lishi-godot-scons.log)."
    fi
}

# build_gdip_xcframeworks <name> <out_dir> <extra include dir> <sources...>
# Produces <out_dir>/<name>.debug.xcframework and <out_dir>/<name>.release.xcframework, each
# with an ios-arm64 slice and an ios-arm64_x86_64-simulator slice.
build_gdip_xcframeworks() {
    local name="$1" out_dir="$2" extra_include="$3"
    shift 3
    local sources=("$@")
    local work
    work="$(mktemp -d "${TMPDIR:-/tmp}/lishi-$name.XXXXXX")"
    local iphoneos_sdk simulator_sdk
    iphoneos_sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
    simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"

    local common=(
        -std=gnu++17 -stdlib=libc++ -fobjc-arc -fno-exceptions -fvisibility=hidden
        -DIOS_ENABLED -DAPPLE_EMBEDDED_ENABLED -DUNIX_ENABLED -DCOREAUDIO_ENABLED -DPTRCALL_ENABLED
        -I"$GODOT_SRC" -I"$GODOT_SRC/platform/ios" -I"$GODOT_SRC/drivers/apple_embedded"
        -I"$extra_include"
        -Wno-ambiguous-macro -Wno-deprecated-declarations
    )

    local config
    for config in debug release; do
        local defines=()
        if [[ "$config" == "debug" ]]; then
            defines=(-O2 -DNDEBUG -DNS_BLOCK_ASSERTIONS=1 -DDEBUG_ENABLED)
        else
            defines=(-O2 -DNDEBUG -DNS_BLOCK_ASSERTIONS=1)
        fi
        local slice
        for slice in "arm64:arm64-apple-ios$IOS_MIN:$iphoneos_sdk:device" \
                     "arm64:arm64-apple-ios$IOS_MIN-simulator:$simulator_sdk:sim-arm64" \
                     "x86_64:x86_64-apple-ios$IOS_MIN-simulator:$simulator_sdk:sim-x86_64"; do
            IFS=: read -r _arch triple sdk tag <<<"$slice"
            local obj_dir="$work/$config/$tag"
            mkdir -p "$obj_dir"
            local src objs=()
            for src in "${sources[@]}"; do
                local obj="$obj_dir/$(basename "${src%.*}").o"
                log "[$config/$tag] $(basename "$src")"
                xcrun clang++ -x objective-c++ -target "$triple" -isysroot "$sdk" \
                    "${common[@]}" "${defines[@]}" -c "$src" -o "$obj"
                objs+=("$obj")
            done
            xcrun libtool -static -o "$obj_dir/lib$name.a" "${objs[@]}"
        done
        mkdir -p "$work/$config/simulator"
        xcrun lipo -create "$work/$config/sim-arm64/lib$name.a" "$work/$config/sim-x86_64/lib$name.a" \
            -output "$work/$config/simulator/lib$name.a"
        local xcf="$out_dir/$name.$config.xcframework"
        rm -rf "$xcf"
        mkdir -p "$out_dir"
        xcodebuild -create-xcframework \
            -library "$work/$config/device/lib$name.a" \
            -library "$work/$config/simulator/lib$name.a" \
            -output "$xcf" >/dev/null
        log "Built $xcf"
    done
    rm -rf "$work"
}
