---
paths: app/components/**/*.rb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Insights

- In Ruby component helpers, avoid `next` inside a `begin` expression used in assignment (`@value ||= begin ... end`); use explicit conditional branches instead to prevent SyntaxError during eager load.

