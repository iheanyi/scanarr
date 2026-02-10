---
paths: **/*
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Never include unescaped backticks in `gh pr comment --body` shell strings; shell command substitution will break the comment text. Use HEREDOC-quoted body instead.

