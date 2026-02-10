---
paths: app/views/pwa/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Insights

- Lighthouse v12+ no longer exposes the legacy `pwa` category/audits in default runs; verify PWA readiness with explicit runtime checks (manifest endpoint, service worker registration/scope, CacheStorage entries) plus browser automation instead of relying on `--only-categories=pwa`.

