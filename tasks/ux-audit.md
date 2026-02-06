# Scanarr UX Audit

**Audit date:** February 2026
**Scope:** Every view, layout, component, and interaction pattern in the application
**Methodology:** Code review of all ERB templates, controllers, Stimulus controllers, CSS tokens, and ViewComponents

---

## Table of Contents

1. [Global / Layout](#1-global--layout)
2. [Login Page](#2-login-page)
3. [Sources Index (Home)](#3-sources-index-home)
4. [Source Search](#4-source-search)
5. [Source Browse (Discover)](#5-source-browse-discover)
6. [Source Preview](#6-source-preview)
7. [Series Index (per source)](#7-series-index-per-source)
8. [Series Show](#8-series-show)
9. [Chapter Reader](#9-chapter-reader)
10. [Library](#10-library)
11. [Calendar](#11-calendar)
12. [Global Search](#12-global-search)
13. [Notifications](#13-notifications)
14. [Admin: Downloads](#14-admin-downloads)
15. [Admin: Scrapers](#15-admin-scrapers)
16. [Design System](#16-design-system)
17. [Cross-Cutting Concerns](#17-cross-cutting-concerns)
18. [Prioritized Recommendations](#18-prioritized-recommendations)

---

## 1. Global / Layout

**File:** `app/views/layouts/application.html.erb`, `app/views/shared/_sidebar_nav.html.erb`

### Strengths
- Clean sidebar + content grid layout with responsive drawer on mobile
- Consistent semantic color tokens throughout
- Mobile navigation uses `<dialog>` element (good native accessibility)
- `aria-label` on hamburger and close buttons
- `aria-current="page"` for active nav links

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 1.1 | **No `<html lang>` attribute** | High | `<html>` tag missing `lang="en"` — required for screen readers and search engines |
| 1.2 | **No skip-to-content link** | Medium | Keyboard users must tab through the entire sidebar before reaching main content |
| 1.3 | **Flash messages lack dismiss/auto-hide** | Medium | Success/error banners persist until page reload; no close button and no auto-fade |
| 1.4 | **Flash not announced to screen readers** | Medium | Missing `role="alert"` or `aria-live="polite"` on flash containers |
| 1.5 | **Nav order: "Library" first but home is "Sources"** | Low | Sidebar lists Library, Calendar, Home, Search — "Home" should likely be first or have a clearer label since the root path is Sources |
| 1.6 | **Notification dropdown position on mobile** | Medium | The dropdown is `absolute left-0 top-full w-80` inside the sidebar footer — on narrow viewports this may overflow or be cut off |
| 1.7 | **Notification dropdown opens on click but has no "Escape" handler** | Low | `dropdown_controller` manages open/close, but there's no visible keyboard close (Escape key support should be verified in the controller) |
| 1.8 | **Design System link in admin nav** | Low | Developer-only page exposed in the sidebar. Consider hiding in production or moving to a hidden route |
| 1.9 | **No breadcrumb on most pages** | Medium | Only Preview and Chapter Reader have breadcrumbs. Series index, library, etc. have no way to orient yourself within the app hierarchy |
| 1.10 | **Mobile header shows app name but no current page title** | Low | Mobile header only says "Scanarr" — no context about which page you're on |

---

## 2. Login Page

**File:** `app/views/sessions/new.html.erb`

### Strengths
- Clean centered design with proper focus management (`autofocus`)
- Uses `autocomplete` attributes for username/password
- Clear error display for failed auth
- Uses `minimal.html.erb` layout (no sidebar clutter)

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 2.1 | **Default credentials shown publicly** | Medium | "Default credentials: `scanarr` / `ilovemanga`" displayed on the login screen. Fine for dev, should be removed/hidden in production |
| 2.2 | **No focus ring on submit button** | Low | Button has `:focus:ring-2` but no visible focus ring on inputs (`focus:ring-1` via `focus:ring-accent`) |
| 2.3 | **No "remember me" option** | Low | Session-only auth; no persistent sessions. May be fine for a self-hosted app |

---

## 3. Sources Index (Home)

**File:** `app/views/sources/index.html.erb`

### Strengths
- Clear header with descriptive subtitle
- Each source shows name, URL, and three distinct CTAs

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 3.1 | **Too many buttons per source card** | Medium | Three CTAs (Discover, View Series, Search) per card creates decision fatigue. "Discover" and "Search" compete visually |
| 3.2 | **No empty state** | Medium | If no sources are enabled, the page shows nothing — no helpful message or guidance |
| 3.3 | **"Discover" vs "View Series" vs "Search" not clear** | Medium | "Discover" = browse, "View Series" = imported series index, "Search" = source search. These labels don't clearly communicate the distinction |
| 3.4 | **Source card doesn't link anywhere on click** | Low | The entire card is not clickable — only the buttons are. Users may try to click the card itself |
| 3.5 | **`border-border-soft` and `bg-accent-ghost`** | Low | Uses design tokens inconsistently — `border-border-soft` not present in all other similar contexts |
| 3.6 | **Page uses `<main>` inside a `<main>` context** | Low | Layout yields into a `<main>` container, but this template also wraps in `<main>`, creating nested `<main>` tags (invalid HTML) |

---

## 4. Source Search

**File:** `app/views/sources/search.html.erb`

### Strengths
- Clean search form with label and placeholder
- Good error display with danger border/background
- Result count shown
- Import button per result

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 4.1 | **No loading state during search** | Medium | Form submits as full page GET — no spinner or "Searching..." feedback. Can feel slow for API-backed searches |
| 4.2 | **No "back to source" link** | Low | Only breadcrumb is the source name in the header subtitle; no explicit back navigation |
| 4.3 | **Import button has no loading feedback** | Medium | `button_to` submits a POST but no visual indication it's working (no `turbo_submits_with`) |
| 4.4 | **Empty state too sparse** | Low | Just "No results." — could suggest checking spelling or trying different terms |
| 4.5 | **Search form doesn't auto-focus** | Low | No `autofocus` on the text input; user must click to start typing |

---

## 5. Source Browse (Discover)

**File:** `app/views/sources/browse.html.erb`

### Strengths
- Beautiful grid layout with cover images
- Hover overlay with description and quick actions (Details + Import)
- Pagination at both top and bottom
- Lazy loading on images
- Status badges (Ongoing/Completed/Hiatus)

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 5.1 | **Hover overlay is desktop-only** | High | The description and action buttons (`opacity-0 group-hover:opacity-100`) are completely inaccessible on touch devices. No tap interaction defined |
| 5.2 | **Grid cards not keyboard accessible** | High | No `tabindex`, no focus state on cards. Keyboard users cannot reach the Details/Import buttons hidden in the hover overlay |
| 5.3 | **No breadcrumb** | Low | No link back to Sources index |
| 5.4 | **Hardcoded page size (24)** | Low | `@results.size >= 24` used to determine if "Next" shows — coupling view logic to adapter pagination |
| 5.5 | **No loading state for pagination** | Low | Page transitions are full-page loads with no loading indicator |

---

## 6. Source Preview

**File:** `app/views/sources/preview.html.erb`

### Strengths
- Excellent detail layout: cover image, metadata, tags, synopsis, chapters
- Breadcrumb navigation
- "Import to Library" as clear primary CTA
- External link with proper `target="_blank"` and `rel="noopener"`
- Truncated alt titles with "+N more"

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 6.1 | **Import button has no loading feedback** | Medium | No `turbo_submits_with` or spinner — user doesn't know import is working |
| 6.2 | **Error state only shows text** | Low | Error message and "Back to Browse" link is fine, but could benefit from an icon for visual weight |
| 6.3 | **Chapter list not scrollable** | Low | If there are 10 chapters, the list can be long on small screens. Consider collapsible or max-height with scroll |

---

## 7. Series Index (per source)

**File:** `app/views/series/index.html.erb`

### Strengths
- Card grid with cover images, titles, authors
- Chapter count shown per series
- Good empty state with CTA to search
- Hover effects on cards

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 7.1 | **N+1 query on chapter count** | Medium | `series.chapters.count` triggers a query per series. Should be preloaded as a counter cache or `GROUP BY` |
| 7.2 | **No search/filter** | Medium | If a source has many imported series, there's no way to find one without scrolling |
| 7.3 | **No pagination** | Medium | All series loaded at once. Could be problematic with many imports |
| 7.4 | **No breadcrumb** | Low | No way back to Sources index |
| 7.5 | **Cover image alt text good** | N/A | Includes series title — well done |

---

## 8. Series Show

**File:** `app/views/series/show.html.erb`, `app/views/series/_chapter_row.html.erb`

### Strengths
- Rich header with cover, metadata, description (expandable)
- Follow/unfollow toggle with auto-download switch
- Chapter filter/search
- Download All with progress counts
- Real-time updates via Turbo Streams
- Reading style selector
- Chapter status badges (Completed, In Progress, Ready, Failed, etc.)
- Bulk actions (Cancel All, Remove All, Download All) with confirmation dialogs

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 8.1 | **Header layout breaks on mobile** | High | `header class="flex gap-6"` with a fixed 144px cover image doesn't wrap on narrow screens. Should be `flex-col sm:flex-row` |
| 8.2 | **Action bar too dense** | Medium | Cancel All, Remove All, Download All buttons + filter search all crammed into one row. On tablet widths this wraps ungracefully |
| 8.3 | **No breadcrumb** | Medium | No way to navigate back to source or Sources index from this page |
| 8.4 | **Chapter row actions are inconsistent widths** | Low | Download/Re-download/Cancel/Remove buttons vary in width causing visual jitter |
| 8.5 | **"(Cannot follow - no library series linked)"** | Medium | User-facing technical error. Should either auto-create the library link or provide a clearer action |
| 8.6 | **Hardcoded amber/rose colors in buttons** | Medium | Uses `border-amber-500/40`, `text-amber-300`, `border-rose-500/40`, `text-rose-300` instead of design tokens (`warning`, `danger`). Inconsistent with design system |
| 8.7 | **Download All disabled state not clearly distinct** | Low | Disabled button uses `bg-surface-2 text-muted cursor-not-allowed` — could benefit from visual distinction like opacity |
| 8.8 | **Long chapter lists have no virtualization or pagination** | Medium | All chapters rendered at once. A series with 1000+ chapters will create a very long DOM |
| 8.9 | **Chapter row has hardcoded amber/rose/sky colors** | Medium | `_chapter_row.html.erb` uses `bg-amber-500/10 text-amber-200`, `bg-rose-500/10 text-rose-200`, `bg-sky-500/10 text-sky-200` — should use semantic tokens like `warning-soft`, `danger-soft`, `info-soft` |
| 8.10 | **Reading style "Webcomic" has no tooltip/description** | Low | Users may not understand the difference between Long Strip and Webcomic |

---

## 9. Chapter Reader

**File:** `app/views/chapters/show.html.erb`

### Strengths
- Excellent breadcrumb navigation
- Sticky progress bar with page count and percentage
- Multiple reading modes (LTR, RTL, Long Strip, Webcomic)
- Lightbox mode for horizontal reading
- Next chapter overlay with countdown and auto-advance
- Progress tracking via API
- Previous/Next chapter navigation
- Graceful error handling (source unavailable, rate limits)
- Source fallback when no downloaded pages exist
- Keyboard navigation support in reader controller

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 9.1 | **No fullscreen mode** | Medium | Manga readers typically expect fullscreen. The sidebar and header take up space |
| 9.2 | **Control bar wraps poorly** | Medium | Lightbox, Previous, Next, Download, Reading Style — all in one `flex-wrap` row. On mobile this creates 2-3 rows |
| 9.3 | **No gesture/swipe support** | Medium | Mobile readers expect swipe left/right to change pages in horizontal mode |
| 9.4 | **Progress bar z-index could conflict** | Low | `z-2` may be overridden by other sticky/fixed elements |
| 9.5 | **"Streaming from source while download completes" message is confusing** | Medium | Shows when `@pages.empty? && @source_pages.empty?` — but the message implies streaming is happening when actually there's no content to show |
| 9.6 | **Next chapter overlay `bg-background/98`** | Low | 98% opacity means a tiny sliver of content shows through. Use `bg-background` (100%) for cleaner look |
| 9.7 | **Lightbox has no keyboard instructions** | Low | Arrow keys and Escape work (via controller) but no visual hint for the user |
| 9.8 | **Download button text doesn't update after download completes** | Medium | After clicking download, the button still shows old state until page reload. No Turbo Stream update for this |
| 9.9 | **No preloading of next/previous pages** | Low | In horizontal mode, could preload adjacent pages for smoother scrolling |

---

## 10. Library

**File:** `app/views/library/index.html.erb`

### Strengths
- Clean grid layout with cover images
- Download progress overlay per series (downloaded/total + downloading count)
- Source badge in top-right of cover
- Filter by status (All/Downloaded/In Progress/Not Downloaded)
- Search within library
- Good empty state with icon and contextual message
- "Clear filters" link when filtering

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 10.1 | **No pagination** | Medium | All series loaded into memory (`@series.to_a`) then filtered. Won't scale past ~100 series |
| 10.2 | **Status filter is tab-style but uses query params** | Low | Each "tab" is a full page navigation. Could be smoother with Turbo Frames |
| 10.3 | **Search doesn't persist across filter changes** | Low | Clicking a status filter after searching preserves `params[:q]` — good. But the search field doesn't auto-submit on type; requires Enter or button click |
| 10.4 | **Missing "following" indicator** | Medium | Library doesn't show which series the user follows. The follow/unfollow state is only on the Series Show page |
| 10.5 | **Grid inconsistency with Browse page** | Low | Library uses `grid-cols-2 sm:3 md:4 lg:5` but Browse uses `grid-cols-2 sm:3 md:4 lg:6`. Slight inconsistency |
| 10.6 | **No sort options** | Low | Can't sort by latest update, alphabetical, download status, etc. |
| 10.7 | **Dead link when no primary source** | Low | `series_path` falls back to `"#"` when there's no source — clicking does nothing, which is confusing |

---

## 11. Calendar

**File:** `app/views/calendar/index.html.erb`

### Strengths
- Three view types (Week/Month/Recent) with toggle
- Source filter dropdown
- Cover images per chapter entry
- "Today" badge
- Good empty state with contextual CTA (follow series or wait)

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 11.1 | **Styling inconsistent with rest of app** | High | Uses raw Tailwind classes like `text-2xl font-bold`, `bg-surface-2 rounded-lg overflow-hidden` without the app's usual `space-y-6` header pattern. Feels like a different design language |
| 11.2 | **No `max-w-6xl mx-auto` — wait, it has it** | N/A | Actually uses inline `max-w-6xl mx-auto px-4 py-8` which duplicates the layout's `<main>` padding — resulting in **double padding** |
| 11.3 | **Cover image uses `<img src>` instead of `image_tag`** | Medium | Line 57: `<img src="<%= chapter.series.cover_url %>">` — uses raw `cover_url` (external URL) instead of locally stored cover. Inconsistent with Library which uses `cover_image_url` |
| 11.4 | **No responsive handling for header controls** | Medium | View toggle + source filter are in a `flex gap-4` row that doesn't wrap on mobile |
| 11.5 | **View toggle doesn't use design tokens** | Low | Active state uses `bg-accent` but inactive uses `bg-surface-2` without `border-border` pattern used elsewhere |
| 11.6 | **"Read" button per chapter is redundant** | Low | The chapter title/number is already a link — the "Read" button just adds visual noise |
| 11.7 | **Date format is verbose** | Low | `"Friday, January 31, 2026"` takes a lot of horizontal space. Consider shorter format or responsive format |
| 11.8 | **No week navigation** | Medium | In "Week" view, there's no way to navigate to previous/next week. Stuck on current week only |

---

## 12. Global Search

**File:** `app/views/search/index.html.erb`

### Strengths
- Multi-source search with selectable sources
- Source badge per result
- Grid layout with cover images
- Error reporting per source
- Good empty state with "Clear search" link
- Autofocus on search input

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 12.1 | **No loading indicator during search** | Medium | Full page reload for results with no feedback. Multi-source search can be slow |
| 12.2 | **Results not grouped by source** | Low | Results from all sources are intermixed. Could optionally group by source for easier scanning |
| 12.3 | **Import button has no loading state** | Medium | Same as Source Search — no `turbo_submits_with` feedback |
| 12.4 | **No keyboard shortcut to focus search** | Low | Common pattern: `/` to focus search field |

---

## 13. Notifications

**File:** `app/views/notifications/index.html.erb`

### Strengths
- Clean list design with cover thumbnails
- Read/unread visual distinction via opacity
- "Mark all as read" action
- Per-notification mark-as-read button
- Good empty state with bell icon and helpful text
- "Read" link to navigate directly to the chapter

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 13.1 | **Hardcoded limit of 50** | Low | No pagination. Users with many notifications only see latest 50 |
| 13.2 | **No notification grouping** | Low | If a series has 20 new chapters, they show as 20 individual notifications. Could group by series |
| 13.3 | **Read notification still shows mark-as-read icon** | Low | Read notifications (`opacity-60`) still have the checkmark button... wait, no — `unless notification.read?` gates it. Good |
| 13.4 | **No real-time updates** | Low | No Turbo Stream subscription. New notifications only appear on page reload |
| 13.5 | **Notification page duplicates sidebar dropdown content** | Low | Sidebar dropdown shows notifications too. The full page adds limited value over the dropdown |

---

## 14. Admin: Downloads

**File:** `app/views/admin/downloads/index.html.erb`, `app/views/admin/downloads/_download_row.html.erb`

### Strengths
- Dashboard with stat cards (Queued/Downloading/Complete/Failed)
- Cover images section with refresh action
- Filter by status with clear filter link
- Paginated table
- Real-time updates via Turbo Streams
- Stuck download detection (10+ min no progress)
- Bulk restart actions (stuck and failed)
- Per-download restart button
- Progress bar per download
- Cancelled downloads hidden by default

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 14.1 | **Table not responsive** | High | Full `<table>` doesn't work on mobile — horizontal overflow without scrolling container. Needs `overflow-x-auto` wrapper or card layout on small screens |
| 14.2 | **No auto-refresh for stats** | Medium | Stats section doesn't update in real-time. The download rows update via Turbo, but the aggregate counts at the top are stale until refresh |
| 14.3 | **Error column truncation** | Low | Errors truncated to 50 chars with full text only on hover (`title` attribute). Mobile users can't hover |
| 14.4 | **Pagination doesn't preserve status filter** | Low | Actually it does: `url_for(page: ..., status: params[:status])`. Good |
| 14.5 | **"Unknown" shown for orphaned downloads** | Low | If series/chapter deleted, shows "Unknown". No link to investigate |

---

## 15. Admin: Scrapers

**File:** `app/views/admin/scrapers/index.html.erb`

### Strengths
- Two clear sections: Sources list and Recent Runs
- Three filter dropdowns for runs (Source, Status, Run Type)
- "Run smoke test" per source

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 15.1 | **Table not responsive** | High | Same table responsiveness issue as Downloads |
| 15.2 | **Stats column shows raw JSON** | Medium | `run.stats_json&.to_json` renders raw JSON in the table cell. Should be formatted or summarized |
| 15.3 | **No pagination on Recent Runs** | Medium | All runs loaded without limit or pagination |
| 15.4 | **No empty state for Recent Runs** | Low | If no runs exist, the table just shows headers with no body |
| 15.5 | **Smoke test button has no loading feedback** | Medium | `button_to` with no `turbo_submits_with` — user doesn't know test is running |
| 15.6 | **Started time not formatted** | Low | `run.started_at` renders raw datetime. Should be formatted like `"%Y-%m-%d %H:%M"` like Downloads |
| 15.7 | **No status badges** | Low | Run status shown as plain text instead of colored badges like Downloads |

---

## 16. Design System

**File:** `app/views/design_system/show.html.erb`

### Strengths
- Comprehensive documentation of tokens, components, and patterns
- Interactive component previews (select, toggle, multi-select, spinner)
- Side navigation with section anchors
- Responsive fallback to pill navigation on mobile
- Accessibility guidelines documented
- Roadmap section with phase tracking
- Beautiful visual design with gradient backgrounds

### Issues

| # | Issue | Severity | Details |
|---|-------|----------|---------|
| 16.1 | **Text hierarchy uses `text-primary`/`text-secondary`/`text-tertiary` but views use `text-foreground`/`text-muted`/`text-muted-2`** | High | Design system documents new naming convention, but all views still use legacy aliases. Creates confusion |
| 16.2 | **Dev-only page accessible to all users** | Low | Should be behind a feature flag or restricted route in production |
| 16.3 | **Nested `<main>` tag issue** | Low | Same as Sources — wraps in no explicit main, but layout already provides one |

---

## 17. Cross-Cutting Concerns

### Empty States

| Page | Has Empty State? | Quality |
|------|-----------------|---------|
| Sources Index | No | Missing |
| Source Search (no results) | Yes | Minimal ("No results.") |
| Source Browse (no results) | Yes | Good (dashed border) |
| Series Index (no imports) | Yes | Good (CTA to search) |
| Series Show (no chapters) | Yes | Good (dashed border) |
| Library (no series) | Yes | Excellent (icon + contextual message + CTA) |
| Library (filter no match) | Yes | Good (with clear filter link) |
| Calendar (no releases) | Yes | Good (contextual message) |
| Global Search (no results) | Yes | Good (suggestions + clear link) |
| Notifications (none) | Yes | Good (icon + helpful text) |
| Admin Downloads (none) | Yes | Minimal ("No downloads yet.") |
| Admin Scrapers (no runs) | No | Missing |

### Loading States

| Interaction | Loading Feedback | Quality |
|-------------|-----------------|---------|
| Import series | None | **Missing** |
| Download chapter | `turbo_submits_with: "Queuing..."` | Good |
| Download All | Loading button controller with spinner | Good |
| Search (source-specific) | None | **Missing** |
| Search (global) | None | **Missing** |
| Browse pagination | None | **Missing** |
| Run smoke test | None | **Missing** |
| Refresh metadata | None | **Missing** |
| Refresh cover | None | **Missing** |

### Consistency Audit

| Pattern | Consistent? | Notes |
|---------|------------|-------|
| Page headers | Mostly | Calendar breaks the pattern (different heading style, double padding) |
| Card borders | Mostly | Some use `border-border`, others `border-border/80` |
| Button styles | Mostly | Some use ViewComponent `UI::ButtonComponent`, most use raw Tailwind |
| Status badges | No | Chapter row uses hardcoded `amber/rose/sky` colors; Downloads use semantic tokens |
| Empty states | No | Mix of minimal text, dashed borders, icon-centered layouts |
| Table design | Yes | Admin pages use consistent table styling |
| Form inputs | Mostly | Some inputs use `bg-background`, others `bg-surface-2` |
| Pagination | No | Browse uses link-style, Downloads uses numbered. No shared component |

### Accessibility Summary

| Aspect | Status | Details |
|--------|--------|---------|
| `lang` attribute | Missing | `<html>` needs `lang="en"` |
| Skip to content | Missing | No skip link |
| Focus management | Partial | Good on forms; missing on cards, browse grid |
| ARIA landmarks | Good | `<main>`, `<nav>`, `<aside>` used correctly |
| Image alt text | Good | All images have alt text or are marked decorative |
| Color contrast | Good | Dark theme with high-contrast text tokens |
| Keyboard navigation | Partial | Form controls good; browse cards, notification dropdown need work |
| Touch targets | Mostly good | Some small icon buttons (mark-as-read) may be under 44px |
| Screen reader | Partial | `aria-label` on some buttons, missing `role="alert"` on flash |

---

## 18. Prioritized Recommendations

### Quick Wins (< 1 hour each)

1. **Add `lang="en"` to `<html>` tag** — One-line fix in `application.html.erb` [1.1]
2. **Add `role="alert"` to flash messages** — One-line fix [1.4]
3. **Add skip-to-content link** — Small HTML addition in layout [1.2]
4. **Fix nested `<main>` tags** — Remove `<main>` wrapper from individual page templates; the layout provides it [3.6]
5. **Add `turbo_submits_with` to all Import buttons** — Simple attribute addition across search/browse/preview [4.3, 6.1, 12.3]
6. **Add loading feedback to smoke test button** — Add `turbo_submits_with` [15.5]
7. **Fix Calendar double padding** — Remove `max-w-6xl mx-auto px-4 py-8` from calendar template; layout already provides it [11.2]
8. **Format scraper run started_at time** — Use `.strftime` [15.6]
9. **Replace raw JSON stats with formatted output** — Parse and display key stats [15.2]
10. **Add empty state for Sources index** — Show message when no sources enabled [3.2]
11. **Add empty state for admin scraper runs** — Show message when no runs [15.4]
12. **Reorder sidebar nav** — Move "Home" to first position or rename to "Sources" [1.5]

### Medium Effort (1-4 hours each)

13. **Fix series show header for mobile** — Change `flex gap-6` to `flex-col gap-4 sm:flex-row sm:gap-6` [8.1]
14. **Replace hardcoded amber/rose/sky colors with semantic tokens** — Update `_chapter_row.html.erb` and series show bulk action buttons [8.6, 8.9]
15. **Make browse cards keyboard accessible** — Add `tabindex`, focus states, and tap interaction for mobile [5.1, 5.2]
16. **Wrap admin tables in `overflow-x-auto`** — Quick fix for table responsiveness [14.1, 15.1]
17. **Add status badges to scraper runs** — Use the same badge pattern as downloads [15.7]
18. **Calendar styling alignment** — Restyle calendar to match app-wide header/spacing patterns [11.1]
19. **Add breadcrumbs to Series Index and Series Show** — Consistent with Preview and Reader [1.9, 7.4, 8.3]
20. **Fix notification dropdown mobile overflow** — Constrain width and position [1.6]
21. **Add flash message dismiss button** — Small Stimulus controller for auto-hide or X button [1.3]
22. **Add pagination to admin scraper runs** — Use Kaminari like downloads [15.3]
23. **Add week navigation to Calendar** — Previous/Next week buttons in "Week" view [11.8]
24. **Use `cover_image_url` in Calendar** — Use locally cached cover instead of external `cover_url` [11.3]
25. **Make "Cannot follow" message actionable** — Auto-create library series link or show import CTA [8.5]

### Large Effort (4+ hours each)

26. **Migrate all views from legacy text tokens to primary/secondary/tertiary** — Design system defines new convention but views use old names [16.1]
27. **Extract shared pagination component** — Unify Browse, Downloads, and future pagination into a ViewComponent [Consistency]
28. **Extract shared empty state component usage** — Use `UI::EmptyStateComponent` across all empty states [Consistency]
29. **Add Turbo Frames to Library filters** — Replace full page reloads with partial updates [10.2]
30. **Add series pagination in Library** — Server-side pagination with Kaminari instead of loading all into memory [10.1]
31. **Chapter list pagination/virtualization** — For series with 500+ chapters, add lazy loading or pagination [8.8]
32. **Add loading indicators to search pages** — Turbo frame with spinner for search results [4.1, 12.1]
33. **Add fullscreen reader mode** — Hide sidebar/header when reading; auto-show on mouse move [9.1]
34. **Add swipe gesture support** — Touch event handling for horizontal reader mode [9.3]
35. **Extract all raw Tailwind button patterns into `UI::ButtonComponent` usage** — Currently most buttons are raw classes [Consistency]
36. **Add following indicator to Library grid** — Show heart/star icon on followed series [10.4]
37. **Group notifications by series** — Collapse multiple chapters from same series [13.2]

---

## Architecture Notes

### What's Working Well
- **Design token system** is solid — CSS custom properties with semantic naming
- **ViewComponent library** is growing and well-structured
- **Turbo Streams** used effectively for real-time download progress
- **Stimulus controllers** are focused and well-named
- **Dark theme** is consistent and readable
- **Error handling** is thorough across scrapers, downloads, and readers
- **Mobile-first layout** with responsive sidebar/drawer

### Key Architectural Debts
1. **Token inconsistency** — Design system documents `text-primary/secondary/tertiary` but all views use `text-foreground/muted/muted-2`. Need to pick one and migrate.
2. **Component adoption** — Many UI patterns (buttons, badges, cards, empty states) are hand-rolled in templates. The `UI::` component library exists but isn't universally used.
3. **Calendar is the outlier** — Different styling approach, external image URLs, redundant wrapper. Needs alignment pass.
4. **No shared pagination** — Three different pagination implementations.
