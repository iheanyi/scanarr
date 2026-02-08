---
paths: app/controllers/chapters_controller.rb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- ActiveStorage's `page.image.attached?` returns true even when the underlying blob file is missing from disk. To verify files actually exist, use `ActiveStorage::Blob.service.exist?(blob.key)`. When selecting releases for the reader, always verify the first page's blob exists on disk before using that release.

