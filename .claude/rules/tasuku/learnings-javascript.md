---
paths: app/javascript/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always add an ambient .d.ts declaration when importing JavaScript-only packages (like @hotwired/turbo-rails) in strict TypeScript mode, otherwise tsc fails with missing declaration errors.

## Insights

- When querying DOM in Playwright for multi-target Stimulus elements, use token selectors like `[data-reader-target~="lightboxImage"]` instead of exact-value selectors, because targets are space-separated.

