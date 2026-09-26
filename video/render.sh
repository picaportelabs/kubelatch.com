#!/bin/sh
# Renders the landing video from index.html (Hyperframes, through npx: no
# dependency in the repo) and writes the files the site serves:
#   landing/site/media/kubelatch.mp4  H.264, no audio, faststart
#   landing/site/media/poster.jpg     the frame at 19.5 s (kubectl, audit, 401)
# Needs Node 22+, ffmpeg and Chrome. Run from anywhere: landing/video/render.sh
set -eu
cd "$(dirname "$0")"
media=../site/media
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HYPERFRAMES_SKIP_SKILLS=1 npx --yes hyperframes@0.8.78 check
HYPERFRAMES_SKIP_SKILLS=1 npx --yes hyperframes@0.8.78 render -o "$tmp/master.mp4" -q delivery --quiet
ffmpeg -y -v error -i "$tmp/master.mp4" -an -c:v libx264 -preset veryslow -crf 26 \
    -pix_fmt yuv420p -profile:v high -movflags +faststart "$media/kubelatch.mp4"
ffmpeg -y -v error -ss 19.5 -i "$tmp/master.mp4" -frames:v 1 -q:v 3 "$media/poster.jpg"
ls -l "$media"
