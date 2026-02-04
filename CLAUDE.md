## Rails Project Conventions

### Model Relationships

Key relationship patterns - **do not confuse singular vs plural**:

```
Series
├── has_many :sources (through :series_sources) ← PLURAL, use primary_source helper
├── has_many :chapters
├── belongs_to :library_series (optional)
└── has_one_attached :cover

Chapter
├── belongs_to :series
├── belongs_to :source (optional) ← SINGULAR, direct relationship
├── has_many :releases
└── source_url (string attribute)

Source
├── has_many :series (through :series_sources)
├── has_many :chapters
├── key (internal identifier, uses underscores: "weeb_central")
└── slug (URL-friendly, uses hyphens: "weeb-central")
```

**Common mistakes to avoid:**
- `series.source` ❌ → `series.primary_source` ✅
- `source.key.tr("_", "-")` ❌ → `source.slug` ✅
- Forgetting to pass required keywords to jobs

### ViewComponent Patterns

Components live in `app/components/ui/` and inherit from `UI::BaseComponent`:

```ruby
# Good: Use render with component
<%= render UI::ButtonComponent.new(variant: :primary, size: :sm) do %>
  Click me
<% end %>

# Components available:
# - UI::ButtonComponent (variant: :primary/:secondary/:ghost, size: :sm/:md/:lg)
# - UI::BadgeComponent
# - UI::ToggleSwitchComponent (for form switches)
# - UI::ToggleButtonComponent (for follow/unfollow)
# - UI::SelectComponent, UI::MultiSelectComponent, UI::AutoSelectComponent
# - UI::DropdownComponent
```

### Stimulus Controllers

Controllers in `app/javascript/controllers/`. Naming: `foo_bar_controller.ts` → `data-controller="foo-bar"`

```erb
<!-- Auto-submit forms on change -->
<%= f.select :field, options, {}, data: { controller: "auto-submit", action: "change->auto-submit#submit" } %>

<!-- Loading button state -->
<div data-controller="loading-button">
  <button data-loading-button-target="button" data-action="click->loading-button#submit">
    <span data-loading-button-target="text">Submit</span>
  </button>
</div>
```

### Tailwind Design Tokens

Use semantic tokens, not raw colors:

```css
/* Backgrounds */
bg-surface       /* card/panel backgrounds */
bg-surface-2     /* elevated surfaces, inputs */
bg-background    /* page background */

/* Text */
text-foreground  /* primary text */
text-muted       /* secondary text */
text-muted-2     /* tertiary/placeholder */

/* Status colors (with -soft variants for backgrounds) */
text-success / bg-success-soft   /* green - downloaded, complete */
text-warning / bg-warning-soft   /* amber - in progress */
text-danger / bg-danger-soft     /* red - errors, delete */
text-info / bg-info-soft         /* blue - links, info */
text-accent / bg-accent-soft     /* emerald - primary actions */

/* Borders */
border-border    /* standard borders */
```

### Hotwire/Turbo Patterns

```erb
<!-- Turbo Frame for partial page updates -->
<%= turbo_frame_tag "filters" do %>
  <!-- Content that updates independently -->
<% end %>

<!-- Turbo Stream for real-time updates -->
<%= turbo_stream_from @series, :downloads %>

<!-- Form with Turbo Frame target -->
<%= form_with url: path, data: { turbo_frame: "results" } do |f| %>
<% end %>

<!-- Broadcast updates from jobs/models -->
Turbo::StreamsChannel.broadcast_replace_to(
  [series, :downloads],
  target: dom_id(chapter),
  partial: "series/chapter_row",
  locals: { chapter: chapter, source: source, series: series }
)
```

### Job Patterns

Always pass required keywords when enqueuing jobs:

```ruby
# DownloadChapterJob requires:
DownloadChapterJob.perform_later(
  chapter.source_url,           # positional: chapter URL
  source_key: source.key,       # required keyword
  series_title: series.title,   # required keyword
  chapter_number: chapter.number, # required keyword
  # optional: chapter_title, language, group, release_id, source_series_id
)
```

### Adapter Patterns

Adapters in `app/scrapers/<source_name>/adapter.rb` inherit from `BaseAdapter`:

```ruby
# Must implement:
def search(query) → Array<ResultTypes::SearchResult>
def series(id_or_url) → ResultTypes::Series
def chapters(series_url) → Array<ResultTypes::Chapter>
def pages(chapter_url) → Array<ResultTypes::Page>

# Optional:
def supports_browse? → boolean
def browse(sort:, page:, limit:) → Array<ResultTypes::BrowseResult>
```

## Workflow Orchestration

### 1. Plan Mode Default

- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy to keep main context window clean

- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One task per subagent for focused execution

### 3. Self-Improvement Loop

- After ANY correction from the user: update 'tasks/lessons.md' with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done

- Never mark a task complete without proving it works, especially within the browser when making front-end changes.
- When running locally, always use `bin/dev` (not `bin/rails s`) so assets are built.
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests -> then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Use Overseer for task plans and tracking; avoid `tasks/todo.md`
   except when Overseer is unavailable (e.g., before git/jj init)
2. **Create Tasks Immediately**: After planning, create Overseer tasks without prompting
3. **Track Progress**: Update Overseer task status as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Record review notes in Overseer (fallback: `tasks/todo.md`)
6. **Capture Lessons**: Update 'tasks/lessons.md' after corrections

## Core Principles

- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior software engineer standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid introducing bugs.
- **No Unrequested Images**: Do not generate images unless explicitly asked.