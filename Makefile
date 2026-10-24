COMPOSE = docker compose -f server/compose.yaml --env-file server/data/.env
# Same image as compose.yaml; used to delete files that Synapse (uid 991) created.
SYNAPSE_IMAGE := $(shell awk '/image: ghcr.io\/element-hq\/synapse:/ {print $$2; exit}' server/compose.yaml)
NO_ENV = echo "server/data/.env does not exist yet: run make up first"

.PHONY: up down logs reset test smoke

up:
	./server/scripts/init.sh
	$(COMPOSE) up -d --build --wait

down:
	@if [ -f server/data/.env ]; then $(COMPOSE) down; else $(NO_ENV); fi

logs:
	@if [ -f server/data/.env ]; then $(COMPOSE) logs -f --tail=100; else $(NO_ENV); fi

# A plain rm fails on Linux for files owned by uid 991, so fall back to a container. No sudo needed.
reset:
	@if [ -f server/data/.env ]; then $(COMPOSE) down -v || true; fi
	rm -rf server/data 2>/dev/null || docker run --rm -v "$(CURDIR)/server:/s" --entrypoint rm $(SYNAPSE_IMAGE) -rf /s/data

test:
	pnpm -r test

smoke: up
	pnpm --filter smoke start
