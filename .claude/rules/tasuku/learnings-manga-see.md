---
paths: app/lib/scrapers/manga_see/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- MangaSee chapter page URLs come from `/read-online/:slug-chapter-...` while some helper logic assumed `/manga/:slug`; always support both URL patterns when deriving slugs for page URL construction.

