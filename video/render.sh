#!/bin/sh
# Renders the landing video from index.html (Hyperframes, through npx: no
# dependency in the repo) and writes the files the site serves, named by a
# hash of their content so nginx can cache /media/ for a year:
#   landing/site/media/kubelatch-<hash>.mp4  H.264, no audio, faststart
#   landing/site/media/poster-<hash>.jpg     the frame at 19.5 s (kubectl, audit, 401)
# then points both pages at the new names and deletes the old files.
# Needs Node 22+, ffmpeg and Chrome. Run from anywhere: landing/video/render.sh
set -eu
cd "$(dirname "$0")"
site=../site
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HYPERFRAMES_SKIP_SKILLS=1 npx --yes hyperframes@0.8.78 check
HYPERFRAMES_SKIP_SKILLS=1 npx --yes hyperframes@0.8.78 render -o "$tmp/master.mp4" -q delivery --quiet
ffmpeg -y -v error -i "$tmp/master.mp4" -an -c:v libx264 -preset veryslow -crf 26 \
    -pix_fmt yuv420p -profile:v high -movflags +faststart "$tmp/kubelatch.mp4"
ffmpeg -y -v error -ss 19.5 -i "$tmp/master.mp4" -frames:v 1 -q:v 3 "$tmp/poster.jpg"

hash() { sha256sum "$1" | cut -c1-10; }
mp4=kubelatch-$(hash "$tmp/kubelatch.mp4").mp4
jpg=poster-$(hash "$tmp/poster.jpg").jpg
rm -f "$site"/media/kubelatch*.mp4 "$site"/media/poster*.jpg
cp "$tmp/kubelatch.mp4" "$site/media/$mp4"
cp "$tmp/poster.jpg" "$site/media/$jpg"
for page in "$site/index.html" "$site/es/index.html"; do
    sed -i -E "s#/media/kubelatch[^\"]*\.mp4#/media/$mp4#g; s#/media/poster[^\"]*\.jpg#/media/$jpg#g" "$page"
done
ls -l "$site/media"
