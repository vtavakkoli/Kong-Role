# Kong OIDC Role Plugin

[![Kong Gateway](https://img.shields.io/badge/Kong%20Gateway-3.9.3-003459?logo=kong&logoColor=white)](https://konghq.com/)
[![Plugin Version](https://img.shields.io/badge/oidc--role-v2.0.0-0ea5e9)](VERSION)
[![CI](https://github.com/vtavakkoli/Kong-Role/actions/workflows/plugin-ci.yml/badge.svg)](https://github.com/vtavakkoli/Kong-Role/actions/workflows/plugin-ci.yml)
[![Tests](https://img.shields.io/badge/unit%20tests-37%20passing-brightgreen)](#testing)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**Kong-Role** is a lightweight custom plugin for Kong Gateway that turns trusted OpenID Connect and JWT claims into Kong authorization groups.

It is designed for Keycloak-friendly role models such as:

- `realm_access.roles`
- `resource_access.<client>.roles`
- `groups`

The plugin validates identity tokens, extracts one or more authorization claims, establishes a trusted Kong credential context, and works with the standard Kong ACL plugin to enforce route-level access.

> **Validated with Kong Gateway 3.9.3** using real Keycloak RS256 access tokens and end-to-end role-based access tests.

---

## Why Kong-Role?

Identity providers authenticate users, but APIs still need a reliable way to decide:

- Who is calling?
- Is the token valid?
- Was it issued by the expected identity provider?
- Was it intended for this API?
- Which roles or groups does the caller have?
- Which routes may the caller access?

Kong-Role centralizes those decisions at the gateway.

```text
Client / BFF
    │
    │ Authorization: Bearer <access-token>
    ▼
Kong Gateway
    │
    ├── oidc-role
    │     ├── verifies JWT or introspects token
    │     ├── validates issuer, audience and time claims
    │     ├── extracts principal and authorization claims
    │     └── publishes trusted authenticated groups
    │
    ├── Kong ACL
    │     └── allows or denies the route
    │
    ▼
Protected upstream service
```

No synthetic Kong Consumer is required for normal multi-role authorization.

---

## Highlights

- **Kong Gateway 3.9.3 tested**
- **Secure JWT mode by default**
- **RS256 signature validation through OIDC Discovery and JWKS**
- **Token introspection mode**
- **Authorization-code mode**
- **Issuer and audience validation**
- **Nested claim extraction**
- **Multiple roles per user**
- **Kong authenticated-group integration**
- **Standard Kong ACL compatibility**
- **Optional legacy Consumer mapping**
- **Trusted-header cleanup and controlled header injection**
- **DB-less and DB-backed deployment support**
- **37 automated Busted unit tests**
- **GitHub Actions validation**
- **Docker-based local development**

---

## Supported authentication modes

| Mode | Purpose | Typical use |
|---|---|---|
| `jwt` | Validates a bearer JWT locally using Discovery and JWKS | Recommended for Keycloak access tokens |
| `introspection` | Sends the bearer token to an introspection endpoint | Opaque tokens or centralized revocation checks |
| `authorization_code` | Performs an OIDC authorization-code flow | Gateway-managed interactive login |

The default mode is:

```yaml
auth_mode: jwt
```

---

## Requirements

- Kong Gateway **3.9.3**
- Lua 5.1 / LuaJIT runtime provided by Kong
- An OpenID Connect provider such as Keycloak
- Signed access tokens or a configured introspection endpoint
- Kong ACL when route-level role enforcement is required

---

## Quick start

### 1. Clone the repository

```bash
git clone https://github.com/vtavakkoli/Kong-Role.git
cd Kong-Role
```

### 2. Build the custom Kong image

```bash
docker build -t kong-oidc-role:2.0.0 .
```

Or use the Makefile:

```bash
make build
```

### 3. Configure the plugin

Update:

```text
config-example/kong.yml
```

Replace the example issuer, Discovery URL, audience, and authorization claims with values from your identity provider.

### 4. Start Kong

```bash
docker compose up --build -d
```

Or:

```bash
make up
```

### 5. Check the services

```bash
docker compose ps
```

Default demo ports:

| Endpoint | Address |
|---|---|
| Kong proxy | `http://localhost:9180` |
| Kong Admin API | `http://localhost:9181` |

---

## Recommended JWT configuration

The following DB-less example validates Keycloak JWTs and authorizes requests through Kong ACL.

```yaml
_format_version: "3.0"

services:
  - name: lob1-service
    url: http://lob1:8080

    plugins:
      - name: oidc-role
        config:
          auth_mode: jwt

          discovery: >-
            https://keycloak.example.com/realms/example/
            .well-known/openid-configuration

          expected_issuer: >-
            https://keycloak.example.com/realms/example

          client_id: kong

          allowed_audiences:
            - kong

          allowed_signing_algorithms:
            - RS256

          ssl_verify: true
          timeout: 10000

          principal_claim: sub
          username_claim: preferred_username
          require_principal: true

          authorization_claims:
            - resource_access.kong.roles
            - realm_access.roles
            - groups

          require_authorization_claim: true

          expose_userinfo: false
          expose_id_token: false
          expose_access_token: false

routes:
  - name: lob1-route
    service: lob1-service
    paths:
      - /lob1

    plugins:
      - name: acl
        config:
          allow:
            - lob1-user

          always_use_authenticated_groups: true
          hide_groups_header: true
```

> YAML folded strings are shown for readability. In a real file, ensure the Discovery URL contains no spaces or line breaks.

A compact form is:

```yaml
discovery: https://keycloak.example.com/realms/example/.well-known/openid-configuration
expected_issuer: https://keycloak.example.com/realms/example
```

---

## Keycloak role mapping

A Keycloak access token may contain:

```json
{
  "sub": "6cde4adb-7a14-4fce-a4c2-3d391468ea27",
  "preferred_username": "alice",
  "aud": ["kong"],
  "realm_access": {
    "roles": [
      "lob1-user",
      "offline_access"
    ]
  },
  "resource_access": {
    "kong": {
      "roles": [
        "api-user"
      ]
    }
  }
}
```

With this configuration:

```yaml
authorization_claims:
  - resource_access.kong.roles
  - realm_access.roles
  - groups
```

Kong-Role collects all string values, removes duplicates, sorts the result, and publishes them as trusted authenticated groups.

Kong ACL can then authorize a route using:

```yaml
plugins:
  - name: acl
    config:
      allow:
        - lob1-user
      always_use_authenticated_groups: true
```

---

## Request flow

### JWT mode

1. A client or Backend-for-Frontend sends an access token to Kong.
2. Kong-Role reads the `Authorization: Bearer ...` header.
3. The plugin retrieves OIDC Discovery and JWKS metadata.
4. The JWT signature and configured signing algorithm are verified.
5. Expiration, issued-at, not-before, issuer, audience, and principal claims are checked.
6. Roles and groups are extracted from configured nested claim paths.
7. The plugin creates a trusted Kong credential context.
8. Extracted roles are published through `kong.ctx.shared.authenticated_groups`.
9. Kong ACL allows or rejects the route.
10. The request is forwarded only when authorization succeeds.

JWT mode validates tokens locally after Discovery and JWKS data are available. It does not require a token-introspection call for every request.

---

## Token introspection mode

Use introspection when your provider issues opaque tokens or when centralized token-state checks are required.

```yaml
plugins:
  - name: oidc-role
    config:
      auth_mode: introspection
      discovery: https://keycloak.example.com/realms/example/.well-known/openid-configuration
      expected_issuer: https://keycloak.example.com/realms/example

      client_id: kong
      client_secret: ${KONG_OIDC_CLIENT_SECRET}

      introspection_endpoint: >-
        https://keycloak.example.com/realms/example/
        protocol/openid-connect/token/introspect

      introspection_endpoint_auth_method: client_secret_post
      ssl_verify: true

      principal_claim: sub
      authorization_claims:
        - realm_access.roles
```

Store secrets using environment variables, Docker secrets, Kubernetes Secrets, Vault, or another secret manager.

---

## Authorization-code mode

Authorization-code mode allows Kong-Role to initiate interactive OIDC login.

```yaml
plugins:
  - name: oidc-role
    config:
      auth_mode: authorization_code
      discovery: https://keycloak.example.com/realms/example/.well-known/openid-configuration
      expected_issuer: https://keycloak.example.com/realms/example

      client_id: kong-web
      client_secret: ${KONG_OIDC_CLIENT_SECRET}
      session_secret: ${KONG_OIDC_SESSION_SECRET}

      redirect_uri: https://api.example.com/callback
      scope: openid profile
      response_type: code
      unauth_action: auth
      ssl_verify: true
```

For Backend-for-Frontend systems, it is often preferable for the BFF to perform the browser login and send only the server-held access token to Kong in JWT mode.

---

## Configuration reference

### Authentication and validation

| Setting | Default | Description |
|---|---:|---|
| `auth_mode` | `jwt` | `jwt`, `introspection`, or `authorization_code` |
| `client_id` | required | OIDC client identifier |
| `client_secret` | unset | Referenceable secret for modes that require it |
| `discovery` | required | OIDC Discovery endpoint |
| `expected_issuer` | unset | Exact accepted `iss` value |
| `allowed_audiences` | `[]` | Accepted `aud` values |
| `allowed_signing_algorithms` | `["RS256"]` | Accepted JWT signing algorithms |
| `timeout` | `10000` | Provider request timeout in milliseconds |
| `ssl_verify` | `true` | Verify provider TLS certificates |

### Identity and authorization

| Setting | Default | Description |
|---|---:|---|
| `principal_claim` | `sub` | Required caller identity claim |
| `username_claim` | `preferred_username` | Human-readable username claim |
| `authorization_claims` | Keycloak roles and groups | Nested claim paths collected as authorization groups |
| `require_principal` | `true` | Reject tokens without the configured principal |
| `require_authorization_claim` | `false` | Reject callers when no authorization group is found |

### Controlled upstream headers

| Setting | Default | Description |
|---|---:|---|
| `header_names` | `[]` | Upstream headers controlled by the plugin |
| `header_claims` | `[]` | Claim path corresponding to each header |
| `expose_userinfo` | `false` | Forward encoded user information |
| `expose_id_token` | `false` | Forward an ID token |
| `expose_access_token` | `false` | Forward an access token |

The plugin clears configured trusted headers before inserting its own values. This prevents clients from spoofing identity headers.

### Legacy Consumer mapping

| Setting | Default | Description |
|---|---:|---|
| `legacy_consumer_mapping` | `false` | Enable claim-to-Consumer lookup |
| `consumer_mapping_required` | `false` | Reject the request when no Consumer matches |
| `consumer_claim` | `sub` | Claim used for Consumer lookup |
| `consumer_by` | `custom_id` | Match by `id`, `username`, or `custom_id` |

New deployments should normally use authenticated groups and Kong ACL instead of creating one Consumer for every role.

---

## HTTP responses

| Status | Meaning |
|---:|---|
| `401 Unauthorized` | Missing, malformed, expired, inactive, or otherwise invalid token |
| `403 Forbidden` | Valid identity but missing required authorization claims or Consumer mapping |
| `500 Internal Server Error` | Plugin configuration or internal processing failure |

Internal error details are not returned to the client.

---

## Testing

Kong-Role v2 includes **37 Busted unit tests** covering:

- nested claim extraction
- role normalization and deduplication
- issuer and audience checks
- JWT validation flows
- token introspection
- authorization-code handling
- invalid or missing bearer tokens
- inactive tokens
- session-secret validation
- request filters
- custom machine principal claims
- authenticated-group propagation
- trusted-header replacement
- opt-in token forwarding
- optional and required legacy Consumer mapping
- correct `401`, `403`, and `500` responses

### Run validation

```bash
make validate
```

This checks:

- Docker Compose configuration
- Lua syntax for the plugin source files

### Run unit tests

Install Lua 5.1, Busted, and `lua-cjson`, then run:

```bash
make test
```

Or directly:

```bash
busted --helper=spec/spec_helper.lua --verbose spec
```

### GitHub Actions

The workflow:

```text
.github/workflows/plugin-ci.yml
```

runs:

- Lua 5.1 syntax checks
- release-file validation
- the complete Busted unit-test suite

### Kong 3.9.3 end-to-end validation

The plugin has also been tested successfully with **Kong Gateway 3.9.3** using:

- Keycloak 26.2
- real RS256 access tokens
- Discovery and JWKS validation
- multiple Keycloak realm roles
- Kong authenticated groups
- Kong ACL route enforcement
- protected backend services
- expected `200`, `401`, and `403` responses

A complete integration environment is available in:

**[vtavakkoli/IAM-LAB](https://github.com/vtavakkoli/IAM-LAB)**

Example tested authorization matrix:

| User | LOB-1 | LOB-2 | LOB-3 |
|---|---:|---:|---:|
| Alice | `200` | `403` | `403` |
| Bob | `200` | `200` | `403` |
| Charlie | `200` | `200` | `200` |

---

## Kong 3.9.3 compatibility

| Component | Version | Status |
|---|---:|---|
| Kong Gateway | `3.9.3` | Tested successfully |
| Plugin | `2.0.0` | Supported |
| Keycloak | `26.2` | End-to-end tested |
| Lua | `5.1 / LuaJIT` | Supported by Kong runtime |

Other Kong versions may work, but should be validated in the target environment before production rollout.

---

## Docker image reproducibility

The Docker image uses pinned runtime dependency versions:

- `lua-resty-openidc` `1.8.0`
- `lua-resty-jwt` `0.2.3`
- `lua-resty-hmac` `0.06`

The build installs the exact runtime modules required by the plugin instead of relying on mutable LuaRocks mirror resolution.

---

## Repository structure

```text
.
├── .github/
│   └── workflows/
│       └── plugin-ci.yml
├── config-example/
│   └── kong.yml
├── oidc-role/
│   ├── filter.lua
│   ├── handler.lua
│   ├── schema.lua
│   ├── session.lua
│   └── utils.lua
├── spec/
│   ├── support/
│   ├── oidc_role_filter_spec.lua
│   ├── oidc_role_handler_spec.lua
│   ├── oidc_role_schema_spec.lua
│   ├── oidc_role_session_spec.lua
│   └── oidc_role_utils_spec.lua
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── Dockerfile
├── LICENSE
├── Makefile
├── NOTICE
├── README.md
├── SECURITY.md
├── VERSION
└── docker-compose.yml
```

---

## Production security checklist

Before production deployment:

- [ ] Use HTTPS for all identity-provider endpoints.
- [ ] Keep `ssl_verify: true`.
- [ ] Configure an exact `expected_issuer`.
- [ ] Configure the intended `allowed_audiences`.
- [ ] Restrict accepted signing algorithms.
- [ ] Use short-lived access tokens.
- [ ] Store client and session secrets outside source control.
- [ ] Disable token and user-information forwarding unless explicitly required.
- [ ] Review every forwarded identity header.
- [ ] Restrict access to the Kong Admin API.
- [ ] Apply network policies between Kong and upstream services.
- [ ] Add rate limiting and abuse protection where required.
- [ ] Monitor authentication and authorization failures.
- [ ] Validate the plugin against your exact Kong and IdP versions.
- [ ] Run dependency and container vulnerability scans.
- [ ] Perform a threat model and security review.

---

## Important limitations

- The plugin depends on the token structure produced by the configured identity provider.
- JWT validation does not provide immediate revocation awareness unless token lifetimes are short or introspection is used.
- Authorization decisions are only as accurate as the configured claim paths and ACL rules.
- High-availability, proxy, timeout, logging, and observability settings must be adapted to the deployment environment.
- This project is an open-source reference implementation and must be reviewed before production use.

---

## Development

Useful commands:

```bash
make build
make up
make ps
make logs
make validate
make test
make down
```

Please read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes.

---

## Security reporting

Do not publish suspected vulnerabilities in a public issue.

Follow the guidance in [SECURITY.md](SECURITY.md) and include:

- affected version or commit
- reproduction steps
- expected and actual behavior
- security impact
- suggested remediation, when available

---

## Roadmap

Planned improvements include:

- a broader Kong compatibility matrix
- automated container integration tests
- SBOM generation and container scanning
- dependency checksum verification
- structured security and authorization metrics
- additional policy examples
- Kubernetes and OpenShift deployment examples

---

## Related project

### IAM-LAB

The companion repository demonstrates a complete end-to-end environment with:

- Keycloak
- OpenLDAP
- Kong Gateway
- Kong-Role
- .NET Backend-for-Frontend applications
- protected LOB services
- automated authorization scenarios

Repository:

**https://github.com/vtavakkoli/IAM-LAB**

---

## Author

**Dr. Vahid Tavakkoli**

Created and maintained in 2026.

---

## License

Licensed under the [MIT License](LICENSE).

See [NOTICE](NOTICE) for additional attribution information.

---

Have fun testing Kong-Role, experimenting with authorization policies, and building new secure systems. 🚀
