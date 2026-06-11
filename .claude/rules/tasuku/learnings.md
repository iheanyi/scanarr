# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- ReaperScans shut down July 2024. Always check if manga sources are still operational before implementing adapters.
- Turbo Frame lazy loading (`loading: :lazy`) uses IntersectionObserver to detect when the frame enters the viewport. CSS `display: contents` removes an element's box model, making IntersectionObserver unable to observe it. Never use `display: contents` on turbo-frame sentinels that need lazy loading. Instead, keep sentinels outside the CSS Grid and let each page render its own grid section.
- Always check Rack Mini Profiler after making changes. Key performance patterns: ActiveStorage includes must use cover_attachment: :blob (not just :cover_attachment). Keep server-side response times under 200ms. Watch for N+1 queries, sidebar rendering twice, and redundant per-request queries.
- Never use `path` as a shell loop variable in zsh; it aliases PATH and can break command resolution (`date`, `tr`, `base64`, etc.). Use names like `url_path` instead.
- Always avoid ad-hoc local DB mutations during profiling/debug runs. Use an explicit, idempotent development seed user or a one-line rails console upsert, and document the workflow so user data/setup remains predictable.
- Always ensure Turbo navigational links/buttons rendered inside a page-scoped turbo frame target `_top` when the destination is a full-page response without that frame; otherwise users hit Turbo 'Content missing' errors.
- When namespacing classes under Scrapers, always reference `Scrapers::AdapterRegistry` directly in app code; relying on a top-level alias can fail autoload timing and cause NameError in runtime paths.
- Always default link-style UI::ButtonComponent instances to data-turbo-frame="_top" unless an explicit target is provided; this prevents Turbo Frame 'Content missing' navigation traps from omitted attributes.
- Never mutate shared controller/service arrays from inside concurrent futures. Always return per-worker payloads (candidate/error) and aggregate sequentially on the calling thread to avoid dropped writes and racey state.
- Always verify review-reported method/route names against the current branch before patching; stale diffs can reference actions/helpers that no longer exist and lead to unnecessary changes.
- Never apply both a capsule border and an inner icon-button border for single-action compact controls; it creates a visible double-ring. Use one border layer (prefer the button) and keep wrapper unbordered.
- Always decide Turbo response style by navigation intent: use in-place Turbo Stream toasts for same-page mutations, but keep redirects for flows that should move users to a different page.
- Always size ActiveRecord pool >= web thread count + ActionCable worker pool + 1 (or set DATABASE_POOL explicitly) when SolidCable runs in the same DB.
- Always run `rails assets:precompile` in production Docker builds when using Propshaft; `yarn build` alone only writes to app/assets/builds and does not create public/assets digests or .manifest.json.
- Always avoid cache-first auto-caching for all image fetches in service workers for authenticated apps; only serve explicitly offline-marked images from cache to prevent unbounded growth and accidental private-content persistence.
- Always set OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES when running the full parallel Rails test suite on macOS to avoid objc fork-safety crashes/hangs in child processes.
- Always prefer native Rails mechanisms over hand-rolled equivalents in this repo: string-backed `enum (validate: true)` instead of a constant + inclusion validation + define_method predicates; generated enum scopes instead of custom ones. User flagged hand-rolled status plumbing on Source as churn ("Rails can handle this natively").

## Insights

- AsuraScans is NOT standard Madara - uses custom Next.js frontend with embedded JSON in script tags
- Pages data extracted via regex from self.__next_f.push script content
- Domain has changed multiple times (asurascans.com -> asuratoon.com -> asuracomic.net)
- On macOS with Homebrew, pg_dump version may not match the PostgreSQL server version (e.g., pg_dump v14 in PATH but server v18). Use `SHOW server_version` to detect, then look for the matching binary at `/opt/homebrew/opt/postgresql@{version}/bin/pg_dump`.
- No pure Ruby option for image processing (WebP conversion, resizing). libvips is fastest (brew install vips on macOS, apt install libvips-dev on Linux). MiniMagick/ImageMagick is fallback. The saver: option is vips-only — MiniMagick does not support it.
- Solid stack (Solid Queue, Solid Cache, Solid Cable) is the right choice for self-hosted single-instance apps. No Redis needed. Works with both SQLite and Postgres. Only reach for Redis if multi-server coordination or thousands of concurrent users.
- When a destructive action targets a stale/missing record in a Turbo flow, prefer Turbo redirect over in-place toast so the page can refresh and remove stale UI state.
- For admin table row actions targeting IDs, use a before_action loader that rescues RecordNotFound and responds with respond_with_toast(..., turbo_redirect: true) to prevent stale-row Turbo interactions from leaving inconsistent UI.
- Apply stale-target handling to user-facing Turbo mutating flows too (not only admin): before_action loaders for IDs should rescue RecordNotFound and return a Turbo redirect with alert toast instead of rendering a not_found page fragment.
- For scraper-backed JSON APIs, explicitly detect HTML challenge pages (e.g., Cloudflare 403 + <!DOCTYPE>) and raise a typed scraper error; this prevents confusing JSON parser errors from leaking into migration UI warnings.
- The connection pool timeout was caused by database.yml using max_connections (ignored) so the pool stayed at default 5, which is too small once ActionCable worker threads + SolidCable polling need extra connections.

