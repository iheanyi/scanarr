# Scanarr

Scanarr is a self-hosted manga aggregation and download manager built with Rails. It tracks series across supported sources, downloads chapters into local storage, keeps a personal library, and provides a browser-based reader with offline support.

## Features

- Source browsing and search across configured manga sources
- Local library with downloaded chapters and cover art
- Background downloads and scheduled chapter checks through Sidekiq
- Per-user accounts, admin controls, API keys, and optional single-user auth bypass
- Mihon/Tachiyomi-compatible import and export workflows
- Self-host deployment with Docker Compose or standalone app containers

## Quick Start

The fastest supported self-host path is Docker Compose:

```bash
git clone https://github.com/iheanyi/scanarr.git
cd scanarr
cp .env.example .env
sed -i.bak "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
docker compose up -d
```

Compose builds a local `scanarr:${SCANARR_VERSION:-local}` image from the clone, so a registry account is not required.

Open `http://localhost:3000` and create the first admin account.

See [docs/self-hosting.md](docs/self-hosting.md) for production setup, backups, updates, reverse proxy examples, and troubleshooting.
See [docs/releasing.md](docs/releasing.md) for the release/tagging policy.

## Development

Scanarr is a Rails 8.1 app with PostgreSQL, Redis/Valkey, Sidekiq, esbuild, and Vitest.

```bash
bin/setup
bin/dev
```

Default development seed user:

- Username: `perfuser`
- Password: `password123`

See [docs/development.md](docs/development.md) for local setup details and queue commands.

## Legal

Scanarr is a personal self-hosting tool. Only use it with content and sources you are legally allowed to access, download, and store in your jurisdiction. Source adapters may break when upstream sites change or block automated access.

## Contributing

Issues and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) and include the checks you ran.

## License

MIT. See [LICENSE](LICENSE).
