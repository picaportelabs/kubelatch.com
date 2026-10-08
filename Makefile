IMAGE ?= kubelatch-landing:dev

.PHONY: image check video

image: ## build the site image (nginx on :3000), as Coolify does
	docker build -t $(IMAGE) .

check: image ## serve the image on :3001 and run check.sh against it
	docker rm -f kubelatch-landing-check >/dev/null 2>&1 || true
	docker run -d --rm --name kubelatch-landing-check -p 127.0.0.1:3001:3000 $(IMAGE) >/dev/null
	for i in 1 2 3 4 5 6 7 8 9 10; do curl -sf -o /dev/null http://127.0.0.1:3001/ && break; sleep 0.5; done; \
	./check.sh http://127.0.0.1:3001; s=$$?; docker stop kubelatch-landing-check >/dev/null; exit $$s

video: ## render both videos into site/media (needs Node 22+, ffmpeg, Chrome)
	video/render.sh
