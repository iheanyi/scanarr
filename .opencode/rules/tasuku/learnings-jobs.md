---
paths: app/jobs/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always rehydrate runtime ivars at the start of ActiveJob::Continuable step methods; cursors persist across resumes but arbitrary instance variables do not.

