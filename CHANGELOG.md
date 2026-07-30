# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-07-30
### Security
- Removed logging of complete plugin configuration and secrets.
- Enabled TLS verification by default.
- Disabled access-token, ID-token, and user-info forwarding by default.
- Clear trusted upstream headers before setting plugin-controlled values.
- Enforce explicit issuer, audience, expiry, signing-algorithm, and principal checks.

### Added
- Explicit `jwt`, `introspection`, and `authorization_code` authentication modes.
- Nested claim extraction for Keycloak realm roles, client roles, and groups.
- Multi-role authorization through `kong.ctx.shared.authenticated_groups`.
- Optional backward-compatible Kong consumer mapping.
- LuaRocks package metadata, unit-test scaffold, and GitHub Actions syntax checks.

### Changed
- A caller identity is now derived from `sub` by default; roles are authorization groups rather than synthetic consumers.
- Configuration flags now use booleans instead of `yes`/`no` strings.
- Secure JWT mode is the default configuration.

## [1.0.0] - 2026-04-12
### Added
- Initial project hardening for open-source readiness.
- Standard repository metadata and policy files.
- Improved README with deployment and security guidance.
- Makefile with common developer commands.

### Changed
- Docker and Compose setup consistency improvements.
- Example DB-less configuration now clearly uses placeholder secrets.
- Minor maintainability comments added to Lua plugin code.
