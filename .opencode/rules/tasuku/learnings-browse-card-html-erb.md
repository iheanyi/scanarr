---
paths: app/views/sources/_browse_card.html.erb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always set `data-turbo-frame="_top"` on card-level `button_to` actions inside lazy-loaded Turbo Frame grids when the response redirects to a full page; otherwise Turbo may attempt frame replacement and render `Content missing`.

## Insights

- For card quick-actions that should appear on hover/focus, pair opacity transitions with `invisible`/`visible` states so hidden buttons are not focusable/clickable before reveal.

