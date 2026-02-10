# Advanced Filters Roadmap (Library, Search, Source Browse)

## Context

The library now supports:

- Debounced live filtering
- Advanced filters (multi-select sources + multi-select genres)
- Indexed filtering (trigram title search + JSONB GIN for genres)

Next, we want the same filter quality in:

- Global `GET /search`
- Per-source `GET /sources/:source_slug/search`
- Per-source `GET /sources/:source_slug/browse`

The challenge is that source adapters expose different capabilities, so not every source can provide the same filter dimensions.

## UX Direction

Use the same high-level filter pattern across views:

1. Primary row: query + sort + quick controls
2. Expandable "Advanced filters" panel
3. Active filter chips above results
4. URL-param persistence for shareable filtered views
5. Fast, debounced updates inside Turbo frames where possible

Reference inspiration:

- Tailwind UI category filter patterns (multi-filter panel + inline actions): https://tailwindcss.com/plus/ui-blocks/ecommerce/components/category-filters

## Capability Model (Required Before Full Parity)

Add/standardize adapter capability methods so UI can be capability-aware:

- `supports_browse?`
- `supports_search?`
- `supports_server_side_filters?`
- `browse_filter_options` (genres/tags/types/status where available)
- `search_filter_options` (if source supports it)

If unsupported, UI should:

- Hide unsupported filter controls
- Keep consistent shell layout
- Show lightweight hint ("This source does not expose genre filters")

## Phased Plan

### Phase 1 — Global Search Filter Parity (Low-Medium Risk)

- Keep existing source multi-select in global search
- Add optional advanced filter group:
  - genres (library-derived for local filtering of imported series only)
  - follow/download/read status (when result can be mapped to existing library series)
- Add active filter chips + clear-one behavior

### Phase 2 — Source Search Advanced Filters (Capability-Aware)

- Add advanced panel to per-source search UI
- If adapter supports server-side filters, pass selected filters to adapter
- If adapter does not, keep query-only mode and hide unavailable filters
- Document per-source behavior in source docs

### Phase 3 — Source Browse Advanced Filters + Sort Extension

- Extend browse UI to include filter controls from adapter metadata
- Keep infinite scrolling behavior
- Ensure selected filters persist to next-page sentinel URL

### Phase 4 — Shared Filter Infrastructure

- Extract reusable filter bar component(s) for:
  - primary controls row
  - advanced panel
  - active chip row
- Add small helper layer for query-param normalization and serialization

## Performance and Data Considerations

- Keep debounced submissions (already in place for library)
- Add/verify indexes only when a filter is backed by local DB queries
- For external adapter-driven filters, optimize request payload and retry behavior
- Confirm query plans on larger datasets before rollout completion

## Testing Strategy

- Controller tests:
  - param normalization
  - filter combinations
  - URL persistence through pagination/random actions
- System/UI tests:
  - advanced panel behavior
  - active chip removal
  - capability-driven control visibility by source
- Regression tests for empty states and no-results messaging

## Open Decisions

1. Should global search filter only imported/local metadata, or also adapter-returned metadata when available?
2. Do we require a minimum capability contract for new adapters before enabling advanced filters?
3. Should filter state be remembered per-user between sessions?
