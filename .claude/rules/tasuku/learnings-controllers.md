---
paths: test/controllers/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Never use `Scrapers::AdapterRegistry.stub` in tests; it is a plain Ruby class. Temporarily override singleton methods and restore them in an ensure block instead.

