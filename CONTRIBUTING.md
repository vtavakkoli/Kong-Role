# Contributing

Thanks for your interest in contributing.

## Development setup

1. Fork and clone the repository.
2. Build the local image:
   ```bash
   make build
   ```
3. Run the demo stack:
   ```bash
   make up
   ```
4. Validate configuration and formatting checks:
   ```bash
   make validate
   ```

## Contribution guidelines

- Keep changes focused and minimal.
- Preserve current plugin runtime behavior unless proposing a breaking change.
- Document behavior changes in `README.md` and `CHANGELOG.md`.
- Never commit real credentials, tokens, or private endpoints.

## Pull requests

Please include:
- What changed and why,
- How it was tested,
- Any compatibility considerations (Kong version, DB-less vs DB-backed).
