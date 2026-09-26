#!/bin/sh
# Smoke test of the landing site as served (local image or production):
#   landing/check.sh http://127.0.0.1:3001
#   landing/check.sh https://kubelatch.com
# Checks status codes, languages, custom 404s, security headers and that
# every link and asset of both pages answers 200 (docs links included).
set -eu

base=${1:?usage: landing/check.sh BASE_URL}
base=${base%/}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bad() { echo "FAIL: $*"; fail=1; }
ok() { echo "ok:   $*"; }

status() { curl -s -o /dev/null -w '%{http_code}' "$1"; }

# page PATH LANG: 200, HTML, the right lang, saved for the link check.
page() {
    out="$tmp/$(echo "$1" | tr '/' '_').html"
    code=$(curl -s -o "$out" -D "$out.h" -w '%{http_code}' "$base$1")
    [ "$code" = 200 ] || { bad "$1 answered $code"; return; }
    grep -qi '^content-type: text/html' "$out.h" || bad "$1 is not text/html"
    grep -q "<html lang=\"$2\"" "$out" || bad "$1 does not declare lang=\"$2\""
    grep -qi 'hreflang="en"' "$out" && grep -qi 'hreflang="es"' "$out" || bad "$1 lacks hreflang alternates"
    ok "$1 ($2)"
}

page / en
page /es/ es

for p in /nope /es/nope; do
    code=$(curl -s -o "$tmp/404" -w '%{http_code}' "$base$p")
    [ "$code" = 404 ] || bad "$p answered $code, want 404"
    grep -q 'kubelatch' "$tmp/404" || bad "$p is not the custom 404 page"
done
grep -q '<html lang="es"' "$tmp/404" || bad "/es/nope is not the Spanish 404 page"
ok "custom 404 pages"

h="$tmp/_.html.h"
for want in 'x-content-type-options: nosniff' 'referrer-policy: strict-origin-when-cross-origin' \
    'x-frame-options: DENY' "content-security-policy: default-src 'none'"; do
    grep -qi "^$want" "$h" || bad "missing header: $want"
done
ok "security headers"

# Every href/src/poster/srcset target in both pages. Relative ones resolve
# against the page; absolute http(s) ones must be docs.kubelatch.com.
links() {
    grep -oE '(href|src|poster|content)="[^"]*"' "$1" | sed -E 's/^[a-z]+="//; s/"$//' |
        grep -vE '^(#|mailto:|data:)' | grep -E '^(/|\.|[a-z0-9_-]+(/|\.)|https?://)' || true
}
for pair in "/ _.html" "/es/ _es_.html"; do
    set -- $pair
    for l in $(links "$tmp/$2" | sort -u); do
        case $l in
        https://kubelatch.com/*|https://kubelatch.com) url=$base${l#https://kubelatch.com} ;;
        http*://*) url=$l ;;
        /*) url=$base$l ;;
        *) url=$base$1$l ;;
        esac
        case $url in
        http*://docs.kubelatch.com*|"$base"*) ;;
        *) bad "$1 links outside kubelatch: $l"; continue ;;
        esac
        code=$(status "$url")
        [ "$code" = 200 ] || bad "$1 -> $l answered $code"
    done
done
ok "links and assets"

if [ "$fail" -ne 0 ]; then
    echo "landing check FAILED"
    exit 1
fi
echo "landing check passed"
