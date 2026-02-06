# Scanarr Design System Audit

**Date**: 2026-02-05
**Scope**: Full codebase — tokens, components, views, controllers, patterns

---

## Executive Summary

The design system has a **strong foundation**: well-structured CSS custom properties with a proper `@theme` block, a growing ViewComponent library, and a dedicated showcase page. However, there are significant **consistency gaps** that undermine the system's value — primarily raw Tailwind color classes in components and views that bypass the semantic token layer, and a dual text-color naming scheme that creates confusion.

**Critical issues**: 2 | **High**: 5 | **Medium**: 8 | **Low**: 4

---

## 1. Tailwind Design Tokens

### Strengths
- Well-organized `@theme` block in `app/javascript/application.css` with clear sections
- Proper CSS custom property indirection (`--color-accent` → `--ds-accent`)
- Comprehensive coverage: surfaces, borders, text hierarchy, accent, semantic status colors, elevation, spacing, radius
- Form-specific spacing tokens (`--spacing-form-label`, etc.)
- Dark-mode-optimized shadow values

### Issues

#### [CRITICAL] Dual text-color naming: legacy vs new

The CSS defines **two parallel naming schemes** for text colors:

```
New:    text-primary / text-secondary / text-tertiary
Legacy: text-foreground / text-muted / text-muted-2
```

**All 20 view files use the legacy names** (`text-foreground`, `text-muted`, `text-muted-2`). The new names (`text-primary`, `text-secondary`, `text-tertiary`) are used **only in the design system showcase page** and a few components.

- `application.css:38-45` — defines both sets, marks foreground/muted/muted-2 as "Legacy aliases"
- Views: 355 usages of legacy names vs 0 of new names (excluding design_system/show.html.erb)
- Components: mixed — `empty_state_component.rb` uses `text-primary`/`text-secondary`, `button_component.rb` uses `text-primary`, but `toggle_switch_component.html.erb` uses `text-foreground`/`text-muted-2`

**Impact**: Confusing for contributors. No enforcement of which set to use. CLAUDE.md still documents `text-foreground`/`text-muted`/`text-muted-2`.

#### [MEDIUM] Missing token: `--color-danger` foreground variant

There's `--color-danger` and `--color-danger-soft` but no `--color-danger-foreground` (like accent has `--color-accent-foreground`). The `danger` button variant in ButtonComponent uses `text-foreground` which may not contrast well with `bg-error`.

- `button_component.rb:46` — `"bg-error text-foreground hover:bg-error/90"`

#### [LOW] `warm` token defined but rarely used

`--color-warm` / `--color-warm-soft` is defined (`#f2b067`) but not meaningfully distinct from `warning` (`#f2c16b`). Only the token definition uses it — no views or components reference `text-warm` or `bg-warm-soft`.

- `application.css:65-66`

#### [LOW] `success-soft` used as border color inconsistently

In `layouts/application.html.erb:42`, the flash notice uses `border-success-soft` as a border — but `-soft` tokens are `rgba()` values designed for backgrounds, not borders. This creates a very faint, nearly invisible border.

---

## 2. ViewComponents

### Inventory (14 components)

| Component | Tokens? | API Consistency | Notes |
|-----------|---------|-----------------|-------|
| BaseComponent | n/a | Foundation | Provides `cn()` and `merge_classes()` |
| ButtonComponent | ✅ Mostly | Good | Has `variant`, `size`, `href`, `disabled` |
| BadgeComponent | ✅ | Good | Clean variant pattern |
| CardComponent | ✅ | Good | Slots for header/footer, padding/radius opts |
| EmptyStateComponent | ✅ | Good | Slots for icon/action, compact mode |
| InputComponent | ✅ | Good | Full form integration, error states |
| SelectComponent | ✅ Mostly | Good | label/hint, but uses `text-foreground` not `text-primary` |
| AutoSelectComponent | ✅ | Good | Composition pattern wrapping SelectComponent |
| RedirectSelectComponent | ✅ | Good | Standalone nav select |
| MultiSelectComponent | ✅ | Good | Chips, filter, panel |
| SpinnerComponent | ✅ | Good | 5 sizes, accessible |
| ToggleButtonComponent | ❌ **Raw colors** | Fair | Uses emerald/zinc raw colors |
| ToggleSwitchComponent | ✅ | Good | Form integration, auto-submit |
| DropdownComponent | ❌ **Raw colors** | Poor | Uses zinc/emerald raw colors throughout |

### Issues

#### [CRITICAL] DropdownComponent uses all raw Tailwind colors

`app/components/ui/dropdown_component.rb:17-28` — Every class string uses raw zinc/emerald colors:

```ruby
# button_classes
"border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs text-zinc-200 hover:border-zinc-500"

# menu_classes
"border-zinc-800 bg-zinc-950 shadow-lg"

# item_classes (selected)
"text-emerald-300 bg-emerald-500/10"

# item_classes (unselected)
"text-zinc-200 hover:bg-zinc-900"
```

**This component completely bypasses the design system.** Should use `bg-surface-2`, `border-border`, `text-foreground`, `text-accent`, etc.

#### [HIGH] ToggleButtonComponent uses raw emerald/zinc colors

`app/components/ui/toggle_button_component.rb:47-51`:

```ruby
# Active state
"border-emerald-500/40 bg-emerald-500/15 text-emerald-300 hover:bg-emerald-500/25"

# Inactive state
"border-zinc-700 bg-zinc-900 text-zinc-300 hover:border-zinc-500 hover:text-zinc-200"
```

Should use `border-accent/40 bg-accent-ghost text-accent` (active) and `border-border bg-surface-2 text-secondary` (inactive).

#### [HIGH] ButtonComponent has inconsistent hover patterns

The `danger` variant uses opacity-based hover (`hover:bg-error/90`) while all other variants use explicit hover colors (`hover:bg-accent-strong`, `hover:bg-surface`). Some inline buttons in views use `hover:bg-accent/80` or `hover:bg-accent/90` instead of the component's `hover:bg-accent-strong`.

- `button_component.rb:46` — `hover:bg-error/90`
- `calendar/index.html.erb:89` — `hover:bg-accent/80`
- `sources/preview.html.erb:34` — `hover:bg-accent/90`
- `sessions/new.html.erb:39` — `hover:bg-accent/90`

#### [MEDIUM] Missing `frozen_string_literal` in some components

`dropdown_component.rb`, `multi_select_component.rb`, `toggle_button_component.rb`, `toggle_switch_component.rb` lack the `frozen_string_literal: true` magic comment that other components have.

#### [MEDIUM] Missing `require_relative "base_component"` in some components

`dropdown_component.rb`, `multi_select_component.rb`, `toggle_button_component.rb`, `toggle_switch_component.rb`, `select_component.rb`, `auto_select_component.rb`, `redirect_select_component.rb` lack the explicit require. Works in Rails autoloading but inconsistent with `button_component.rb`, `badge_component.rb`, etc.

#### [MEDIUM] No component for inline action buttons

26 instances of inline `"inline-flex items-center rounded-md border..."` button patterns in views that don't use `ButtonComponent`. These should be extractable to a variant or a new component.

#### [LOW] CardComponent default radius doesn't match views

`CardComponent` defaults to `radius: :lg` which maps to `rounded-2xl`, but most hand-written cards in views use `rounded-lg`. This mismatch means the component renders differently from the hand-written pattern.

---

## 3. Raw Color/Style Usage in Views

### Violations by file

| File | Raw Color Classes | Severity |
|------|-------------------|----------|
| `series/show.html.erb:139,145,151,157` | `amber-500`, `amber-300`, `rose-500`, `rose-300` | HIGH |
| `series/_chapter_row.html.erb:28,49,51,85,100` | `amber-500`, `amber-200`, `rose-500`, `rose-200`, `sky-500`, `sky-200` | HIGH |
| `calendar/index.html.erb:89` | `hover:bg-accent/80` (inconsistent hover) | MEDIUM |
| `sources/browse.html.erb:109` | `hover:bg-accent/90` (inconsistent hover) | MEDIUM |
| `sources/preview.html.erb:34` | `hover:bg-accent/90` (inconsistent hover) | MEDIUM |
| `sessions/new.html.erb:39` | `hover:bg-accent/90` (inconsistent hover) | MEDIUM |

### Status badge colors use raw values instead of semantic tokens

The `_chapter_row.html.erb` partial uses inline raw colors for download status badges:

```ruby
# :28 — Reading progress: "In progress"
"bg-amber-500/10 text-amber-200 border-amber-500/30"

# :49 — Download: "Failed"
"bg-rose-500/10 text-rose-200 border-rose-500/30"

# :51 — Download: "Ready"
"bg-sky-500/10 text-sky-200 border-sky-500/30"
```

These should map to semantic tokens: `warning-soft`/`warning` for in-progress, `danger-soft`/`danger` for failed, `info-soft`/`info` for ready.

### Cancel/Remove buttons use raw amber/rose

`series/show.html.erb:139-157` — The "Cancel All" and "Remove All" buttons use `amber-500/40`, `amber-300`, `rose-500/40`, `rose-300` instead of `warning`/`danger` tokens.

---

## 4. Repeated UI Patterns (Extraction Candidates)

### 4a. Status Badge Pattern (8+ occurrences)

A `<span>` with `inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-semibold` appears in:
- `_chapter_row.html.erb:30,55` (reading progress, download status)
- `admin/downloads/_download_row.html.erb:18,20,27,29,31` (download statuses)
- `sources/browse.html.erb:80-88` (series status)
- `sources/preview.html.erb:71-78` (series status)

**Recommendation**: Extend `BadgeComponent` with a `bordered` variant or create a `StatusBadgeComponent` that maps status strings to token-based colors.

### 4b. Inline Button Pattern (~26 occurrences)

The pattern `inline-flex items-center rounded-md border border-border/accent/danger px-3 py-1.5 text-sm font-semibold` appears across virtually every view. Most are `button_to` calls with custom classes.

**Recommendation**: Use `ButtonComponent` with appropriate variants. Add `icon` variant support if icons are common (they are — most of these buttons have SVG icons).

### 4c. "No Cover" Placeholder (6 occurrences)

```html
<div class="flex h-full w-full items-center justify-center text-xs uppercase text-muted-2">
  No cover
</div>
```

Found in: `series/index.html.erb:21`, `search/index.html.erb:63`, `sources/search.html.erb:43`, `sources/browse.html.erb:67`, `sources/preview.html.erb:24`, `library/index.html.erb:74`

**Recommendation**: Extract to a `CoverImageComponent` or `SeriesCoverComponent` that handles both the image display and the "no cover" fallback.

### 4d. Search Input with Icon (3 occurrences)

A search input with a magnifying glass icon on the left appears in:
- `library/index.html.erb:31-37`
- `series/show.html.erb:189-196`
- `search/index.html.erb:17` (without icon prefix)

**Recommendation**: Extend `InputComponent` with a `leading_icon` slot.

### 4e. Pagination Pattern (2 occurrences)

Previous/Next pagination with page indicators appears in:
- `sources/browse.html.erb:34-52` (top) and `:118-139` (bottom)
- `admin/downloads/index.html.erb:138-163`

**Recommendation**: Extract to a `PaginationComponent`.

### 4f. Error/Alert Banner (4 occurrences)

```html
<div class="rounded-lg border border-danger/30 bg-danger-soft px-4 py-3 text-sm text-danger">
```

Found in: `sources/browse.html.erb:9`, `sources/search.html.erb:26`, `sources/preview.html.erb:9`, `sessions/new.html.erb:9`

Plus flash messages in `layouts/application.html.erb:42-50` with slightly different styling.

**Recommendation**: Extract to an `AlertComponent` with `variant: :success/:danger/:warning/:info`.

### 4g. Section Header Pattern

```html
<header class="space-y-2">
  <p class="text-sm text-muted">Subtitle</p>
  <h1 class="text-3xl font-semibold text-balance">Title</h1>
  <p class="text-muted text-pretty">Description</p>
</header>
```

Found in: `series/show.html.erb`, `series/index.html.erb`, `sources/browse.html.erb`, `sources/search.html.erb`, `admin/downloads/index.html.erb`, `admin/scrapers/index.html.erb`, `sources/index.html.erb`

**Recommendation**: Extract to a `PageHeaderComponent`.

### 4h. Empty State (inconsistent)

Despite having an `EmptyStateComponent`, most views implement empty states inline:
- `series/show.html.erb:208` — dashed border div with text
- `series/index.html.erb:38` — dashed border with CTA
- `library/index.html.erb:43` — bordered div with SVG icon
- `notifications/index.html.erb:59` — dashed border with SVG icon
- `search/index.html.erb:89` — dashed border centered text
- `admin/downloads/index.html.erb:85` — dashed border centered text

**Only the design system showcase actually uses `EmptyStateComponent`.** This is the biggest missed reuse opportunity.

### 4i. Inline SVG Icons (~40+ occurrences)

Despite having the Lucide `icon` helper (visible in `design_system/show.html.erb`), every view uses inline SVGs. Example: the refresh icon `<path d="M4 4v5h.582m15.356 2A8.001..."` appears 6 times.

**Recommendation**: Replace all inline SVGs with `icon "name"` calls. This is the single highest-ROI cleanup.

---

## 5. Stimulus Controllers

### Inventory (10 controllers)

| Controller | LOC | Complexity | Notes |
|------------|-----|------------|-------|
| `auto_submit_controller.ts` | 10 | Low | Clean, single-purpose |
| `drawer_controller.ts` | 23 | Low | Clean, uses `<dialog>` correctly |
| `dropdown_controller.ts` | 45 | Medium | Good outside-click and escape handling |
| `loading_button_controller.ts` | 18 | Low | Clean, single-purpose |
| `toggle_button_controller.ts` | 39 | Low | Clean hover/default state swap |
| `multi_select_controller.ts` | 172 | High | Complex but well-structured |
| `reader_controller.ts` | 454 | Very High | Full manga reader — keyboard, lightbox, progress, IntersectionObserver |
| `chapter_filter_controller.ts` | 23 | Low | Clean client-side filter |
| `hello_controller.ts` | — | — | Scaffold, should be removed |
| `application.ts` | — | — | Registration file |

### Issues

#### [LOW] `hello_controller.ts` still present

The default Stimulus scaffold controller is still in the codebase. Should be removed.

#### [MEDIUM] `multi_select_controller.ts` creates DOM elements with hardcoded classes

`multi_select_controller.ts:147-167` — Creates chip elements with hardcoded Tailwind classes in JavaScript. If the design tokens change, these chips won't update. Consider using a `<template>` element in the HTML that the controller can clone.

#### [MEDIUM] `dropdown_controller.ts` duplicates click-outside/escape logic with `multi_select_controller.ts`

Both controllers implement `document.addEventListener("click", ...)` for outside-click and `document.addEventListener("keydown", ...)` for escape. This pattern could be extracted into a `Dismissable` mixin or a base `PopoverController`.

---

## 6. Design System Showcase Page

### Strengths
- Comprehensive — covers tokens, components, patterns, guidelines, accessibility, roadmap
- Uses actual ViewComponents for demos (Select, ToggleSwitch, MultiSelect, Spinner, Input, Card, EmptyState, Badge)
- Proper anchor navigation with sticky sidebar
- Beautiful presentation with radial gradients and grid background

### Issues

#### [HIGH] Showcase uses new naming but app uses legacy naming

The showcase demonstrates `text-primary`, `text-secondary`, `text-tertiary` but the actual app exclusively uses `text-foreground`, `text-muted`, `text-muted-2`. This creates a confusing disconnect — the documentation doesn't match reality.

#### [MEDIUM] Showcase buttons are hardcoded HTML, not ButtonComponent

`design_system/show.html.erb:377-380` — Button previews are raw HTML, not rendered via `ButtonComponent`. If the component changes, the showcase won't reflect it.

#### [MEDIUM] Missing components from showcase

The following components exist but aren't demonstrated:
- `RedirectSelectComponent`
- `AutoSelectComponent` (shown only as "auto-applies" mention)
- `DropdownComponent`
- `ToggleButtonComponent`

#### [LOW] Roadmap is stale

Phase 1 and 2 are marked "In progress" but many components (Button, Badge, Spinner, Toggle) are already built. Should be updated to reflect current state.

---

## 7. Font Weight Inconsistency

Most headings use `font-semibold` (consistent with design system), but 4 instances use `font-bold`:

- `calendar/index.html.erb:3` — `<h1 class="text-2xl font-bold">`
- `chapters/show.html.erb:261` — `<h2 class="text-3xl font-bold">`
- `chapters/show.html.erb:279` — countdown badge `font-bold`
- `sessions/new.html.erb:4` — `<h1 class="text-3xl font-bold">`

**Recommendation**: Standardize on `font-semibold` for all headings to match the design system.

---

## Prioritized Recommendations

### P0 — Critical (do first)

1. **Migrate DropdownComponent to design tokens** — Replace all `zinc-*`/`emerald-*` classes with semantic tokens. This is a component that other views depend on.

2. **Decide on text naming and enforce it** — Pick either `text-foreground/muted/muted-2` or `text-primary/secondary/tertiary`. Update CLAUDE.md, the showcase, and all components/views to use one set. Remove the other from `application.css` or mark it deprecated with a comment.

### P1 — High (this sprint)

3. **Migrate ToggleButtonComponent to design tokens** — Replace `emerald-*`/`zinc-*` with `accent-*`/`border`/`surface-2`.

4. **Replace raw amber/rose/sky colors in views with semantic tokens** — `_chapter_row.html.erb` and `series/show.html.erb` status badges and action buttons should use `warning`/`danger`/`info` tokens.

5. **Replace inline SVGs with `icon` helper** — 40+ inline SVGs can be replaced with `icon "name"` calls. Single highest-ROI cleanup for maintainability.

6. **Use EmptyStateComponent everywhere** — 6 views implement empty states inline despite the component existing.

7. **Standardize button hover pattern** — Use `hover:bg-accent-strong` consistently (the component's pattern) instead of `hover:bg-accent/80` or `hover:bg-accent/90` in views.

### P2 — Medium (next sprint)

8. **Extract StatusBadgeComponent** — Encapsulate the `inline-flex rounded-full border px-2 py-0.5` pattern with status-to-color mapping.

9. **Extract AlertComponent** — Encapsulate the `rounded-lg border bg-*-soft text-*` error/success banner pattern.

10. **Extract PageHeaderComponent** — Encapsulate the `header > subtitle + h1 + description` pattern.

11. **Extract CoverImageComponent** — Encapsulate cover display with "no cover" fallback.

12. **Extract PaginationComponent** — Encapsulate the prev/next/page-numbers pattern.

13. **Use more ButtonComponent instances** — 26 inline button patterns across views could use the component instead.

14. **Use `<template>` for multi-select chips** — Instead of hardcoding classes in JavaScript.

15. **Extract Dismissable mixin for Stimulus** — Share click-outside/escape logic between dropdown and multi-select.

### P3 — Low (backlog)

16. **Remove `hello_controller.ts`** — Dead scaffold code.

17. **Standardize font weight** — Replace 4 `font-bold` usages with `font-semibold`.

18. **Remove or clarify `warm` token** — Either differentiate it from `warning` or remove it.

19. **Update showcase roadmap** — Reflect current completion state.

---

## Appendix: Token Usage Heatmap

| Token | Usage Count (views+components) | Notes |
|-------|-------------------------------|-------|
| `text-foreground` | ~80 | Primary text (legacy) |
| `text-muted` | ~70 | Secondary text (legacy) |
| `text-muted-2` | ~50 | Tertiary text (legacy) |
| `text-primary` | ~5 | Primary text (new) — only in components + showcase |
| `text-secondary` | ~5 | Secondary text (new) — only in components + showcase |
| `text-tertiary` | ~3 | Tertiary text (new) — only in components + showcase |
| `bg-surface` | ~30 | Card/panel backgrounds |
| `bg-surface-2` | ~40 | Elevated surfaces |
| `bg-background` | ~15 | Page background |
| `bg-accent` | ~20 | Primary action buttons |
| `border-border` | ~60 | Standard borders |
| `text-accent` | ~15 | Links, action text |
| Raw zinc/emerald/amber/rose/sky | ~25 | **Violations** |
