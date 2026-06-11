# Lessons

- 2026-02-09: Performance: Always check Rack Mini Profiler after changes. Look for N+1 queries (especially ActiveStorage — MUST use `cover_attachment: :blob` not just `:cover_attachment`), redundant queries on every request (notification counts, setup checks), and view rendering overhead. Keep server-side response times under 200ms. The profiler badge shows on every page in dev. Common traps: sidebar renders twice (desktop + mobile), `User.exists?` in before_action on every request, loading entire associations into memory when SQL can do it (e.g., chapter prev/next navigation). Postgres > SQLite for concurrent writes (download jobs + web requests). No pure Ruby option for image processing — libvips is the way.
- 2026-02-04: CI Brakeman: Don't use `--ensure-latest` flag - causes exit code 5 when newer version exists. Remove from bin/brakeman.
- 2026-02-04: Test fixtures: When multiple fixtures share same foreign key (e.g., two releases for same chapter), `order(created_at: :desc).first` picks based on fixture load order. Fix by ensuring fixtures use different relationships or cleaning up in test setup.
- 2026-02-04: rubocop-rails-omakase requires spaces inside array brackets: `[ "a", "b" ]` not `["a", "b"]`.
- 2026-02-04: Use `gh run view <id> --log-failed` to inspect CI failure logs from terminal.
- 2026-02-03: `button_to` with a block: URL is first argument, NOT text. Block provides button content.
- 2026-02-03: Kaminari doesn't have `page_range` method - calculate window manually with `(start_page..end_page)`.
- 2026-02-03: Always read library docs (via Context7 MCP) before using unfamiliar APIs - don't guess.
- 2026-02-03: CSS selector `doc.at_css("img")` gets FIRST image on page. Use specific selectors like `img[alt$=" cover"]` for targeted elements.
- 2026-02-03: SSL certificate issues with CDNs - add retry logic with `VERIFY_NONE` fallback for cover downloads.
- 2026-02-03: Add `jobs: bin/jobs` to Procfile.dev for hot-reloading background workers.
- 2026-02-03: Rails defaults `queue_adapter` to `:async` in development - set to `:solid_queue` in development.rb to use SolidQueue tables (required for Mission Control visibility).
- 2026-02-03: Mission Control for SolidQueue: install gem, mount at `/admin/jobs`, set `MissionControl::Jobs.http_basic_auth_enabled = false` in initializer for dev.
- 2026-02-02: Avoid assuming third-party extension bridges (e.g., Mihon). Confirm the source integration approach early and default to first-party scraper framework unless the user explicitly wants an extension ecosystem.
- 2026-02-02: Zeitwerk autoloading expects constants that match file paths; align scraper class/module names with app/scrapers paths to avoid NameError. Also convert Nokogiri NodeSet to arrays before using Array methods like concat.
- 2026-02-02: Don't miss basic Rails conventions. Before running tests, sanity-check Zeitwerk naming (file paths ↔ constants) and avoid obvious autoload pitfalls.
- 2026-02-02: Don't ship download artifacts without anchoring them to core domain models. Define Series/Chapter (and Release/FileAsset as needed) before persisting downloaded content.
- 2026-02-02: Verify git repo state with `git status -sb` before claiming no repo.
- 2026-02-02: If the user expects live visibility, do work on `main` (or merge immediately). Avoid keeping changes only in worktrees unless explicitly requested.
- 2026-02-02: When a user specifies design inspiration, follow it exactly; do not substitute sources.
- 2026-02-01: Avoid unnecessary tool calls; never generate images unless explicitly requested.

## Prefer native Rails over hand-rolled mechanisms (2026-06-10)

- Correction: hand-rolled `HEALTH_STATUSES` constant + inclusion validation + `define_method` predicates on `Source` flagged as churn ("Rails can handle this natively").
- Rule: reach for string-backed `enum(..., validate: true)`, delegated types, generated scopes, and ActiveModel casting before writing any status/variant plumbing by hand. Re-scan a diff for one-caller wrappers and speculative scopes before presenting it.
