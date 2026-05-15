# Contributing

Thanks for helping improve Scanarr.

## Development Setup

Use the local development guide:

- [docs/development.md](docs/development.md)
- [docs/self-hosting.md](docs/self-hosting.md)

## Before Opening a PR

Run the checks that match the change:

```bash
bin/rails test
yarn test:run
bin/rubocop
bin/erblint --lint-all
bin/brakeman
bin/bundler-audit
```

For scraper changes, include the source you tested, whether the request used fixtures or the live source, and any known upstream instability.

For Docker/self-hosting changes, include the `docker compose` command you ran and whether it was a fresh install or an upgrade path.

## Project Conventions

- Keep production defaults self-host friendly and environment-variable driven.
- Do not commit `.env`, `config/master.key`, downloaded manga, or generated storage files.
- Prefer small, focused pull requests with tests or explicit manual verification.
- Treat source adapters as best-effort integrations; upstream sites can change markup or block automated requests.

## Legal

Only contribute code, docs, fixtures, and screenshots you have the right to publish. Do not add copyrighted manga pages or private source credentials to the repository.
