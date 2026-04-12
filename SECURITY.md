# Security Policy

## Supported versions

At this time, only the latest version on the default branch is actively maintained.

## Reporting a vulnerability

Please report suspected vulnerabilities privately to the maintainer before public
 disclosure. Include:

- Affected version/commit,
- Reproduction steps,
- Impact assessment,
- Suggested remediation (if available).

## Secure deployment guidance

- Do not commit client secrets, API tokens, or private keys.
- Use secret managers, environment variables, or Docker/Kubernetes secrets.
- Enable TLS and certificate validation for IdP endpoints.
- Review token validation behavior and claim mapping before production rollout.
- Keep Kong and Lua/OpenResty dependencies up to date.

> This plugin should be reviewed and hard-tested in your environment before
> production use.
