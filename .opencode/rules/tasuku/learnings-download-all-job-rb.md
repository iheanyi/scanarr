---
paths: app/jobs/download_all_job.rb
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Always reset existing failed or cancelled FileAsset records to queued immediately when bulk queueing downloads, so Turbo broadcasts and admin rows reflect that retry work has actually been accepted.

