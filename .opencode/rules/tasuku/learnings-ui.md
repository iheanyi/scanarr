---
paths: app/components/ui/**
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always guard `UI::SeriesCoverComponent` against raw local upload-style paths (for example `upload/pages/...`). Passing those strings straight to `image_tag` can trigger `Propshaft::MissingAssetError` during view rendering if they are not resolvable public URLs or asset pipeline paths.

