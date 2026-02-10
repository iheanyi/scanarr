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

## Insights

- AsuraScans is NOT standard Madara - uses custom Next.js frontend with embedded JSON in script tags
- Pages data extracted via regex from self.__next_f.push script content
- Domain has changed multiple times (asurascans.com -> asuratoon.com -> asuracomic.net)
- On macOS with Homebrew, pg_dump version may not match the PostgreSQL server version (e.g., pg_dump v14 in PATH but server v18). Use `SHOW server_version` to detect, then look for the matching binary at `/opt/homebrew/opt/postgresql@{version}/bin/pg_dump`.
- No pure Ruby option for image processing (WebP conversion, resizing). libvips is fastest (brew install vips on macOS, apt install libvips-dev on Linux). MiniMagick/ImageMagick is fallback. The saver: option is vips-only — MiniMagick does not support it.
- Solid stack (Solid Queue, Solid Cache, Solid Cable) is the right choice for self-hosted single-instance apps. No Redis needed. Works with both SQLite and Postgres. Only reach for Redis if multi-server coordination or thousands of concurrent users.

