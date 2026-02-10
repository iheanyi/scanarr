---
paths: **/*
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- Never include unescaped backticks in `gh pr comment --body` shell strings; shell command substitution will break the comment text. Use HEREDOC-quoted body instead.
- Always verify a PR has mergedAt/mergeCommit before deleting its remote branch; a closed PR can look done but leave commits unmerged.
