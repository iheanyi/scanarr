---
paths: app/javascript/controllers/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Webtoon/continuous reader pages can be much taller than viewport, so IntersectionObserver thresholds like 0.3 may never be crossed; use threshold 0 (or very low) for webtoon-style progress tracking.

## Insights

- In webtoon/vertical reader modes, lightbox UX should use a vertical focus-scroll overlay (no left/right arrows) and keep progress state synchronized from the overlay back to reader URL/progress persistence.
- When a modal/lightbox owns keyboard navigation state, suspend background IntersectionObserver page-index updates; otherwise observer callbacks can race and regress current page during rapid key navigation.
- Gate end-of-chapter overlays behind an explicit next-at-end action (plus a short delay) instead of auto-showing on arrival at last page to avoid jarring interruptions in paged and swipe navigation flows.

