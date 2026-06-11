---
paths: app/services/sources/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always SSRF-filter URLs ingested from third-party feeds (e.g. the keiyoushi upstream catalog): reject loopback, private, link-local, 0.0.0.0, and .internal/.local hosts at the parse boundary, because health-recheck probes later fetch stored base_urls. Ruby's IPAddr covers this natively (loopback?/private?/link_local? include IPv6 ULA and fe80); no hand-rolled prefix lists needed.

