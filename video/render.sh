#!/bin/sh
# Renders the landing videos from their Hyperframes compositions (through
# npx: no dependency in the repo), in English and in Spanish: each
# composition holds both and picks its strings from <html lang>.
#   kubelatch  index.html   the cover, in the header of / and /es/
#   agents     agents.html  in the agents section of / and /es/, and on
#                           /agents/ and /es/agents/
# Each language gets files named by a hash of their content so nginx can
# cache /media/ for a year:
#   landing/site/media/kubelatch-<hash>.mp4, poster-<hash>.jpg (frame at 19.5 s)
#   landing/site/media/agents-<hash>.mp4, agents-<hash>.jpg    (frame at 16.5 s)
# H.264, no audio, faststart. Then it points the pages at the new files and
# deletes the old ones.
#   landing/video/render.sh                  render and publish both videos
#   landing/video/render.sh agents           only that one
#   landing/video/render.sh --snap [video…]  PNG frames into landing/video/snapshots/, nothing published
# Needs Node 22+, ffmpeg and Chrome. Run from anywhere.
set -eu
cd "$(dirname "$0")"
site=../site
hf="npx --yes hyperframes@0.8.78"
export HYPERFRAMES_SKIP_SKILLS=1
snap=false
if [ "${1:-}" = "--snap" ]; then snap=true; shift; fi
videos=${*:-kubelatch agents}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

hash() { sha256sum "$1" | cut -c1-10; }

for v in $videos; do
    case $v in
    kubelatch)
        src=index.html; at=19.5; frames=2,6,11,17,19.5,23; mp4=kubelatch; jpg=poster; shots=snapshots
        pages_en="$site/index.html"; pages_es="$site/es/index.html" ;;
    agents)
        src=agents.html; at=16.5; frames=1.5,5,9,12.5,16.5,19.5,23.5; mp4=agents; jpg=agents; shots=snapshots/agents
        pages_en="$site/index.html $site/agents/index.html"; pages_es="$site/es/index.html $site/es/agents/index.html" ;;
    *) echo "no such video: $v (kubelatch or agents)" >&2; exit 2 ;;
    esac
    for lang in en es; do
        p="$tmp/$v-$lang"
        mkdir -p "$p"
        cp hyperframes.json meta.json "$p/"
        sed "s#<html lang=\"en\">#<html lang=\"$lang\">#" "$src" > "$p/index.html"
        $hf check "$p" > "$tmp/check.log" 2>&1 || { cat "$tmp/check.log" >&2; exit 1; }
        if $snap; then
            $hf snapshot "$p" --at "$frames" -o "$shots/$lang" >/dev/null
            echo "landing/video/$shots/$lang"
            continue
        fi
        $hf render "$p" -o "$p/master.mp4" -q delivery --quiet
        ffmpeg -y -v error -i "$p/master.mp4" -an -c:v libx264 -preset veryslow -crf 26 \
            -pix_fmt yuv420p -profile:v high -movflags +faststart "$p/out.mp4"
        ffmpeg -y -v error -ss "$at" -i "$p/master.mp4" -frames:v 1 -q:v 3 "$p/out.jpg"
    done
    $snap && continue

    rm -f "$site/media/$mp4-"*.mp4 "$site/media/$jpg-"*.jpg
    for lang in en es; do
        p="$tmp/$v-$lang"
        m=$mp4-$(hash "$p/out.mp4").mp4
        j=$jpg-$(hash "$p/out.jpg").jpg
        cp "$p/out.mp4" "$site/media/$m"
        cp "$p/out.jpg" "$site/media/$j"
        pages=$pages_en
        [ "$lang" = es ] && pages=$pages_es
        for page in $pages; do
            [ -f "$page" ] || continue   # /agents/ pages before they exist
            sed -i -E "s#/media/$mp4-[^\"]*\.mp4#/media/$m#g; s#/media/$jpg-[^\"]*\.jpg#/media/$j#g" "$page"
        done
    done
done
$snap || ls -l "$site/media"
