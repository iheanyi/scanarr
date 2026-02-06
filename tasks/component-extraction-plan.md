# Component & Stimulus Extraction Plan

> Thorough analysis of Scanarr's views, existing components, and Stimulus controllers to identify reusable extraction opportunities.

---

## 1. Current Component Inventory

### ViewComponents (14 total in `app/components/ui/`)

| Component | Purpose | Variants/Slots | Used In |
|---|---|---|---|
| `BaseComponent` | Abstract base class with `cn()` / `merge_classes()` helpers | — | All components inherit |
| `BadgeComponent` | Status pill labels | `:success`, `:warning`, `:danger/:error`, `:info`, `:accent`, `:default` | Limited direct use — inline badge HTML is more common |
| `ButtonComponent` | Action buttons (also supports link mode) | `:primary`, `:secondary`, `:ghost`, `:danger` + sizes `:sm/:default/:lg` | `series/show`, design system |
| `CardComponent` | Container with optional header/footer slots | `padding:`, `radius:`, `interactive:`, `elevated:` | Design system showcase |
| `DropdownComponent` | Toggle menu with items | `align: :left/:right` | Sidebar nav notifications |
| `EmptyStateComponent` | Zero-state messaging | `compact:` mode, `icon` + `action` slots | Design system showcase |
| `InputComponent` | Text inputs with label/hint/error | Form-builder or standalone, sizes | Design system showcase |
| `SelectComponent` | Form select with custom styling | Sizes, `full_width:`, label/hint | Browse, Admin downloads, Admin scrapers, Design system |
| `AutoSelectComponent` | Select that auto-submits on change | Wraps `SelectComponent` with auto-submit data attrs | Series show, Chapter reader |
| `RedirectSelectComponent` | Standalone select that navigates to URL | Sizes | Calendar page |
| `MultiSelectComponent` | Multi-checkbox select with chips | Filter, chips, count display | Search page |
| `SpinnerComponent` | Loading indicator SVG | Sizes: `:xs` to `:xl` | Design system showcase |
| `ToggleButtonComponent` | Follow/Unfollow style button with hover state | Active/inactive labels, form action | Series show (follow) |
| `ToggleSwitchComponent` | Checkbox toggle switch for settings | `auto_submit:`, description text | Series show (auto-download) |

### Stimulus Controllers (9 total in `app/javascript/controllers/`)

| Controller | Purpose | Used By |
|---|---|---|
| `auto-submit` | Submit closest form on change event | `AutoSelectComponent`, `ToggleSwitchComponent` |
| `drawer` | Mobile sidebar dialog open/close/backdrop | Application layout |
| `dropdown` | Toggle menu visibility, click-outside close, Escape close | `DropdownComponent`, sidebar notifications |
| `loading-button` | Disable + show spinner on submit | Series show "Download All" |
| `multi-select` | Panel toggle, filter, chips, checkbox state | `MultiSelectComponent` |
| `reader` | Full chapter reader (page navigation, progress, lightbox, keyboard, next-chapter) | Chapter show |
| `toggle-button` | Hover label swap for follow/unfollow | `ToggleButtonComponent` |
| `chapter-filter` | Client-side text filter for chapter list | Series show |
| `hello` | Placeholder/demo | Unused |

---

## 2. Proposed New ViewComponents (Prioritized by Impact)

### Priority 1 — High Frequency, High Impact

#### 2.1 `UI::PageHeaderComponent`
**Pattern**: Every page starts with an identical header structure: optional breadcrumb text, h1 title, description paragraph.

**Current duplication** (appears in **12+ views**):
```erb
<header class="space-y-2">
  <p class="text-sm text-muted">Source Name</p>
  <h1 class="text-3xl font-semibold text-balance">Page Title</h1>
  <p class="text-muted text-pretty">Description text.</p>
</header>
```

**Found in**: `sources/index`, `sources/browse`, `sources/search`, `sources/preview`, `series/index`, `admin/downloads/index`, `admin/scrapers/index`, `search/index`, `library/index`, `notifications/index`, `calendar/index`

**Proposed API**:
```ruby
# Props: title (required), description (optional), breadcrumb (optional)
# Slots: actions (for header-right buttons), breadcrumb (for custom breadcrumbs)
<%= render UI::PageHeaderComponent.new(
  title: "Browse",
  description: "Discover new series from this source.",
  breadcrumb: @source.name
) %>
```

**Estimated reuse**: 12+ pages
**Complexity**: Low

---

#### 2.2 `UI::StatusBadgeComponent`
**Pattern**: Status badge with conditional color mapping. Currently, every view manually builds case/when for download status, series status, progress status, etc. with inline Tailwind classes.

**Current duplication** (appears in **6+ partials**):
```erb
<%# Pattern 1: Download status in chapter_row.html.erb %>
<% label_classes = case file_asset.download_status
                   when "downloading" then "bg-accent-soft text-accent border-accent/30"
                   when "failed" then "bg-rose-500/10 text-rose-200 border-rose-500/30"
                   ... end %>
<span class="inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-semibold <%= label_classes %>">

<%# Pattern 2: Series status in browse.html.erb and preview.html.erb %>
<%= case result.status.to_s.downcase
    when 'ongoing' then 'bg-info-soft text-info'
    when 'completed' then 'bg-success-soft text-success'
    ... end %>

<%# Pattern 3: Download status in admin/downloads/_download_row.html.erb %>
<span class="inline-flex items-center rounded-full bg-warning-soft px-2 py-0.5 text-xs font-medium text-warning">Queued</span>
```

**Found in**: `series/_chapter_row`, `sources/browse`, `sources/preview`, `admin/downloads/_download_row`, `calendar/index` (roadmap badges in design_system)

**Proposed API**:
```ruby
# Extends BadgeComponent with a `status:` shorthand for common mappings
<%= render UI::StatusBadgeComponent.new(status: :downloading) %>
<%= render UI::StatusBadgeComponent.new(status: :ongoing) %>
<%= render UI::StatusBadgeComponent.new(status: :complete, label: "Ready") %>

# Predefined status maps:
# :downloading → accent/soft, :failed → danger, :complete → info
# :queued → warning, :cancelled → muted
# :ongoing → info, :completed → success, :hiatus → warning
```

**Estimated reuse**: 10+ locations
**Complexity**: Low (extends existing `BadgeComponent`)

---

#### 2.3 `UI::SeriesCoverComponent`
**Pattern**: Cover image with fallback "No cover" placeholder. This exact pattern appears in nearly every view that shows a series.

**Current duplication** (appears in **9+ templates**):
```erb
<%# Pattern: conditional image with no-cover fallback %>
<% if series.cover_image_url.present? %>
  <%= image_tag series.cover_image_url, class: "h-full w-full object-cover", alt: ... %>
<% else %>
  <div class="flex h-full w-full items-center justify-center ...">
    <span class="text-xs uppercase text-muted-2">No cover</span>
  </div>
<% end %>
```

**Found in**: `library/index` (grid cards), `series/index` (list cards), `series/show` (hero), `sources/browse` (grid), `sources/preview` (sidebar), `sources/search` (list), `search/index` (grid), `calendar/index`, `notifications/index`

**Proposed API**:
```ruby
<%= render UI::SeriesCoverComponent.new(
  url: series.cover_image_url,
  alt: series.canonical_title,
  size: :md,          # :sm (48x64), :md (96x128), :lg (144x192), :xl (custom)
  aspect: "2/3",      # default
  rounded: :lg
) %>
```

**Estimated reuse**: 9+ templates
**Complexity**: Low

---

#### 2.4 `UI::SearchInputComponent`
**Pattern**: Search text field with magnifying glass icon. Repeated 3+ times with minor variations.

**Current duplication**:
```erb
<%# library/index %>
<div class="relative">
  <svg ...magnifying glass icon... />
  <input type="text" placeholder="Search library..." class="w-full rounded-lg border border-border bg-surface-2 py-2 pl-10 pr-4 text-sm ..." />
</div>

<%# series/show (chapter filter) %>
<div class="relative flex-1">
  <svg ...magnifying glass icon... />
  <input type="text" placeholder="Filter chapters..." class="w-full rounded-lg border border-border bg-surface-2 py-2 pl-9 pr-3 text-sm ..." />
</div>
```

**Found in**: `library/index`, `series/show` (chapter filter), `search/index`, `sources/search`

**Proposed API**:
```ruby
<%= render UI::SearchInputComponent.new(
  placeholder: "Search library...",
  name: :q,
  value: params[:q],
  data: { chapter_filter_target: "input", action: "input->chapter-filter#filter" }
) %>
```

**Estimated reuse**: 4+ templates
**Complexity**: Low

---

#### 2.5 `UI::FlashMessageComponent`
**Pattern**: Flash notice/alert banners. Appears in layout and login page with similar but inconsistent styling.

**Current duplication**:
```erb
<%# application.html.erb %>
<div class="rounded-lg border border-success-soft bg-success-soft px-4 py-3 text-sm text-success">
  <%= flash[:notice] %>
</div>
<div class="rounded-lg border border-danger-soft bg-danger-soft px-4 py-3 text-sm text-danger">
  <%= flash[:alert] %>
</div>

<%# Also: error banners in browse.html.erb, search.html.erb, preview.html.erb %>
<div class="rounded-lg border border-danger/30 bg-danger-soft px-4 py-3 text-sm text-danger">
  <%= @error %>
</div>
```

**Found in**: `layouts/application`, `sessions/new`, `sources/browse`, `sources/search`, `sources/preview`, `search/index` (warning variant), `chapters/show` (error block)

**Proposed API**:
```ruby
<%= render UI::FlashMessageComponent.new(variant: :success, message: flash[:notice]) %>
<%= render UI::FlashMessageComponent.new(variant: :danger, message: @error) %>
<%= render UI::FlashMessageComponent.new(variant: :warning) do %>
  <p class="font-medium">Some sources couldn't be searched:</p>
  ...
<% end %>
```

**Estimated reuse**: 7+ locations
**Complexity**: Low

---

### Priority 2 — Medium Frequency, Medium Impact

#### 2.6 `UI::PaginationComponent`
**Pattern**: Previous/Next pagination with page numbers. Duplicated identically between browse page (top + bottom) and admin downloads.

**Current duplication**: ~30 lines of pagination code repeated 3 times in `sources/browse` and once in `admin/downloads/index`.

**Proposed API**:
```ruby
<%= render UI::PaginationComponent.new(
  current_page: @page,
  total_pages: @total_pages,      # or use has_next: @results.size >= 24
  base_path: source_browse_path(source_slug: ..., sort: @sort)
) %>
```

**Estimated reuse**: 3-4 locations (will grow with more paginated views)
**Complexity**: Medium

---

#### 2.7 `UI::StatCardComponent`
**Pattern**: Admin stat card with label + big number + color.

**Current duplication** (4 identical cards in `admin/downloads/index`):
```erb
<div class="rounded-lg border border-border bg-surface p-4">
  <p class="text-xs uppercase text-muted-2">Queued</p>
  <p class="text-2xl font-semibold text-warning"><%= @stats["queued"] || 0 %></p>
</div>
```

**Proposed API**:
```ruby
<%= render UI::StatCardComponent.new(label: "Queued", value: @stats["queued"] || 0, color: :warning) %>
```

**Estimated reuse**: 4+ (admin downloads, potential future dashboards)
**Complexity**: Very low

---

#### 2.8 `UI::SeriesCardComponent`
**Pattern**: Series card used in grid layouts across library, browse, and search. Contains cover image, title, author, and optional overlays (progress, source badge, status).

**Current duplication**: Three similar but distinct card layouts in `library/index` (with progress overlay), `sources/browse` (with hover overlay), and `search/index` (horizontal card with import button).

This one is **trickier** because each view customizes the card significantly. Worth extracting a base structure with slots.

**Proposed API**:
```ruby
<%= render UI::SeriesCardComponent.new(
  title: series.canonical_title,
  author: series.display_author,
  cover_url: series.cover_image_url,
  href: series_path,
  layout: :grid  # :grid (vertical) or :horizontal
) do |card| %>
  <% card.with_overlay do %>
    <%# Progress bar, status badges, source labels %>
  <% end %>
  <% card.with_actions do %>
    <%# Import button, details link %>
  <% end %>
<% end %>
```

**Estimated reuse**: 3 templates (library, browse, search)
**Complexity**: High (many variants, needs careful slot design)

---

#### 2.9 `UI::ProgressBarComponent`
**Pattern**: Horizontal progress bar with percentage. Used for download progress in library cards, admin downloads table, and chapter reader.

**Current duplication** (3+ locations):
```erb
<div class="h-1 overflow-hidden rounded-full bg-border">
  <div class="h-full rounded-full bg-success" style="width: <%= percent %>%"></div>
</div>
```

**Proposed API**:
```ruby
<%= render UI::ProgressBarComponent.new(
  value: progress[:downloaded],
  max: progress[:total],
  color: :success,    # auto-selects based on completion
  size: :sm           # :xs (h-1), :sm (h-2), :md (h-3)
) %>
```

**Estimated reuse**: 4+ locations
**Complexity**: Low

---

#### 2.10 `UI::FilterTabsComponent`
**Pattern**: Segmented tab bar for filtering (status filters in library, view type toggle in calendar).

**Current duplication**:
```erb
<%# library/index - status filter tabs %>
<div class="flex overflow-hidden rounded-lg border border-border bg-surface-2/60 text-sm">
  <%= link_to "All", library_path, class: "px-3 py-1.5 #{active_classes}" %>
  <%= link_to "Downloaded", library_path(status: "downloaded"), class: "px-3 py-1.5 border-l ..." %>
  ...
</div>

<%# calendar/index - view type toggle %>
<div class="flex rounded-lg overflow-hidden border border-border">
  <% %w[week month recent].each do |view| %>
    <%= link_to view.titleize, calendar_path(view: view), class: "px-4 py-2 text-sm #{active}" %>
  <% end %>
</div>
```

**Proposed API**:
```ruby
<%= render UI::FilterTabsComponent.new(
  items: [
    { label: "All", href: library_path, active: params[:status].blank? },
    { label: "Downloaded", href: library_path(status: "downloaded"), active: params[:status] == "downloaded", variant: :success },
  ]
) %>
```

**Estimated reuse**: 2-3 templates (library, calendar, potentially admin)
**Complexity**: Medium

---

#### 2.11 `UI::ConfirmButtonComponent`
**Pattern**: `button_to` with turbo_confirm, icon, and danger/warning styling. Repeated extensively in series show and admin views.

**Current duplication** (6+ locations in `series/show`, `series/_chapter_row`, `admin/downloads/index`):
```erb
<%= button_to path,
              method: :delete,
              class: "inline-flex items-center gap-1.5 rounded-md border border-rose-500/40 px-3 py-1.5 text-sm font-semibold text-rose-300 hover:bg-rose-500/10",
              data: { turbo_confirm: "Remove all downloads?" } do %>
  <svg ...trash icon... />
  Remove All
  <span class="rounded-full bg-rose-500/20 px-1.5 py-0.5 text-xs"><%= count %></span>
<% end %>
```

**Proposed API**:
```ruby
<%= render UI::ConfirmButtonComponent.new(
  label: "Remove All",
  url: remove_path,
  method: :delete,
  variant: :danger,
  confirm: "Remove all #{count} downloaded chapters?",
  icon: "trash-2",
  count: @downloaded_count
) %>
```

**Estimated reuse**: 8+ locations
**Complexity**: Medium

---

### Priority 3 — Lower Frequency but Worth Extracting

#### 2.12 `UI::BreadcrumbComponent`
**Pattern**: Breadcrumb nav with separator slashes.

```erb
<nav class="flex items-center gap-2 text-sm text-muted" aria-label="Breadcrumb">
  <%= link_to @source.name, path, class: "hover:text-foreground" %>
  <span class="text-muted-2">/</span>
  <span class="text-foreground">Current Page</span>
</nav>
```

**Found in**: `sources/preview`, `chapters/show`

**Estimated reuse**: 2+ (will grow as app grows)
**Complexity**: Low

---

#### 2.13 `UI::DataTableComponent`
**Pattern**: Table with styled header row, divider rows, consistent padding.

**Found in**: `admin/downloads/index`, `admin/scrapers/index`

**Complexity**: High (many columns, custom cells)
**Recommendation**: Defer — tables are too varied for a generic component right now. Better to extract when there are 4+ tables.

---

#### 2.14 `UI::NotificationBadgeComponent`
**Pattern**: Small counter badge (e.g., unread notifications count, download count pills).

**Current duplication**:
```erb
<span class="ml-auto inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-accent text-[10px] font-semibold text-accent-foreground">
  <%= count > 9 ? "9+" : count %>
</span>
```

**Found in**: Sidebar (notifications), series show (download/cancel counts)

**Estimated reuse**: 4+ locations
**Complexity**: Very low

---

## 3. Proposed New Stimulus Controllers

### 3.1 `click-outside` (Generic)
**Opportunity**: Both `dropdown_controller` and `multi_select_controller` independently implement click-outside-to-close and Escape-to-close logic. This could be extracted into a composable controller.

**Current duplication**:
```typescript
// In dropdown_controller.ts AND multi_select_controller.ts:
private handleDocumentClick = (event: MouseEvent) => {
  if (!this.element.contains(event.target as Node)) { this.close() }
}
private handleKeydown = (event: KeyboardEvent) => {
  if (event.key === "Escape") { this.close() }
}
```

**Recommendation**: Rather than a standalone controller, this is better as a **mixin pattern** or simply accepting the minor duplication since the close behavior differs between components. **Low priority** — the duplication is small and the controllers are tightly coupled to their components.

### 3.2 `clipboard` Controller
**Opportunity**: Not currently needed but common in apps — copy to clipboard for chapter URLs, source URLs. Worth adding if sharing features are planned.

**Priority**: Future/Optional

### 3.3 `flash-dismiss` Controller
**Opportunity**: Flash messages currently have no auto-dismiss or close button behavior. A simple controller that auto-hides after N seconds with a manual dismiss button would improve UX.

**Priority**: Medium

### 3.4 `redirect-select` Controller (Replace Inline JS)
**Opportunity**: `RedirectSelectComponent` uses `onchange="window.location.href = this.value"` — inline JS that should be a Stimulus controller for consistency.

**Current code** in `redirect_select_component.html.erb`:
```erb
<select onchange="window.location.href = this.value" ...>
```

**Proposed controller**:
```typescript
// redirect_select_controller.ts
import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  navigate(event: Event) {
    const select = event.currentTarget as HTMLSelectElement
    if (select.value) window.location.href = select.value
  }
}
```

**Priority**: High — eliminates the only inline JS in the codebase

### 3.5 Remove `hello_controller.ts`
**Opportunity**: Unused scaffold controller. Should be deleted and unregistered from `index.ts`.

**Priority**: Trivial cleanup

---

## 4. Inline SVG Icon Consolidation

### Problem
The codebase has an `icon` helper (visible in `design_system/show.html.erb`) using Lucide icons, but most views still use inline SVG. There are **40+ inline SVG icon usages** across templates.

### Common Inline SVGs (by frequency)
| Icon | Inline SVG Count | Lucide Equivalent |
|---|---|---|
| Chevron down (dropdown arrow) | 6+ | `icon "chevron-down"` |
| Search/magnifying glass | 4+ | `icon "search"` |
| Refresh/rotate arrows | 5+ | `icon "refresh-cw"` |
| Download arrow | 3+ | `icon "download"` |
| Trash | 2+ | `icon "trash-2"` |
| X/Close | 3+ | `icon "x"` |
| Check mark | 3+ | `icon "check"` |
| Bell/notification | 2+ | `icon "bell"` |
| External link | 1+ | `icon "external-link"` |
| Book open | 2+ | `icon "book-open"` |
| Menu/hamburger | 1 | `icon "menu"` |
| Plus | 1 | `icon "plus"` |
| Spinner (animated) | 3+ | `SpinnerComponent` |

### Recommendation
Replace all inline SVGs with the `icon` helper. This:
1. Reduces template bloat by ~4 lines per icon
2. Ensures consistent icon sizing (currently varies between `h-3 w-3`, `h-4 w-4`, `h-5 w-5`)
3. Makes icon changes trivial (change once in helper vs. find-replace across views)

**Priority**: Medium — large impact on code cleanliness but not functional

---

## 5. Priority Ranking (Frequency x Complexity)

| Rank | Component | Frequency | Complexity | Impact Score |
|---|---|---|---|---|
| 1 | `UI::PageHeaderComponent` | 12+ views | Low | **Critical** |
| 2 | `UI::StatusBadgeComponent` | 10+ uses | Low | **Critical** |
| 3 | `UI::SeriesCoverComponent` | 9+ uses | Low | **High** |
| 4 | `UI::FlashMessageComponent` | 7+ uses | Low | **High** |
| 5 | `UI::ConfirmButtonComponent` | 8+ uses | Medium | **High** |
| 6 | `UI::SearchInputComponent` | 4+ uses | Low | **Medium** |
| 7 | `UI::ProgressBarComponent` | 4+ uses | Low | **Medium** |
| 8 | `UI::StatCardComponent` | 4 uses | Very Low | **Medium** |
| 9 | `UI::PaginationComponent` | 3+ uses | Medium | **Medium** |
| 10 | `UI::FilterTabsComponent` | 2-3 uses | Medium | **Medium** |
| 11 | `UI::NotificationBadgeComponent` | 4+ uses | Very Low | **Low** |
| 12 | `UI::BreadcrumbComponent` | 2+ uses | Low | **Low** |
| 13 | `UI::SeriesCardComponent` | 3 uses | High | **Low** (risky) |
| 14 | Inline SVG → `icon` helper migration | 40+ | Tedious | **Medium** |
| 15 | `redirect-select` Stimulus controller | 1 use | Very Low | **Quick win** |
| 16 | Delete `hello_controller.ts` | — | Trivial | **Quick win** |

---

## 6. Recommended Extraction Order

### Phase 1: Quick Wins (1-2 hours)
1. Delete `hello_controller.ts` + unregister
2. Create `redirect-select` Stimulus controller to replace inline JS
3. Extract `UI::StatCardComponent` (4 lines of template each)
4. Extract `UI::NotificationBadgeComponent`

### Phase 2: High-Value Primitives (half day)
5. Extract `UI::PageHeaderComponent` → refactor all 12+ views
6. Extract `UI::StatusBadgeComponent` → refactor chapter rows, admin downloads, browse cards
7. Extract `UI::SeriesCoverComponent` → refactor all cover image patterns
8. Extract `UI::FlashMessageComponent` → refactor layout + error banners

### Phase 3: Medium-Value Components (half day)
9. Extract `UI::SearchInputComponent`
10. Extract `UI::ProgressBarComponent`
11. Extract `UI::ConfirmButtonComponent`
12. Extract `UI::FilterTabsComponent`

### Phase 4: Polish & Sweep (half day)
13. Extract `UI::PaginationComponent`
14. Extract `UI::BreadcrumbComponent`
15. Migrate inline SVGs to `icon` helper across all views

### Phase 5: Complex Components (deferred)
16. `UI::SeriesCardComponent` — extract only when design stabilizes
17. `UI::DataTableComponent` — extract when 4+ tables exist

---

## 7. Design Consistency Issues Found

During analysis, noted these token/style inconsistencies that the extraction would fix:

1. **Inconsistent border radius**: Some badges use `rounded-full`, others use no explicit radius. Components would standardize.
2. **Mixed color tokens**: Chapter rows use raw Tailwind colors (`text-rose-300`, `bg-rose-500/10`, `border-amber-500/40`) alongside semantic tokens (`text-danger`, `bg-danger-soft`). The `StatusBadgeComponent` would enforce semantic tokens everywhere.
3. **Inconsistent text hierarchy aliases**: Views mix `text-muted` / `text-secondary` / `text-muted-2` / `text-tertiary` — these map to different things. Need token audit.
4. **Input styling variations**: Search inputs use slightly different padding, border-radius, and focus styles across views. `SearchInputComponent` would unify.
5. **Progress bar height**: Library uses `h-1`, admin downloads uses `h-2`. Need standardized sizes.

---

*Generated: Feb 2026*
