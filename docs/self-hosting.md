# Self-Hosting Scanarr

This guide covers the supported self-hosted deployment paths for Scanarr.

## Prerequisites

- Docker 24+
- Docker Compose plugin (`docker compose`) if you use the recommended Compose path
- 1 GB RAM minimum, 2 GB+ recommended
- Disk sized for your downloaded manga library
- Optional: a reverse proxy such as Caddy, nginx, Traefik, or Cloudflare Tunnel for HTTPS

## Quick Start

Docker Compose is the simplest path when you want Scanarr to manage the app, database, queue, and local file storage together:

```bash
git clone https://github.com/iheanyi/scanarr.git
cd scanarr
cp .env.example .env
sed -i.bak "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
docker compose up -d
```

Open `http://localhost:3000` and create the first admin account. On first boot, the web container prepares the database before it becomes healthy; the Sidekiq worker waits for that health check before starting.

Before exposing Scanarr outside localhost, edit `.env` and change `SCANARR_DATABASE_PASSWORD` from the example value.

Compose builds a local app image from the checked-out repository and tags it as `${SCANARR_IMAGE:-scanarr}:${SCANARR_VERSION:-local}`. For a release checkout, set `SCANARR_VERSION=v0.1.0` or the tag you are running.

## Deployment Options

### Docker Compose

Use Docker Compose if you want one command to start Postgres, Valkey, the web process, and Sidekiq. This is the recommended home lab path.

To serve a custom domain with the bundled Caddy profile, add these values to `.env`:

```env
APP_URL=https://manga.example.com
RAILS_HOSTS=manga.example.com
RAILS_ASSUME_SSL=true
RAILS_FORCE_SSL=true
CADDY_DOMAIN=manga.example.com
```

Then start the stack with Caddy:

```bash
docker compose --profile caddy up -d
```

### Existing Postgres and Valkey

Use the standalone container path if your NAS, homelab stack, or platform already provides PostgreSQL and Redis/Valkey. You still run two Scanarr containers: one web container and one Sidekiq worker.

Build the app image:

```bash
docker build -t scanarr:local .
docker volume create scanarr_storage_data
```

Add the external service URLs to `.env`:

```env
DATABASE_URL=postgresql://scanarr:<password>@<postgres-host>:5432/scanarr_production
REDIS_URL=redis://<redis-host>:6379/0
SIDEKIQ_REDIS_URL=redis://<redis-host>:6379/1
ACTION_CABLE_REDIS_URL=redis://<redis-host>:6379/2
APP_URL=https://manga.example.com
RAILS_HOSTS=manga.example.com,scanarr.home.arpa,192.168.1.50
RAILS_ASSUME_SSL=true
RAILS_FORCE_SSL=true
ACTIVE_STORAGE_SERVICE=local
ACTIVE_STORAGE_LOCAL_ROOT=/rails/storage
```

Then run the web and worker containers:

```bash
docker run -d \
  --name scanarr-web \
  --restart unless-stopped \
  --env-file .env \
  -p 3000:80 \
  -v scanarr_storage_data:/rails/storage \
  scanarr:local

docker run -d \
  --name scanarr-sidekiq \
  --restart unless-stopped \
  --env-file .env \
  -v scanarr_storage_data:/rails/storage \
  scanarr:local \
  bundle exec sidekiq -C config/sidekiq.yml
```

The web container runs `db:prepare` on startup. Start `scanarr-web` before `scanarr-sidekiq` on first install so migrations run before jobs start.

If you use `ACTIVE_STORAGE_SERVICE=s3`, omit the `scanarr_storage_data` volume and configure the S3/R2/MinIO variables instead.

### Kamal

Use Kamal when you want deploys over SSH to a server or VPS. The included `config/deploy.yml` is a homelab template with:

- Kamal proxy on the web role with automatic TLS for `scanarr.example.com`
- A PostgreSQL 18 accessory with persistent `scanarr_postgres_data`
- A Valkey accessory with persistent `scanarr_redis_data`
- An app storage volume at `scanarr_storage_data:/rails/storage`
- Separate `web` and Sidekiq `job` roles

Before deploying, edit `config/deploy.yml`:

- Replace `192.168.0.1` with your server IP or SSH hostname.
- Replace `scanarr.example.com` with your public or internal domain.
- Set `registry` to the registry you use for Kamal builds.
- Set `APP_URL`, `APP_HOST`, and `RAILS_HOSTS` to the same domain users browse.

Export secrets locally or source them from your password manager:

```bash
export SECRET_KEY_BASE="$(openssl rand -hex 64)"
export SCANARR_DATABASE_PASSWORD="$(openssl rand -hex 32)"
```

Then deploy:

```bash
bin/kamal setup
bin/kamal deploy
```

If you terminate TLS in an external proxy instead of Kamal proxy, keep `APP_URL=https://...`, `RAILS_ASSUME_SSL=true`, and `RAILS_FORCE_SSL=true`, but disable or adjust the `proxy` block in `config/deploy.yml`.

## Services

Docker Compose starts four long-running services by default. The optional Caddy profile adds a fifth service for reverse proxying:

| Service | Image | Purpose |
| --- | --- | --- |
| `web` | Built from this repo | Rails app through Thruster on container port 80 |
| `sidekiq` | Built from this repo | Background jobs for downloads, chapter checks, imports, and notifications |
| `postgres` | `postgres:18-alpine` | Primary application database |
| `redis` | `valkey/valkey:8-alpine` | Cache, Sidekiq queues, and Action Cable pub/sub |
| `caddy` | `caddy:2-alpine` | Optional HTTPS reverse proxy when started with the `caddy` profile |

Three explicitly named volumes persist data across restarts, rebuilds, and checkout-directory renames:

| Volume | Mounted at | Contains |
| --- | --- | --- |
| `scanarr_postgres_data` | `/var/lib/postgresql` | Database data |
| `scanarr_redis_data` | `/data` | Valkey persistence |
| `scanarr_storage_data` | `/rails/storage` | Downloaded pages, covers, backups, and Active Storage files |

The Caddy profile also creates `scanarr_caddy_data` and `scanarr_caddy_config` for certificates and proxy state.

Use `docker compose down` for normal stops. Do not use `docker compose down -v` unless you intentionally want to destroy the database, queues, and local media storage.

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
| `APP_URL` | blank | Canonical external URL, for example `https://manga.example.com`. Used for generated links, host authorization, and Action Cable origins. |
| `APP_HOST` | blank | Hostname override when `APP_URL` is not set. Usually leave blank and use `APP_URL`. |
| `APP_PROTOCOL` | `http` or `https` | Protocol override when `APP_URL` is not set. |
| `APP_PORT` | blank | External port for generated URLs when using a non-default port. |
| `RAILS_HOSTS` | blank | Comma- or space-separated hostnames/IPs Rails should accept, for example `manga.example.com,scanarr.home.arpa,192.168.1.50`. |
| `RAILS_ASSUME_SSL` | `false` | Treat proxied requests as HTTPS. Set `true` behind Caddy, Kamal proxy, Cloudflare Tunnel, Traefik, or nginx. |
| `RAILS_FORCE_SSL` | `false` | Use secure cookies, HSTS, and HTTPS redirects. Set `true` when all external traffic reaches Scanarr through HTTPS. |
| `ACTION_CABLE_ALLOWED_REQUEST_ORIGINS` | `APP_URL` | Optional explicit websocket origins. Use a comma-separated list for multiple domains. |
| `ACTIVE_STORAGE_SERVICE` | `local` | Set to `local` for the Compose storage volume, or `s3` for AWS S3, Cloudflare R2, MinIO, and compatible object stores. |
| `ACTIVE_STORAGE_LOCAL_ROOT` | `/rails/storage` | Disk path for local Active Storage files inside the web and Sidekiq containers. |
| `S3_ENDPOINT` | blank | Custom S3-compatible endpoint. Required for R2 and MinIO; usually blank for AWS S3. |
| `S3_BUCKET` | blank | Bucket name for `ACTIVE_STORAGE_SERVICE=s3`. |
| `S3_ACCESS_KEY_ID` | blank | S3-compatible access key. |
| `S3_SECRET_ACCESS_KEY` | blank | S3-compatible secret key. |
| `S3_REGION` | `auto` | Region for S3-compatible storage. Use `auto` for Cloudflare R2. |
| `S3_FORCE_PATH_STYLE` | `true` | Use path-style bucket addressing. Use `false` for most AWS S3 buckets. |
| `CADDY_DOMAIN` | `:80` | Domain served by the optional Compose Caddy profile. Set this to your public or internal hostname for HTTPS. |
| `HTTP_PORT` | `80` | Host HTTP port for the optional Caddy profile. |
| `HTTPS_PORT` | `443` | Host HTTPS port for the optional Caddy profile. |

### Custom Domains

For a public HTTPS domain:

```env
APP_URL=https://manga.example.com
RAILS_HOSTS=manga.example.com
RAILS_ASSUME_SSL=true
RAILS_FORCE_SSL=true
```

For an internal homelab DNS name without HTTPS:

```env
APP_URL=http://scanarr.home.arpa:3000
RAILS_HOSTS=scanarr.home.arpa,scanarr.local,192.168.1.50
RAILS_ASSUME_SSL=false
RAILS_FORCE_SSL=false
```

`RAILS_HOSTS` is intentionally explicit. Add every hostname or LAN IP that users will type into a browser, otherwise Rails can reject the request as an unknown host.

## Storage

### Local Disk

The default storage service writes downloaded pages, covers, generated CBZ archives, and backup artifacts into the `scanarr_storage_data` volume mounted at `/rails/storage`.

If you prefer a visible host directory for NAS backups, replace the `web` and `sidekiq` storage mounts with a bind mount:

```yaml
volumes:
  - /srv/scanarr/storage:/rails/storage
```

New downloads use readable Active Storage object keys:

```text
library/<source>/<series-slug>--<series-id>/volumes/<volume>/chapters/<chapter>--<chapter-id>/pages/001.jpg
library/<source>/<series-slug>--<series-id>/covers/cover.jpg
library/<source>/<series-slug>--<series-id>/volumes/<volume>/chapters/<chapter>--<chapter-id>/chapter.cbz
```

Existing blobs keep whatever key they were created with. Re-downloaded chapters, refreshed covers, and newly packaged archives use the readable layout.

### Cloudflare R2

```env
ACTIVE_STORAGE_SERVICE=s3
S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
S3_BUCKET=scanarr
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_REGION=auto
S3_FORCE_PATH_STYLE=true
```

### AWS S3

```env
ACTIVE_STORAGE_SERVICE=s3
S3_BUCKET=scanarr
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_REGION=us-east-1
S3_FORCE_PATH_STYLE=false
```

Leave `S3_ENDPOINT` blank for normal AWS S3 usage.

### MinIO

For a MinIO service reachable from the Scanarr containers:

```env
ACTIVE_STORAGE_SERVICE=s3
S3_ENDPOINT=http://minio:9000
S3_BUCKET=scanarr
S3_ACCESS_KEY_ID=...
S3_SECRET_ACCESS_KEY=...
S3_REGION=us-east-1
S3_FORCE_PATH_STYLE=true
```

When using S3-compatible storage, back up the bucket separately from the Compose volumes.

## Docker Compose Operations

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

For local disk storage, back up the `scanarr_storage_data` volume along with the database. For example:

```bash
docker run --rm -v scanarr_storage_data:/data -v "$PWD:/backup" alpine \
  tar czf /backup/scanarr-storage.tgz -C /data .
```

For S3-compatible storage, back up or version the object store bucket according to your provider's tooling.

### Update Scanarr

```bash
git pull
docker compose build
docker compose up -d
```

Migrations run automatically when the web container starts.

For tagged releases:

```bash
git fetch --tags
git checkout v0.1.0
SCANARR_VERSION=v0.1.0 docker compose build
docker compose up -d
```

### Change the exposed port

Set `PORT` in `.env`:

```env
PORT=8080
```

Then apply it:

```bash
docker compose up -d
```

## Standalone Container Operations

For standalone Docker installs, logs and health checks use the container names from the example above:

```bash
docker logs -f scanarr-web
docker logs -f scanarr-sidekiq
curl -fsS http://localhost:3000/up
```

To update a standalone install:

```bash
docker build -t scanarr:local .
docker stop scanarr-sidekiq scanarr-web
docker rm scanarr-sidekiq scanarr-web
```

Then rerun the `docker run` commands from the standalone container setup. Removing the containers does not delete the `scanarr_storage_data` volume.

## Reverse Proxy

For public access, terminate HTTPS in a reverse proxy and forward to the host port configured by `PORT`.

### Bundled Caddy Profile

The Compose file includes an optional Caddy service. For a public or internal HTTPS domain, set the domain and Rails URL values in `.env`:

```env
APP_URL=https://manga.example.com
RAILS_HOSTS=manga.example.com
RAILS_ASSUME_SSL=true
RAILS_FORCE_SSL=true
CADDY_DOMAIN=manga.example.com
```

Then start the stack:

```bash
docker compose --profile caddy up -d
```

Caddy stores certificates and state in the `scanarr_caddy_data` and `scanarr_caddy_config` volumes.

### External Caddy

```caddy
manga.example.com {
	encode zstd gzip
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
docker volume ls | grep scanarr_postgres_data
docker volume rm scanarr_postgres_data
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

With local storage, downloaded manga pages are stored in the `storage_data` volume. To move storage to a host path, change the web and Sidekiq volume mounts:

```yaml
volumes:
  - /path/to/manga:/rails/storage
```
