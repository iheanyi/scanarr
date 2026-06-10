---
paths: test/controllers/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Never use `Scrapers::AdapterRegistry.stub` in tests; it is a plain Ruby class. Temporarily override singleton methods and restore them in an ensure block instead.

## Insights

- When Stimulus targets combine multiple tokens in one `data-*` attribute, controller/view tests should assert the actual combined value (or a robust fragment) to avoid brittle failures on target-list expansions.

