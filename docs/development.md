# Development Workflow

## Sidekiq + Redis local setup

Scanarr now uses Sidekiq for jobs and Redis for both queueing and cache in development.

### Quick start

1. Start Redis locally:

```bash
# Option A (Homebrew)
brew services start redis

# Option B (Docker/Valkey)
docker run --name scanarr-redis -p 6379:6379 valkey/valkey:8
```

2. Run setup (includes Redis connectivity checks):

```bash
bin/setup
```

3. Start app + worker:

```bash
bin/dev
```

### Useful queue commands

```bash
bin/rails queue:health              # Redis + Sidekiq + cron visibility
bin/rails queue:cron                # list loaded cron jobs
bin/rails queue:assert_single_worker # dev guard against duplicate workers
bin/rails queue:clear_dev           # clear queue/retry/dead/scheduled (dev only)
```

### Notes on job compatibility

- **Recurring/cron jobs** are loaded from `config/sidekiq_schedule.yml` via `sidekiq-cron`.
- **Continuable jobs** still run through Active Job (`ActiveJob::Continuable`) on Sidekiq.
- `DownloadChapterJob` explicitly rehydrates runtime entities at each continuation step, which prevents nil-state resume failures across retries/resumes.

## Local test user policy

To keep local profiling/testing repeatable, use a dedicated development user instead of mutating arbitrary records.

### Default development seed user

`db/seeds.rb` creates an idempotent dev-only user when:

- `Rails.env.development?`
- `SCANARR_SEED_DEV_USER=1` (default)

Defaults:

- `username`: `perfuser`
- `email`: `perfuser@local.scanarr`
- `password`: `password123`

Override via environment variables before running seeds:

```bash
SCANARR_DEV_USERNAME=myuser \
SCANARR_DEV_EMAIL=myuser@local.scanarr \
SCANARR_DEV_PASSWORD='my-password' \
bin/rails db:seed
```

Disable dev user seeding:

```bash
SCANARR_SEED_DEV_USER=0 bin/rails db:seed
```

### One-off console upsert (no schema/app changes)

When you need a test account quickly, use this idempotent command:

```bash
bin/rails runner "u=User.find_or_initialize_by(username: 'perfuser'); u.email='perfuser@local.scanarr'; u.password='password123' if u.new_record? || u.password_digest.blank?; u.role=:admin if u.respond_to?(:role); u.save!"
```

This avoids ad-hoc data churn and keeps local test access predictable.
