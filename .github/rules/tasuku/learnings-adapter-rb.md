---
paths: app/lib/scrapers/mangadex/adapter.rb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Insights

- For MangaDex chapter discovery, use /manga/:id/feed (not /chapter with manga filter) and avoid includeFuturePublishAt/includeExternalUrl because they can force zero results even when chapters exist.

