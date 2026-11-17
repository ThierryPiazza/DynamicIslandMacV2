#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
for item in a b; do
  if [ ! -f "$item.mp4" ]; then
    color=red
    if [ "$item" = b ]; then color=blue; fi
    ffmpeg -hide_banner -loglevel error -f lavfi -i "color=c=$color:s=640x360:r=24:d=30" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$item.mp4"
  fi
done
if [ "${1:-}" = "--prepare-only" ]; then exit 0; fi
printf 'Apri http://127.0.0.1:8765 in Zen. Ctrl-C per fermare.\n'
python3 -m http.server 8765 --bind 127.0.0.1
