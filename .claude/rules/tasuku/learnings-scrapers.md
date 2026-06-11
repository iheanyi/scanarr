---
paths: app/lib/scrapers/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Insights

- Source adapter metadata has a single source of truth: config/sources/manifest.yml (identity, adapter class, per-adapter integer version, curation flags). AdapterRegistry and db/seeds derive from it via Scrapers::Manifest / Sources::SyncService. To add an adapter: create app/lib/scrapers/<key>/adapter.rb plus a manifest entry; test/scrapers/adapter_coverage_test.rb fails CI if either half is missing. To ship an adapter fix: bump that entry's version, which resets the source's health probation on the next sync.

