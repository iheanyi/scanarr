---
paths: app/views/admin/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Insights

- When replacing redirect-only admin actions with Turbo toasts for delete flows, ensure list rows have stable DOM ids (`dom_id`) so controllers can emit `turbo_stream.remove` and avoid stale UI.

