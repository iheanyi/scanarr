# Self-Hosting Scanarr with Docker Compose

This guide walks you through deploying Scanarr on your own server using Docker Compose.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) 24+ with the Compose plugin (`docker compose`)
- 1 GB RAM minimum (2 GB recommended)
- A few GB of disk for manga downloads

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/iheanyi/scanarr.git
cd scanarr

# 2. Copy the example env file
cp .env.example .env

# 3. Generate a secret key and add it to .env
#    Set EITHER SECRET_KEY_BASE or RAILS_MASTER_KEY (not both).
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env

# 4. Start everything
docker compose up -d

# 5. Open http://localhost:3000 and create your account
```

Scanarr will be available at `http://localhost:3000` (or whatever port you set in `.env`).

## Architecture

Docker Compose starts four services:

| Service    | Image              | Purpose                                    |
|------------|--------------------|--------------------------------------------|
| `web`      | Scanarr (built)    | Rails app via Thruster on port 80          |
| `sidekiq`  | Scanarr (built)    | Background jobs (downloads, chapter checks)|
| `postgres` | postgres:18-alpine | Primary application database               |
| `redis`    | valkey/valkey:8    | Cache store (db 0) + Sidekiq queue (db 1) + Action Cable pub/sub (db 2) |

Three named volumes persist data across restarts:

| Volume          | Mounted at                    | Contains                    |
|-----------------|-------------------------------|-----------------------------|
| `postgres_data` | `/var/lib/postgresql/data`    | All database data           |
| `redis_data`    | `/data`                       | Redis/Valkey persistence    |
| `storage_data`  | `/rails/storage`              | Downloaded manga pages      |

## Configuration

All configuration is done via environment variables in `.env`. Copy `.env.example` to `.env` and edit as needed.

### Required Variables

| Variable                    | Description                                                  |
|-----------------------------|--------------------------------------------------------------|
| `SECRET_KEY_BASE`           | 128-char hex string for session encryption. Generate with `openssl rand -hex 64`. |
| `SCANARR_DATABASE_PASSWORD` | PostgreSQL password (default: `scanarr`).                    |

> **Note**: You can use `RAILS_MASTER_KEY` instead of `SECRET_KEY_BASE` if you have the original `config/master.key` from the repo. Most self-hosters should use `SECRET_KEY_BASE`.

### Optional Variables

| Variable              | Default   | Description                                      |
|-----------------------|-----------|--------------------------------------------------|
| `PORT`                | `3000`    | Host port for the web UI.                        |
| `WEB_CONCURRENCY`     | `1`       | Number of Puma worker processes.                 |
| `RAILS_MAX_THREADS`   | `5`       | Threads per Puma worker.                         |
| `SIDEKIQ_CONCURRENCY` | `5`       | Sidekiq worker threads.                          |
| `REDIS_URL`           | `redis://redis:6379/0` | Redis cache URL for Rails cache store. |
| `SIDEKIQ_REDIS_URL`   | `redis://redis:6379/1` | Redis URL for Sidekiq queues.          |
| `ACTION_CABLE_REDIS_URL` | `redis://redis:6379/2` | Redis URL for Action Cable pub/sub. |
| `RAILS_LOG_LEVEL`     | `info`    | Log verbosity (`debug`, `info`, `warn`, `error`).|
| `SCANARR_DISABLE_AUTH`| `false`   | Set to `true` to skip login (single-user/VPN).   |

## Kamal Redis defaults

Kamal deploys can use the Redis accessory defined in `config/deploy.yml`.

- Default app runtime URLs point to `redis://scanarr-redis:6379/0` (cache) and `redis://scanarr-redis:6379/1` (Sidekiq).
- Action Cable defaults to `redis://scanarr-redis:6379/2`.
- To use external Redis, override `REDIS_URL`, `SIDEKIQ_REDIS_URL`, and `ACTION_CABLE_REDIS_URL` in `config/deploy.yml` for your environment.

## Common Operations

### View logs

```bash
docker compose logs -f          # all services
docker compose logs -f web      # just the web server
docker compose logs -f sidekiq  # just background jobs
```

### Open a Rails console

```bash
docker compose exec web bin/rails console
```

### Run database migrations

Migrations run automatically on startup (`db:prepare`). To run manually:

```bash
docker compose exec web bin/rails db:migrate
```

### Back up the database

```bash
docker compose exec postgres pg_dumpall -U scanarr > backup.sql
```

### Restore from backup

```bash
docker compose exec -T postgres psql -U scanarr < backup.sql
```

### Update to a new version

```bash
git pull
docker compose build
docker compose up -d
```

Migrations run automatically on container start.

### Upgrade PostgreSQL major versions (16 -> 18)

This release upgrades the Postgres image from `postgres:16` to `postgres:18`.
Major Postgres upgrades require dump/restore for Docker volumes.

1. Back up while your old Postgres container is still running:

```bash
docker compose exec postgres pg_dumpall -U scanarr > scanarr-pg16-backup.sql
```

2. Stop services:

```bash
docker compose down
```

3. Remove only the Postgres volume (keep Redis and storage volumes):

```bash
docker volume ls | grep postgres_data
docker volume rm <your_project>_postgres_data
```

4. Start fresh Postgres 18:

```bash
docker compose up -d postgres
```

5. Restore data:

```bash
docker compose exec -T postgres psql -U scanarr < scanarr-pg16-backup.sql
```

6. Start the full stack:

```bash
docker compose up -d
```

7. Verify Postgres version:

```bash
docker compose exec postgres psql -U scanarr -d scanarr_production -c "select version();"
```

If you already pulled the new image and Postgres fails to boot, roll back to the previous commit/image first, take a dump, then follow the steps above.

### Change the exposed port

Edit `PORT` in `.env`:

```bash
PORT=8080
```

Then `docker compose up -d` to apply.

## Reverse Proxy (Optional)

For HTTPS, put Scanarr behind a reverse proxy like Caddy or nginx.

### Caddy example

```
manga.example.com {
    reverse_proxy localhost:3000
}
```

### nginx example

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

## Troubleshooting

### Container won't start — "RAILS_MASTER_KEY" error

Set `SECRET_KEY_BASE` in your `.env` file instead:

```bash
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)" >> .env
```

### Database connection errors on first start

If database initialization fails on first boot, reset the Postgres volume and retry:

```bash
docker compose down -v    # WARNING: destroys all data
docker compose up -d
```

### Sidekiq not processing jobs

Check that Redis is healthy:

```bash
docker compose exec redis valkey-cli ping
```

Check Sidekiq logs:

```bash
docker compose logs -f sidekiq
```

### Storage fills up

Downloaded manga pages are stored in the `storage_data` volume. To check usage:

```bash
docker system df -v | grep storage_data
```

To move storage to a specific host path, edit `docker-compose.yml`:

```yaml
volumes:
  - /path/to/manga:/rails/storage
```
