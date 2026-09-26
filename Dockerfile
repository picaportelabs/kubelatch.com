# Landing site image (kubelatch.com): the static pages in landing/site served
# by nginx on port 3000. Nothing is built here; the video in site/media is
# rendered beforehand from landing/video. Build from the repo root:
#   docker build -f landing/Dockerfile -t kubelatch-landing .
# (landing/Dockerfile.dockerignore replaces the root .dockerignore).
FROM nginx:1.29-alpine
COPY landing/nginx.conf /etc/nginx/conf.d/default.conf
COPY landing/site /usr/share/nginx/html
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:3000/ || exit 1
