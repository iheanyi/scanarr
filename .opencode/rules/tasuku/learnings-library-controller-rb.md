---
paths: app/controllers/library_controller.rb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always avoid interpolating user-derived arrays into SQL fragments for JSONB filters; build predicates with Arel or parameterized placeholders to prevent Brakeman SQL warnings and keep scan_ruby green.

