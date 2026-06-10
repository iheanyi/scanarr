# Scanarr

Scanarr is a self-hosted manga aggregation and download manager built with Rails. It tracks series across supported sources, downloads chapters into configurable local or S3-compatible storage, keeps a personal library, and provides a browser-based reader with offline support.

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

To dogfood the bundled Caddy profile locally and open Scanarr through the reverse proxy, run:

```bash
bin/self-host-caddy-smoke
```

Then open `http://localhost:8080`.

Media storage uses the named Docker volume `scanarr_storage_data` by default. To store pages, covers, and backups on a server path or NAS mount, set `SCANARR_STORAGE_PATH=/srv/scanarr/storage` before starting Compose. To avoid storing downloaded media on the app server, set `ACTIVE_STORAGE_SERVICE=s3` and provide the `S3_*` settings for AWS S3, Cloudflare R2, MinIO, or another S3-compatible object store.

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
