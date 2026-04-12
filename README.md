# Kong OIDC Role Plugin

A lightweight, reusable Kong custom plugin for role-based authorization using OIDC/JWT claims (with Keycloak-friendly defaults).

This repository packages a Kong plugin named `oidc-role` that reads identity claims from validated tokens and maps them to Kong consumer/ACL authorization decisions.

> **Author:** Written by **Vahid Tavakkoli (2026)**.

## Project Overview

`oidc-role` is intended to be used **after authentication** (for example, after `kong-oidc`, OpenID Connect introspection, or JWT validation).

The plugin focuses on authorization and identity mapping by:
- validating/introspecting bearer tokens (depending on config),
- extracting claim values (including nested paths),
- optionally mapping claims to Kong consumers,
- injecting identity headers/groups for upstream services,
- enabling Kong ACL-based access control per route/service.

## Purpose

This project enables centralized API authorization in Kong when your identity provider (for example Keycloak) provides role/group claims in access tokens.

Typical use case:
- Identity provider authenticates users and issues tokens,
- Kong plugin reads token claims such as `realm_access.roles`,
- Kong ACL and consumer mapping enforce route-level access.

## Key Features

- Kong custom plugin structure compatible with Kong plugin loading.
- Works in both:
  - **DB-less mode** (`kong.yml` declarative config),
  - **DB-backed mode** (PostgreSQL + Admin API / decK / Kong Manager).
- Supports nested claim extraction (for example `realm_access.roles`).
- Optional consumer mapping by `id`, `username`, or `custom_id`.
- Identity/group/header injection for upstream services.
- Docker-based local demo setup for quick testing.

## Architecture (How It Works)

1. Request reaches Kong route/service with `oidc-role` enabled.
2. Plugin processes auth path based on configuration:
   - bearer JWT verify,
   - introspection,
   - or OIDC authorization flow.
3. Plugin extracts configured claims and sets Kong credential context.
4. Plugin can map claims to Kong consumer entities.
5. Kong ACL plugin (or upstream authorization logic) enforces route access.

## Repository Structure

```text
.
├── config-example/
│   └── kong.yml                  # DB-less declarative example (demo values)
├── oidc-role/
│   ├── filter.lua                # Request filtering helper
│   ├── handler.lua               # Main plugin handler (access phase)
│   ├── schema.lua                # Kong plugin schema
│   ├── session.lua               # Session secret handling
│   └── utils.lua                 # Shared helpers
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── Dockerfile                    # Custom Kong image with plugin
├── LICENSE                       # MIT license
├── Makefile                      # Common developer commands
├── NOTICE                        # Attribution / notices
├── SECURITY.md
├── VERSION
└── docker-compose.yml            # DB-less docker compose demo
```

## Installation

### Option 1: Build a custom Kong image (recommended for containerized deployments)

```bash
docker build -t kong-oidc-role:local .
```

### Option 2: Install plugin files into an existing Kong instance

Copy `oidc-role/` to:

```text
/usr/local/share/lua/5.1/kong/plugins/oidc-role
```

Then enable plugin loading in Kong config:

```ini
plugins = bundled,oidc-role
```

Restart Kong.

## Configuration Examples

### Minimal plugin configuration

```yaml
plugins:
  - name: oidc-role
    config:
      discovery: "https://<idp-host>/realms/<realm>/.well-known/openid-configuration"
      client_id: "<client-id>"
      client_secret: "<client-secret>"
      bearer_only: "yes"
      use_jwks: "yes"
      consumer_claim: "realm_access.roles"
      consumer_by: "custom_id"
```

### DB-less Kong usage

1. Update `config-example/kong.yml` with your real IdP endpoints and credentials.
2. Start Kong in DB-less mode.

```bash
docker compose up --build
```

### DB-backed Kong usage

Use PostgreSQL-backed Kong and configure resources via Admin API/decK.

High-level steps:
1. Install plugin on all Kong data-plane nodes.
2. Enable `oidc-role` in Kong `plugins` list.
3. Create services/routes/consumers.
4. Attach `oidc-role` and ACL config via Admin API or declarative sync (decK).

## Docker Usage

```bash
# build
make build

# run in detached mode
make up

# inspect logs
make logs

# stop/remove containers
make down
```

By default the compose setup exposes:
- Proxy: `http://localhost:9180`
- Admin API: `http://localhost:9181`

## Development Notes

- Keep plugin behavior backwards-compatible unless explicitly versioned.
- Favor small, targeted changes in Lua handlers.
- Use placeholders for demo configuration values (never real secrets).
- Run `make validate` before committing docs/config updates.

## Testing (Practical Approach)

No automated unit test suite is currently bundled with runtime dependencies in this repository.

Recommended validation path:
1. Static/config checks (`make validate`),
2. Launch demo (`make up`),
3. Verify unauthorized and authorized request behavior with curl.

### Sample curl checks

Unauthorized (missing/invalid token):

```bash
curl -i http://localhost:9180/lob1
```

Authorized (valid token placeholder):

```bash
curl -i \
  -H "Authorization: Bearer <VALID_ACCESS_TOKEN>" \
  http://localhost:9180/lob1
```

> Replace `<VALID_ACCESS_TOKEN>` with a real token from your identity provider.

## Limitations

- This repository is primarily a reference implementation and demo packaging.
- Behavior depends on correct token/claim structure from your IdP.
- Production-hardening (timeouts, retries, observability, policy rules) should be tailored to your environment.

## Security Considerations

- **Do not store client secrets in plain text** in version-controlled config files.
- Use environment variables, Docker secrets, or a secret manager.
- Treat `config-example/kong.yml` values as **placeholders only**.
- Validate TLS settings and avoid insecure `ssl_verify` behavior in production.
- Review and threat-model this plugin before production deployment.

See `SECURITY.md` for reporting guidance and deployment recommendations.

## Roadmap / Future Improvements

- Add automated plugin tests (busted/spec + CI workflow).
- Add compatibility matrix for Kong versions.
- Add examples for claim-based role matching policies beyond consumer mapping.
- Improve structured logging and operational metrics.

## Author and License

- **Author:** Vahid Tavakkoli (2026)
- **License:** MIT (see `LICENSE`)
- Additional attribution details: see `NOTICE`
