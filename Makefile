IMAGE ?= kong-oidc-role:local
SERVICE ?= kong

.PHONY: build up down logs ps validate test

build:
	docker build -t $(IMAGE) .

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f $(SERVICE)

ps:
	docker compose ps

validate:
	docker compose config >/dev/null
	test -f oidc-role/handler.lua
	test -f oidc-role/schema.lua

test:
	@echo "No automated test runner configured yet."
	@echo "See README.md for manual integration testing steps."
