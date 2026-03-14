---
paths: app/jobs/download_chapter_job.rb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always guard long-running download jobs against `download_status == "cancelled"` during each step; otherwise in-flight jobs can overwrite cancellation with later progress/complete state and produce misleading live UI updates.

