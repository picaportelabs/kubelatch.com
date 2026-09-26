#!/bin/sh
# Smoke test of the landing site as served (local image or production):
#   landing/check.sh http://127.0.0.1:3001
#   landing/check.sh https://kubelatch.com
# Checks status codes, languages, custom 404s, security headers on every kind
# of response and that every link and asset of both pages answers 200 (docs
# links included).
set -eu

base=${1:?usage: landing/check.sh BASE_URL}
base=${base%/}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bad() { echo "FAIL: $*"; fail=1; }
ok() { echo "ok:   $*"; }

# A refused connection or a DNS failure reads as status 000, never as a
# silent exit through set -e.
status() { curl -s -o /dev/null -w '%{http_code}' "$1" || true; }

# page PATH LANG: 200, HTML, the right lang, saved for the link check.
page() {
    out="$tmp/$(echo "$1" | tr '/' '_').html"
    code=$(curl -s -o "$out" -D "$out.h" -w '%{http_code}' "$base$1" || true)
    [ "$code" = 200 ] || { bad "$1 answered $code"; return; }
    grep -qi '^content-type: text/html' "$out.h" || bad "$1 is not text/html"
    grep -q "<html lang=\"$2\"" "$out" || bad "$1 does not declare lang=\"$2\""
    grep -qi 'hreflang="en"' "$out" && grep -qi 'hreflang="es"' "$out" || bad "$1 lacks hreflang alternates"
    ok "$1 ($2)"
}

page / en
page /es/ es

for pair in "/nope en" "/es/nope es"; do
    set -- $pair
    code=$(curl -s -o "$tmp/404" -w '%{http_code}' "$base$1" || true)
    [ "$code" = 404 ] || bad "$1 answered $code, want 404"
    grep -q "<html lang=\"$2\"" "$tmp/404" || bad "$1 is not the $2 404 page"
done
ok "custom 404 pages"

# Every kind of response carries the same headers: nginx drops the
# server-level add_header in any location that declares its own.
csp="default-src 'none'; style-src 'self'; img-src 'self'; media-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
poster=$(grep -oE 'poster="[^"]*"' "$tmp/_.html" | sed -E 's/^poster="//; s/"$//')
for p in / /es/ /nope /style.css "$poster"; do
    curl -s -o /dev/null -D "$tmp/h" "$base$p" || true
    for want in 'x-content-type-options: nosniff' 'referrer-policy: strict-origin-when-cross-origin' \
        'x-frame-options: DENY' 'strict-transport-security: max-age=31536000'; do
        grep -qi "^$want" "$tmp/h" || bad "$p: missing header $want"
    done
    got=$(grep -i '^content-security-policy:' "$tmp/h" | sed -E 's/^[^:]*: //' | tr -d '\r')
    [ "$got" = "$csp" ] || bad "$p: content-security-policy is '$got'"
    [ "$(grep -ci '^cache-control:' "$tmp/h")" -le 1 ] || bad "$p: more than one Cache-Control header"
done
ok "security headers"

# Every href/src/poster/content target in both pages. Relative ones resolve
# against the page; absolute ones must be kubelatch.com or docs.kubelatch.com.
links() {
    grep -oE '(href|src|poster|content)="[^"]*"' "$1" | sed -E 's/^[a-z]+="//; s/"$//' |
        grep -vE '^(#|mailto:|data:)' | grep -E '^(/|\.|[a-z0-9_-]+(/|\.)|https?://)' || true
}
for pair in "/ _.html" "/es/ _es_.html"; do
    set -- $pair
    for l in $(links "$tmp/$2" | sort -u); do
        case $l in
        https://kubelatch.com/*) url=$base${l#https://kubelatch.com} ;;
        http*://*) url=$l ;;
        /*) url=$base$l ;;
        *) url=$base$1$l ;;
        esac
        case $url in
        https://docs.kubelatch.com/*|"$base"/*) ;;
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
