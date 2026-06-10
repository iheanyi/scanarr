---
paths: public/offline-*.html
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- When migrating legacy IndexedDB offline records, never rely on a single identifier (like chapter_public_id) for backfill; add layered recovery (API metadata first, then chapter page HTML fallback) so stale data can self-heal without forced re-downloads.
- Always style public PWA fallback pages with the same --ds token palette and button semantics as app components; ad-hoc hardcoded colors make offline flows feel disconnected from Scanarr.

