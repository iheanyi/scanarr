---
paths: app/controllers/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Prefer a shared `respond_with_toast` helper for mutating controller actions so Turbo requests get inline toasts while HTML requests keep redirect + flash fallback; this avoids duplicated respond_to blocks and keeps UX consistent.

