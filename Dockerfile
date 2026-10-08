# Landing site image (kubelatch.com): the static pages in site/ served by
# nginx on port 3000. Nothing is built here; the video in site/media is
# rendered beforehand from video/. The build context is this directory:
#   docker build -t kubelatch-landing .          (in the kubelatch.com repository)
#   docker build -t kubelatch-landing landing    (from kubelatch-src, make landing-image)
# .dockerignore keeps the context to nginx.conf and site/.
FROM nginx:1.29-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site /usr/share/nginx/html
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:3000/ || exit 1
