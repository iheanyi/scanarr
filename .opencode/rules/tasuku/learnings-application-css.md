---
paths: app/javascript/application.css
---

# Tasuku Learnings

_Auto-synced from .tasuku/context/learnings.md_

## Rules

- In Tailwind v4, custom CSS rules that need to override Tailwind utility classes (like opacity-0, hidden, etc.) MUST be placed in @layer utilities, not @layer components. The CSS cascade layer order is: base < components < utilities. Rules in @layer components will always lose to utility classes. This is the most common cause of "my CSS override isn't working" in Tailwind v4.

## Insights

- Tailwind v4's @source directive DOES scan .rb files correctly - the Rust-based Oxide scanner natively supports Ruby. Classes in constant hashes (VARIANT_CLASSES = { key: "bg-success-soft text-success" }) ARE detected. If classes appear missing from compiled CSS, check: (1) stale build artifacts like tailwind.css alongside application.css, (2) browser cache, (3) whether bin/dev build watcher is running. The @source inline("...") syntax is available as v4's safelist replacement if truly needed.

