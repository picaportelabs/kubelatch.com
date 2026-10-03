#!/bin/sh
# Renders the landing video from index.html (Hyperframes, through npx: no
# dependency in the repo) in English and in Spanish: index.html holds both and
# picks its strings from <html lang>. Each language gets files named by a hash
# of their content so nginx can cache /media/ for a year:
#   landing/site/media/kubelatch-<hash>.mp4  H.264, no audio, faststart
#   landing/site/media/poster-<hash>.jpg     the frame at 19.5 s (kubectl, audit, 401)
# then points index.html at the English pair and es/index.html at the Spanish
# one, and deletes the old files.
#   landing/video/render.sh          render and publish both languages
#   landing/video/render.sh --snap   PNG frames into landing/video/snapshots/, nothing published
# Needs Node 22+, ffmpeg and Chrome. Run from anywhere.
set -eu
cd "$(dirname "$0")"
site=../site
hf="npx --yes hyperframes@0.8.78"
export HYPERFRAMES_SKIP_SKILLS=1
snap=false
if [ "${1:-}" = "--snap" ]; then snap=true; fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

hash() { sha256sum "$1" | cut -c1-10; }
for lang in en es; do
    p="$tmp/$lang"
    mkdir -p "$p"
    cp hyperframes.json meta.json "$p/"
    sed "s#<html lang=\"en\">#<html lang=\"$lang\">#" index.html > "$p/index.html"
    $hf check "$p" > "$tmp/check.log" 2>&1 || { cat "$tmp/check.log" >&2; exit 1; }
    if $snap; then
        $hf snapshot "$p" --at 2,6,11,17,19.5,23 -o "snapshots/$lang" >/dev/null
        echo "landing/video/snapshots/$lang"
        continue
    fi
    $hf render "$p" -o "$p/master.mp4" -q delivery --quiet
    ffmpeg -y -v error -i "$p/master.mp4" -an -c:v libx264 -preset veryslow -crf 26 \
        -pix_fmt yuv420p -profile:v high -movflags +faststart "$p/kubelatch.mp4"
    ffmpeg -y -v error -ss 19.5 -i "$p/master.mp4" -frames:v 1 -q:v 3 "$p/poster.jpg"
done
$snap && exit 0

rm -f "$site"/media/kubelatch*.mp4 "$site"/media/poster*.jpg
for lang in en es; do
    p="$tmp/$lang"
    mp4=kubelatch-$(hash "$p/kubelatch.mp4").mp4
    jpg=poster-$(hash "$p/poster.jpg").jpg
    cp "$p/kubelatch.mp4" "$site/media/$mp4"
    cp "$p/poster.jpg" "$site/media/$jpg"
    page="$site/index.html"
    [ "$lang" = es ] && page="$site/es/index.html"
    sed -i -E "s#/media/kubelatch[^\"]*\.mp4#/media/$mp4#g; s#/media/poster[^\"]*\.jpg#/media/$jpg#g" "$page"
done
ls -l "$site/media"
