# Self-Hosting Scanarr with Docker Compose

This guide covers the supported self-hosted deployment path for Scanarr.

## Prerequisites

- Docker 24+ with the Compose plugin (`docker compose`)
- 1 GB RAM minimum, 2 GB+ recommended
- Disk sized for your downloaded manga library
- Optional: a reverse proxy such as Caddy, nginx, Traefik, or Cloudflare Tunnel for HTTPS

## Quick Start

```bash
git clone https://github.com/iheanyi/scanarr.git
cd scanarr
cp .env.example .env
sed -i.bak "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
docker compose up -d
```

Open `http://localhost:3000` and create the first admin account. On first boot, the web container prepares the database before it becomes healthy; the Sidekiq worker waits for that health check before starting.

Before exposing Scanarr outside localhost, edit `.env` and change `SCANARR_DATABASE_PASSWORD` from the example value.

## Services

Docker Compose starts four long-running services:

| Service | Image | Purpose |
| --- | --- | --- |
| `web` | Built from this repo | Rails app through Thruster on container port 80 |
| `sidekiq` | Built from this repo | Background jobs for downloads, chapter checks, imports, and notifications |
| `postgres` | `postgres:18-alpine` | Primary application database |
| `redis` | `valkey/valkey:8-alpine` | Cache, Sidekiq queues, and Action Cable pub/sub |

Three named volumes persist data across restarts:

| Volume | Mounted at | Contains |
| --- | --- | --- |
| `postgres_data` | `/var/lib/postgresql` | Database data |
| `redis_data` | `/data` | Valkey persistence |
| `storage_data` | `/rails/storage` | Downloaded pages, covers, backups, and Active Storage files |

## Configuration

Copy `.env.example` to `.env` and configure these values.

### Required

| Variable | Description |
| --- | --- |
| `SECRET_KEY_BASE` | Secret used by Rails for signed/encrypted cookies. Generate once with `openssl rand -hex 64` and keep it stable across upgrades. |
| `SCANARR_DATABASE_PASSWORD` | PostgreSQL password for the `scanarr` database user. The example value works locally; change it for real deployments. |

`RAILS_MASTER_KEY` is optional. Most self-hosters should leave it blank and use `SECRET_KEY_BASE`. Only set `RAILS_MASTER_KEY` if you intentionally deploy with Rails encrypted credentials.

### Optional

| Variable | Default | Description |
| --- | --- | --- |
| `PORT` | `3000` | Host port for the web UI. |
| `WEB_CONCURRENCY` | `1` | Puma worker processes. |
| `RAILS_MAX_THREADS` | `5` | Puma threads per worker. |
| `SIDEKIQ_CONCURRENCY` | `5` | Sidekiq worker threads. |
| `REDIS_URL` | `redis://redis:6379/0` | Rails cache Redis URL. |
| `SIDEKIQ_REDIS_URL` | `redis://redis:6379/1` | Sidekiq queue Redis URL. |
| `ACTION_CABLE_REDIS_URL` | `redis://redis:6379/2` | Action Cable pub/sub Redis URL. |
| `RAILS_LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error`, or `fatal`. |
| `SCANARR_DISABLE_AUTH` | `false` | Set to `true` only for private single-user deployments behind a trusted VPN or reverse proxy. |

## Common Operations

### View logs

```bash
docker compose logs -f
docker compose logs -f web
docker compose logs -f sidekiq
```

### Check health

```bash
docker compose ps
curl -fsS http://localhost:${PORT:-3000}/up
```

### Open a Rails console

```bash
docker compose exec web bin/rails console
```

### Run migrations manually

The web container runs `db:prepare` on startup. To run migrations manually:

```bash
docker compose exec web bin/rails db:migrate
```

### Reset admin credentials

```bash
docker compose exec web bin/rails "scanarr:admin:reset[newadmin,new-password-here]"
```

### Back up the database

```bash
docker compose exec postgres pg_dumpall -U scanarr > scanarr-backup.sql
```

### Restore the database

```bash
docker compose exec -T postgres psql -U scanarr < scanarr-backup.sql
```

### Back up downloaded files

Back up the `storage_data` volume along with the database. For example:

```bash
docker run --rm -v scanarr_storage_data:/data -v "$PWD:/backup" alpine \
  tar czf /backup/scanarr-storage.tgz -C /data .
```

Adjust the volume name if your Compose project name is not `scanarr`.

### Update Scanarr

```bash
git pull
docker compose build
docker compose up -d
```

Migrations run automatically when the web container starts.

### Change the exposed port

Set `PORT` in `.env`:

```env
PORT=8080
```

Then apply it:

```bash
docker compose up -d
```

## Reverse Proxy

For public access, terminate HTTPS in a reverse proxy and forward to the host port configured by `PORT`.

### Caddy

```caddy
manga.example.com {
    reverse_proxy localhost:3000
}
```

### nginx

```nginx
server {
    listen 443 ssl;
    server_name manga.example.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## PostgreSQL Major Upgrades

This Compose file uses PostgreSQL 18. Major PostgreSQL upgrades require dump and restore.
The Postgres volume is mounted at `/var/lib/postgresql` so the official PostgreSQL 18 image can manage its major-version-specific data directory.

1. Back up while the old Postgres container is running:

```bash
docker compose exec postgres pg_dumpall -U scanarr > scanarr-postgres-backup.sql
```

2. Stop services:

```bash
docker compose down
```

3. Remove only the Postgres volume:

```bash
docker volume ls | grep postgres_data
docker volume rm <your_project>_postgres_data
```

4. Start fresh Postgres:

```bash
docker compose up -d postgres
```

5. Restore:

```bash
docker compose exec -T postgres psql -U scanarr < scanarr-postgres-backup.sql
```

6. Start the full stack:

```bash
docker compose up -d
```

7. Verify:

```bash
docker compose exec postgres psql -U scanarr -d scanarr_production -c "select version();"
```

## Troubleshooting

### `SECRET_KEY_BASE` is missing

Generate one and add it to `.env`:

```bash
sed -i.bak "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
docker compose up -d
```

Keep this value stable. Changing it invalidates existing signed cookies.

### Database connection errors on first start

Check Postgres health and logs:

```bash
docker compose ps postgres
docker compose logs postgres
```

For a brand-new install only, you can reset all Compose volumes:

```bash
docker compose down -v
docker compose up -d
```

This destroys database, Redis, and storage data.

### Sidekiq is not processing jobs

Check Valkey and worker logs:

```bash
docker compose exec redis valkey-cli ping
docker compose logs -f sidekiq
```

### Storage fills up

Downloaded manga pages are stored in the `storage_data` volume. To move storage to a host path, change the web and Sidekiq volume mounts:

```yaml
volumes:
  - /path/to/manga:/rails/storage
```
