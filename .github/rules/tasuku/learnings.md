# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- ReaperScans shut down July 2024. Always check if manga sources are still operational before implementing adapters.
- Turbo Frame lazy loading (`loading: :lazy`) uses IntersectionObserver to detect when the frame enters the viewport. CSS `display: contents` removes an element's box model, making IntersectionObserver unable to observe it. Never use `display: contents` on turbo-frame sentinels that need lazy loading. Instead, keep sentinels outside the CSS Grid and let each page render its own grid section.

## Insights

- AsuraScans is NOT standard Madara - uses custom Next.js frontend with embedded JSON in script tags
- Pages data extracted via regex from self.__next_f.push script content
- Domain has changed multiple times (asurascans.com -> asuratoon.com -> asuracomic.net)
- On macOS with Homebrew, pg_dump version may not match the PostgreSQL server version (e.g., pg_dump v14 in PATH but server v18). Use `SHOW server_version` to detect, then look for the matching binary at `/opt/homebrew/opt/postgresql@{version}/bin/pg_dump`.

