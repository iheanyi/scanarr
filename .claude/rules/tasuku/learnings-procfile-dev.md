---
paths: Procfile.dev
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Never pass `-P/--pidfile` to Sidekiq 8 in Procfiles; verify supported flags with `bundle exec sidekiq --help` after major gem upgrades.

