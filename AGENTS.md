## Cursor Cloud specific instructions

### Services overview

Scanarr is a Rails 8.1 monolith (manga aggregation/download manager). Development requires three processes started together via `bin/dev` (Foreman): **Puma web server** (port 3000), **esbuild asset watcher**, and **Sidekiq worker**. See `Procfile.dev` for details.

### Prerequisites (system-level, already installed in snapshot)

- **Ruby 3.4.4** at `/usr/local/ruby-3.4.4/bin` (added to `PATH` via `~/.bashrc`)
- **PostgreSQL 18** — start with `sudo pg_ctlcluster 18 main start`
- **Redis** — start with `sudo redis-server --daemonize yes`
- **Node.js 22.x** + **Yarn 1.x** (pre-installed)
- **libvips**, **libpq-dev**, **libyaml-dev** (pre-installed)

### Starting the dev environment

1. Start PostgreSQL: `sudo pg_ctlcluster 18 main start`
2. Start Redis: `sudo redis-server --daemonize yes`
3. Prepare DB (idempotent): `bin/rails db:prepare`
4. Start all services: `bin/dev`

The app runs at `http://localhost:3000`. Default dev user: `perfuser` / `password123` (seeded by `db/seeds.rb`).

### Running tests

- **Ruby tests**: `bin/rails test` (some pre-existing failures in scraper/download tests are expected)
- **JS tests**: `yarn test:run` (Vitest)
- **Linting**: `bin/rubocop` (Ruby), `bin/erblint --lint-all` (ERB)
- **Security**: `bin/brakeman` (static analysis), `bin/bundler-audit` (gem vulnerabilities)

See `CLAUDE.md` for model relationships, component patterns, and code conventions.

### Gotchas

- `bin/dev` checks Redis connectivity before starting; always start Redis first.
- `bin/dev` also checks for stale Sidekiq PID files in `tmp/pids/` — delete stale files if Foreman fails to start.
- Search functionality queries live external manga source APIs; some sources may time out or block requests in CI/cloud environments. This is expected behavior, not a bug.
- The `foreman` gem is installed globally (not in Gemfile) — `bin/dev` auto-installs it if missing.

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `iheanyi/scanarr`. See `docs/agents/issue-tracker.md`.

### Triage labels

Triage uses the canonical Matt Pocock skills label vocabulary. See `docs/agents/triage-labels.md`.

### Domain docs

Domain documentation follows the single-context layout for this Rails monolith. See `docs/agents/domain.md`.
