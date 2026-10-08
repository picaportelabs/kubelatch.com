#!/bin/sh
# Smoke test of the landing site as served (local image or production):
#   landing/check.sh http://127.0.0.1:3001
#   landing/check.sh https://kubelatch.com
# Checks status codes, languages, custom 404s, redirects, security headers on
# every kind of response, that every link and asset of the pages answers 200
# (docs links included) and that the stylesheet's font is served from the
# site.
# DOCS_URL=http://127.0.0.1:3002 checks the docs links against a local docs
# image (make docs-image) instead of docs.kubelatch.com, for pages not
# deployed yet.
set -eu

base=${1:?usage: landing/check.sh BASE_URL}
base=${base%/}
docs=${DOCS_URL:-}
docs=${docs%/}
fail=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bad() { echo "FAIL: $*"; fail=1; }
ok() { echo "ok:   $*"; }

# Every page of the site, "PATH LANG", one per |.
pages="/ en|/es/ es|/agents/ en|/es/agents/ es|/pricing/ en|/es/pricing/ es|/pro/thanks/ en|/es/pro/thanks/ es|/pro/key/ en|/es/pro/key/ es|/pro/key/sent/ en|/es/pro/key/sent/ es|/terms/ en|/es/terms/ es|/privacy/ en|/es/privacy/ es|/security/ en|/es/security/ es"
echo "$pages" | tr '|' '\n' >"$tmp/pages"

# Where page PATH is saved: / is _.html, /es/agents/ is _es_agents_.html.
saved() { echo "$tmp/$(echo "$1" | tr '/' '_').html"; }

# A refused connection or a DNS failure reads as status 000, never as a
# silent exit through set -e.
status() { curl -s -o /dev/null -w '%{http_code}' "$1" || true; }

# page PATH LANG: 200, HTML, the right lang, saved for the link check.
page() {
    out=$(saved "$1")
    code=$(curl -s -o "$out" -D "$out.h" -w '%{http_code}' "$base$1" || true)
    [ "$code" = 200 ] || { bad "$1 answered $code"; return; }
    grep -qi '^content-type: text/html' "$out.h" || bad "$1 is not text/html"
    grep -q "<html lang=\"$2\"" "$out" || bad "$1 does not declare lang=\"$2\""
    grep -qi 'hreflang="en"' "$out" && grep -qi 'hreflang="es"' "$out" || bad "$1 lacks hreflang alternates"
    ok "$1 ($2)"
}

while read -r p lang <&3; do
    page "$p" "$lang"
done 3<"$tmp/pages"

# A page without the slash is a redirect to the page, not a 404.
for p in /agents /es/agents /pricing /es/pricing /terms /es/terms /privacy /es/privacy \
    /security /es/security /pro/key /es/pro/key; do
    loc=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$base$p" || true)
    case $loc in
    "301 $base$p/"|"301 $p/") ;;
    *) bad "$p answered '$loc', want 301 to $p/" ;;
    esac
done
ok "pages without the slash redirect to the page"

# Buying, the trial and the customer portal are redirects to Stripe, or to a
# mail to pro@kubelatch.com until the Stripe links exist.
for pair in "/pro/buy/ https://buy.stripe.com/" "/pro/trial/ https://buy.stripe.com/" \
    "/pro/portal/ https://billing.stripe.com/"; do
    set -- $pair
    loc=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$base$1" || true)
    case $loc in
    "302 $2"* | "302 mailto:pro@kubelatch.com"*) ;;
    *) bad "$1 answered '$loc', want 302 to $2… or to mailto:pro@kubelatch.com" ;;
    esac
    echo "$loc" >"$tmp/loc$(echo "$1" | tr '/' '_')"
done
# Buying and the trial are two different Payment Links.
cmp -s "$tmp/loc_pro_buy_" "$tmp/loc_pro_trial_" && bad "/pro/buy/ and /pro/trial/ redirect to the same link"
ok "/pro/buy/, /pro/trial/ and /pro/portal/ redirect to Stripe or to pro@"

# The key resend form posts the address and the page's language to the
# licensing service.
for pair in "/pro/key/ en" "/es/pro/key/ es"; do
    set -- $pair
    for want in 'action="https://licensing.kubelatch.com/keys/resend"' 'method="post"' 'name="email"' \
        "<input type=\"hidden\" name=\"lang\" value=\"$2\">"; do
        grep -qF "$want" "$(saved "$1")" || bad "$1: the form lacks $want"
    done
done
ok "the key resend forms"

for pair in "/nope en" "/es/nope es" "/es/pro/key/nope es" "/pro/ en" "/es/pro/ es"; do
    set -- $pair
    code=$(curl -s -o "$tmp/404" -w '%{http_code}' "$base$1" || true)
    [ "$code" = 404 ] || bad "$1 answered $code, want 404"
    grep -q "<html lang=\"$2\"" "$tmp/404" || bad "$1 is not the $2 404 page"
done
ok "custom 404 pages"

# Every kind of response carries the same headers: nginx drops the
# server-level add_header in any location that declares its own. The pages
# with the key resend form allow posting it to the licensing service.
csp="default-src 'none'; style-src 'self'; font-src 'self'; img-src 'self'; media-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
csp_form="default-src 'none'; style-src 'self'; font-src 'self'; img-src 'self'; media-src 'self'; base-uri 'none'; form-action 'self' https://licensing.kubelatch.com; frame-ancestors 'none'"
# The posters of the home page (the cover) and of /agents/ (the agents
# video). Unquoted below, so each is checked on its own.
posters=$(grep -ohE 'poster="[^"]*"' "$(saved /)" "$(saved /agents/)" | sed -E 's/^poster="//; s/"$//')
font=/fonts/InterVariable.woff2
for p in $(cut -d' ' -f1 "$tmp/pages") /nope /pro/buy/ /style.css $posters "$font"; do
    curl -s -o /dev/null -D "$tmp/h" "$base$p" || true
    for want in 'x-content-type-options: nosniff' 'referrer-policy: strict-origin-when-cross-origin' \
        'x-frame-options: DENY' 'strict-transport-security: max-age=31536000'; do
        grep -qi "^$want" "$tmp/h" || bad "$p: missing header $want"
    done
    case $p in
    /pro/key/|/es/pro/key/) want=$csp_form ;;
    *) want=$csp ;;
    esac
    got=$(grep -i '^content-security-policy:' "$tmp/h" | sed -E 's/^[^:]*: //' | tr -d '\r')
    [ "$got" = "$want" ] || bad "$p: content-security-policy is '$got'"
    [ "$(grep -ci '^cache-control:' "$tmp/h")" -le 1 ] || bad "$p: more than one Cache-Control header"
done
ok "security headers"

# Every href/src/poster/content target in the pages. Relative ones resolve
# against the page; absolute ones must be kubelatch.com or docs.kubelatch.com,
# except the source repository and Stripe, allowed without being fetched. A
# form's action= is none of these attributes, so it is not followed.
links() {
    grep -oE '(href|src|poster|content)="[^"]*"' "$1" | sed -E 's/^[a-z]+="//; s/"$//' |
        grep -vE '^(#|mailto:|data:)' | grep -E '^(/|\.|[a-z0-9_-]+(/|\.)|https?://)' || true
}
while read -r p lang <&3; do
    set -- "$p"
    for l in $(links "$(saved "$1")" | sort -u); do
        case $l in
        https://github.com/picaportelabs/kubelatch|https://github.com/picaportelabs/kubelatch/*) continue ;;
        https://buy.stripe.com/*|https://billing.stripe.com/*) continue ;;
        # The redirects to Stripe, checked above.
        /pro/buy/|/pro/trial/|/pro/portal/) continue ;;
        https://kubelatch.com/*) url=$base${l#https://kubelatch.com} ;;
        http*://*) url=$l ;;
        /*) url=$base$l ;;
        *) url=$base$1$l ;;
        esac
        if [ -n "$docs" ]; then
            case $url in https://docs.kubelatch.com/*) url=$docs/${url#https://docs.kubelatch.com/} ;; esac
        fi
        case $url in
        https://docs.kubelatch.com/*|"$base"/*) ;;
        "$docs"/*) [ -n "$docs" ] || { bad "$1 links outside kubelatch: $l"; continue; } ;;
        *) bad "$1 links outside kubelatch: $l"; continue ;;
        esac
        case $url in
        *#*)
            # A link to a heading: the page answers and holds that id.
            code=$(curl -s -o "$tmp/target" -w '%{http_code}' "${url%%#*}" || true)
            [ "$code" = 200 ] || { bad "$1 -> $l answered $code"; continue; }
            grep -q "id=\"${url#*#}\"" "$tmp/target" || bad "$1 -> $l: no such anchor"
            ;;
        *)
            code=$(status "$url")
            [ "$code" = 200 ] || bad "$1 -> $l answered $code"
            ;;
        esac
    done
done 3<"$tmp/pages"
ok "links and assets"

# The stylesheet loads nothing from another origin, and every file it names
# answers 200; the font comes as a font and is cached like the media.
curl -s -o "$tmp/style.css" "$base/style.css" || true
if grep -qE 'url\(["'"'"']?(https?:)?//|@import' "$tmp/style.css"; then
    bad "style.css loads from another origin"
fi
grep -q "url(\"$font\")" "$tmp/style.css" || bad "style.css does not load $font"
for l in $(grep -oE 'url\("?/[^")]*' "$tmp/style.css" | sed -E 's/^url\("?//' | sort -u); do
    code=$(status "$base$l")
    [ "$code" = 200 ] || bad "style.css -> $l answered $code"
done
curl -s -o /dev/null -D "$tmp/h" "$base$font" || true
grep -qi '^content-type: font/woff2' "$tmp/h" || bad "$font is not font/woff2"
grep -qi '^cache-control: max-age=31536000' "$tmp/h" || bad "$font is not cached for a year"
ok "stylesheet and font"

if [ "$fail" -ne 0 ]; then
    echo "landing check FAILED"
    exit 1
fi
echo "landing check passed"
