#!/usr/bin/env bash
# App Store uploads need the iOS 26 SDK (Xcode 26).
set -euo pipefail

export TOOLCHAINS="${TOOLCHAINS:-com.apple.dt.toolchain.XcodeDefault}"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "TOOLCHAINS=$TOOLCHAINS" >> "$GITHUB_ENV"
fi
echo "Using TOOLCHAINS=$TOOLCHAINS"

# Codemagic sets xcode: latest on the image.
if [ -n "${CM_BUILD_ID:-}" ]; then
  echo "Codemagic runner — using default Xcode from image"
  xcodebuild -version
  xcodebuild -showsdks 2>/dev/null | grep -E 'iphoneos|iphonesimulator' || true
  exit 0
fi

selected=""
for app in \
  /Applications/Xcode_26.4.app \
  /Applications/Xcode_26.4.0.app \
  /Applications/Xcode_26.5.app \
  /Applications/Xcode_26.5_beta.app; do
  if [ -d "$app" ]; then
    selected="$app"
    break
  fi
done

if [ -z "$selected" ]; then
  selected=$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)
fi

if [ -z "$selected" ] || [ ! -d "$selected" ]; then
  echo "ERROR: No Xcode 26 found on runner." >&2
  ls -la /Applications/Xcode*.app >&2 || true
  exit 1
fi

echo "Selecting Xcode: $selected"
sudo xcode-select -s "$selected/Contents/Developer"
xcodebuild -version
echo "Installed iOS SDKs:"
xcodebuild -showsdks 2>/dev/null | grep -E 'iphoneos|iphonesimulator' || true
