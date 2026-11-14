#!/bin/bash
# App Preview videos from the real game (ScreenshotTour --preview captures every frame at a fixed
# 30 fps at the exact App Store size), with the game's own Aurora Garden music, encoded to Apple's
# spec: H.264 High, level 4.0, <=30 fps, ~11 Mb/s, stereo AAC 256 kb/s 48 kHz, 15-30 s.
#   tools/store_listings/make_preview.sh <godot> [locale ...]     (default: en he)
# Output: build/preview/<locale>/{iphone,ipad}.mp4 (publish-asc.mjs uploads them when present).
set -euo pipefail
GODOT="$1"; shift
LOCALES="${*:-en he}"
cd "$(dirname "$0")/../.."
MUSIC=assets/veya/audio/music/aurora_garden_a.ogg
for loc in $LOCALES; do
  for dev in "iphone 886x1920" "ipad 1200x1600"; do
    set -- $dev
    out="build/preview/$loc/$1"
    rm -rf "$out"; mkdir -p "$out"
    "$GODOT" --path . --resolution "$2" --fixed-fps 30 -- --tour="$out" --preview --locale="$loc" --save-dir="user://preview_${loc}_$1" > "$out/log.txt" 2>&1 || true
    # The tour logs how many frames it recorded; never trust the folder (old frames can linger).
    n=$(sed -n 's/.*TOUR preview end: \([0-9]*\) frames.*/\1/p' "$out/log.txt" | tail -n1)
    [ -n "$n" ] || { echo "$loc $1: recording failed (see $out/log.txt)"; continue; }
    secs=$(awk "BEGIN{print $n/30}")
    echo "$loc $1: $n frames (${secs}s)"
    ffmpeg -y -loglevel error -framerate 30 -i "$out/frames/%05d.png" -stream_loop -1 -i "$MUSIC" \
      -t "$(awk "BEGIN{t=$n/30; print (t>29.9)?29.9:t}")" \
      -vf "format=yuv420p" -c:v libx264 -profile:v high -level:v 4.0 -b:v 11M -maxrate 12M -bufsize 24M -r 30 \
      -af "afade=t=in:d=0.5,afade=t=out:st=$(awk "BEGIN{t=$n/30; t=(t>29.9)?29.9:t; print t-1.2}"):d=1.2,volume=0.8" \
      -c:a aac -b:a 256k -ar 48000 -ac 2 -movflags +faststart "build/preview/$loc/$1.mp4"
    ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate,profile,level -show_entries format=duration -of compact "build/preview/$loc/$1.mp4"
  done
done
