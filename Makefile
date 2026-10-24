COMPOSE = docker compose -f server/compose.yaml --env-file server/data/.env

.PHONY: up down logs reset test smoke

up:
	./server/scripts/init.sh
	$(COMPOSE) up -d --build --wait

down:
	$(COMPOSE) down

logs:
	$(COMPOSE) logs -f --tail=100

reset:
	-$(COMPOSE) down -v
	rm -rf server/data

test:
	pnpm -r test

smoke: up
	pnpm --filter smoke start
