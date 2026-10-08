# kubelatch.com

The landing site of kubelatch: static HTML and CSS in two languages (English at `/`, Spanish at `/es/`), with no scripts.

The product's source is private (`kubelatch-src`). The public repository is `picaportelabs/kubelatch`.

## Layout

| Path | What |
| --- | --- |
| `site/` | The English pages, fonts, media and `style.css`; `site/es/` holds the Spanish pages |
| `video/` | Hyperframes compositions of the two videos, and `render.sh` |
| `nginx.conf` | Server config: caching, headers, the `/es/` fallbacks and the Stripe redirects |
| `check.sh` | Status codes, headers and links, run against a served image |
| `Dockerfile`, `.dockerignore` | The image: nginx serving `site/`; the build context is this directory |

## Pages

Home, `/agents/`, `/pricing/`, `/pro/thanks/`, `/pro/key/`, `/pro/key/sent/`, `/terms/`, `/privacy/` and `/security/`, each also under `/es/`.

## Build and check

```bash
make image   # docker build -t kubelatch-landing:dev .
make check   # serve the image on :3001 and run check.sh against it
```

## Deploy

Coolify builds the `Dockerfile` at the root of this repository and serves it on port 3000. TLS ends at the Coolify proxy.

## Stripe redirects

`/pro/buy/`, `/pro/trial/` and `/pro/portal/` are redirects to Stripe, defined in `nginx.conf`. Change the targets there, then run `make check`.

## Video

`video/render.sh` renders both videos (cover and agents, in each language) into `site/media/` with content-hashed names, and points the pages at them. It needs Node 22+, ffmpeg and Chrome, and runs through `npx` with no dependency in the repository:

```bash
make video
video/render.sh agents          # only one video
video/render.sh --snap          # PNG frames into video/snapshots/, nothing published
```
