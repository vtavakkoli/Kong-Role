IMAGE ?= kong-oidc-role:local
SERVICE ?= kong
BUSTED ?= busted

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
	luac -p oidc-role/handler.lua
	luac -p oidc-role/utils.lua
	luac -p oidc-role/filter.lua
	luac -p oidc-role/session.lua
	luac -p oidc-role/schema.lua

test:
	$(BUSTED) --helper=spec/spec_helper.lua --verbose spec
