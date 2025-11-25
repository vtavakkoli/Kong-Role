# Kong OIDC Role Plugin

This repository contains a custom **Kong plugin** that makes it easy to use **Keycloak realm roles** (or any `roles`-like claim) for API access control.

The plugin is **agnostic to the Kong database mode** – it works both with:

- **DB-less** Kong (declarative `kong.yml` configuration)
- **DB mode** (Postgres) where configuration is stored in the database and managed via the Admin API / Kong Manager / `deck`

The configs and Docker files in this repo are provided as **examples** to quickly try the plugin in a DB-less setup, but the plugin itself can be used in either mode.

---

## Features

- ✅ Role-based access control (RBAC) for Kong routes/services based on OIDC / JWT claims
- ✅ Works with Keycloak **realm roles** (e.g. `realm_access.roles`) or any array-like claim
- ✅ Clear HTTP responses when roles are missing (e.g. `403 Forbidden`)
- ✅ Can be used in **DB-less** and **DB** deployments
- ✅ Small, self-contained Lua plugin (designed to sit on top of an existing OIDC/JWT validation plugin)

---

## Repository structure

```text
Dockerfile           # Example Dockerfile to build a Kong image with this plugin
docker-compose.yml   # Example compose file (DB-less) to quickly try the plugin
config-example/
  kong.yml           # Example DB-less Kong configuration using the plugin
oidc-role/
  handler.lua        # Main plugin logic (access phase)
  schema.lua         # Plugin configuration schema (fields & validation)
  filter.lua         # Helper for parsing / matching role requirements
  session.lua        # Optional session / cache helper (if used)
  utils.lua          # Shared helper utilities
```

> **Note:** `docker-compose.yml` + `config-example/kong.yml` are only **examples to show the plugin working in DB-less mode**.  
> The plugin itself can also be installed and configured in a normal Kong **DB mode** (Postgres) setup.

---

## How it works

1. An upstream OIDC / JWT-auth plugin (for example `kong-oidc` or `jwt`) validates the access token and exposes the decoded token to Kong (via headers, `ngx.ctx`, etc.).
2. The **`oidc-role`** plugin runs in the access phase and:
   - reads the decoded token
   - extracts roles from a configurable JSON path (for example: `realm_access.roles`)
   - compares them with the required roles configured per route/service
3. If the required roles are present, the request is allowed to continue to the upstream service.
4. If roles are missing, the plugin responds with **HTTP 403 Forbidden** (or your configured status code/message).

In other words: authentication and token validation stay in the OIDC/JWT plugin; **`oidc-role` focuses purely on authorization**.

---

## Kong deployment modes

### DB-less (declarative config)

- `KONG_DATABASE=off`
- You define **services, routes, and plugins** in a single YAML file, e.g. `kong.yml`.
- This repo ships an example in `config-example/kong.yml` to show how the plugin can be configured.

Example snippet:

```yaml
_format_version: "3.0"

services:
  - name: lob1-service
    url: http://lob1:8080
    routes:
      - name: lob1-route
        paths:
          - /lob1
        plugins:
          - name: oidc
            config:
              # your existing OIDC / Keycloak configuration here
          - name: oidc-role
            config:
              required_roles:
                - lob1-user
              roles_claim: realm_access.roles
```

You then start Kong with:

```bash
KONG_DATABASE=off     KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml     kong start
```

or via Docker / Compose (see the example `docker-compose.yml`).

### DB mode (Postgres)

In **DB mode**, you keep the plugin code exactly the same, but configuration goes into the database via the **Admin API** (or Kong Manager / `deck`).

Minimal example using the Admin API:

```bash
# 1) Create service
curl -X POST http://localhost:8001/services       --data name=lob1-service       --data url=http://lob1:8080

# 2) Create route
curl -X POST http://localhost:8001/services/lob1-service/routes       --data name=lob1-route       --data paths[]=/lob1

# 3) Attach oidc-role plugin to that route
curl -X POST http://localhost:8001/routes/lob1-route/plugins       --data name=oidc-role       --data config.required_roles[1]=lob1-user       --data config.roles_claim=realm_access.roles
```

The plugin logic is identical; only the **way you store and manage configuration** (YAML vs. DB) changes.

---

## Installation

You have two main options:

### 1. Build a custom Kong image (example in this repo)

The provided `Dockerfile` can be used to build a Kong image with the plugin included:

```bash
# From the repository root
docker build -t kong-with-oidc-role .
```

In the image, the plugin code from `oidc-role/` is copied into the Kong plugins directory (e.g. `/usr/local/share/lua/5.1/kong/plugins/oidc-role`) and Kong is configured to load it.

### 2. Manual installation into an existing Kong

1. Copy the folder `oidc-role/` into your Kong plugins directory, for example:

   ```text
   /usr/local/share/lua/5.1/kong/plugins/oidc-role
   ```

2. Add the plugin name to your Kong configuration (`kong.conf` or environment variable):

   ```ini
   plugins = bundled,oidc-role
   ```

3. Restart Kong so that it can discover and load the new plugin.

You can then configure it either:

- declaratively in `kong.yml` (DB-less), **or**
- via the Admin API / Kong Manager / `deck` (DB mode).

---

## Configuration options

The exact fields are defined in `oidc-role/schema.lua`. The key ones are:

- `required_roles` (array of strings, **required**)  
  List of roles that must be present in the token for the request to be allowed.

- `roles_claim` (string, default: `realm_access.roles`)  
  JSON path or dot-notation indicating where to find the roles array inside the decoded token.

- `logical_operator` (string, default: `"AND"`)  
  Whether **all** roles (`"AND"`) or **at least one** role (`"OR"`) must match.

- `unauthorized_status` (number, default: `403`)  
  HTTP status code to return when the role check fails.

- `unauthorized_message` (string, optional)  
  Custom error message body for failed authorization.

Check `schema.lua` for the full list of options and the exact field names.

---

## Running the example (DB-less demo)

1. Make sure Docker (and the Compose plugin) is installed.
2. From the repo root run:

   ```bash
   docker compose up --build
   ```

3. Kong will start with the `oidc-role` plugin enabled and declarative configuration from `config-example/kong.yml` (feel free to adapt both files to your own environment).

4. Call the protected route with a valid access token:

   ```bash
   curl -H "Authorization: Bearer <ACCESS_TOKEN>" http://localhost:8000/lob1
   ```

   - If the token contains the required role(s), the upstream service will respond.
   - Otherwise you will get the configured `403` response from the plugin.

---

## Use cases

- Restrict access to APIs based on **Keycloak realm roles**
- Implement RBAC on top of existing OIDC / JWT authentication
- Protect internal admin / management APIs with minimal changes to application code
- Combine with other Kong plugins (rate limiting, logging, request/response transformation, etc.)

---

## Notes / disclaimers

- This plugin is intended as **example / lab code**. Review and harden it before using in production.
- Pay attention to TLS, timeouts, token validation, and key rotation in your OIDC setup.
- If you extend the plugin (e.g. client roles, groups, multi-IdP scenarios), feel free to fork and adapt it.
