# Watching/Following/Importing Series on a Schedule

## Current State Assessment

### What Already Exists

The codebase already has **most of the core infrastructure** built:

| Component | Status | Details |
|-----------|--------|---------|
| `UserSeriesFollow` | Exists | `belongs_to :user`, `belongs_to :library_series`, `download_policy` enum (`notify_only`, `auto_download`), `source_priority` jsonb |
| `NewChapterNotification` | Exists | `belongs_to :user`, `belongs_to :chapter`, `read` boolean, scopes for `unread`/`recent` |
| `CheckNewChaptersJob` | Exists | Iterates all follows, enqueues `CheckSourceForChaptersJob` per series |
| `CheckSourceForChaptersJob` | Exists | Fetches chapters from adapter, creates new chapters + notifications, auto-downloads if policy set |
| `FollowsController` | Exists | CRUD for follows with Turbo Stream responses |
| `NotificationsController` | Exists | Lists notifications, mark read/all read |
| `CalendarController` | Exists | Shows chapters from followed series grouped by date |
| `recurring.yml` | Exists | `CheckNewChaptersJob` runs every 30 minutes |
| `LibrarySeries` | Exists | Aggregation layer linking multiple `Series` (from different sources) to one canonical entity |
| `SeriesSource.last_checked_at` | Exists | Column already in schema, but **not being updated** by any job |
| Follow UI on series page | Exists | Toggle button + auto-download switch on `series/show.html.erb` |

### What's Broken / Incomplete

1. **`CheckNewChaptersJob` has a bug**: Line 15 calls `series.source` (singular) which doesn't exist on the `Series` model. Series has `has_many :sources`. Should use `series.primary_source` or iterate sources.

2. **`CheckSourceForChaptersJob` concurrency key bug**: The `limits_concurrency` lambda expects 3 args `(series_id, _, _)` but the job's `perform` only takes `(series_id, follow_id, source_id = nil)`. The `_` params don't match - this should be `(series_id, follow_id, _source_id)`.

3. **`last_checked_at` never updated**: `SeriesSource` has a `last_checked_at` column in the schema but `CheckSourceForChaptersJob` never sets it after checking.

4. **No follow-from-import flow**: When you import a series from a source, there's no prompt to follow it.

5. **No "Followed" tab in library**: The library view shows all series, not a filtered view of followed series.

6. **Calendar has no download button**: Can see chapters but can't download from calendar view.

7. **No published_at usage in CheckSourceForChaptersJob**: New chapters are created with `published_at` from adapter data, but this isn't used for determining "newness" - only chapter existence check.

8. **No error tracking per-series**: If a source check fails, there's no visibility to the user. Errors just go to logs.

9. **No frequency control**: All followed series check at the same interval (30 min). No per-series customization.

10. **Notifications view missing Turbo Streams**: No real-time update when new notifications arrive.

---

## Implementation Plan

### Phase 1: Fix Existing Bugs & Core Robustness
**Estimated complexity: Small (1-2 hours)**

#### 1.1 Fix `CheckNewChaptersJob` source bug
- **File**: `app/jobs/check_new_chapters_job.rb`
- **Change**: Replace `series.source` with proper source resolution
- Current code iterates each `series` under a `library_series`, then calls `series.source`. Should instead iterate `series.series_sources` and check each source that has a `source_series_id`.
- **Proposed fix**:
```ruby
follow.library_series.series.each do |series|
  series.series_sources.each do |ss|
    next unless ss.source_series_id.present?
    CheckSourceForChaptersJob.perform_later(series.id, follow.id, ss.source_id)
  end
end
```

#### 1.2 Fix `CheckSourceForChaptersJob` concurrency key
- **File**: `app/jobs/check_source_for_chapters_job.rb`
- **Change**: Fix lambda parameter names to match perform signature

#### 1.3 Update `last_checked_at` after checking
- **File**: `app/jobs/check_source_for_chapters_job.rb`
- **Change**: After successful chapter check, update `series_source.update!(last_checked_at: Time.current)`
- Also record a `ScraperRun` for observability.

#### 1.4 Add tests for the check jobs
- Test that new chapters are detected
- Test that existing chapters are skipped
- Test auto-download triggers correctly
- Test notification creation

**[DECISION] Should Phase 1 be deployed independently before Phase 2, or batch together?**

---

### Phase 2: Follow Flow Improvements
**Estimated complexity: Medium (3-5 hours)**

#### 2.1 Follow-on-import prompt
- **File**: `app/controllers/sources_controller.rb` (import action)
- After `ImportSeriesJob` completes, redirect to the series page where the follow button is already visible.
- **[DECISION]**: Should we auto-follow on import? Or just make the follow button more prominent post-import? Recommendation: Don't auto-follow, but surface a flash message like "Import started! Follow this series to get notified of new chapters."

#### 2.2 Add "Following" filter to library
- **File**: `app/controllers/library_controller.rb`
- **File**: `app/views/library/index.html.erb`
- Add a "Following" tab alongside existing filters (All / Downloaded / In Progress / Not Downloaded)
- Query: filter series where `library_series_id IN (user's followed library_series_ids)`
- Show follow status badge on library grid cards

#### 2.3 Follow from library grid
- Add a small follow/unfollow icon button on each library series card (hover or always visible)
- Uses existing `FollowsController` with Turbo Stream response

#### 2.4 Bulk follow/unfollow
- **File**: `app/views/library/index.html.erb`
- Add a "Follow All Visible" / "Unfollow All Visible" button when filter is active
- Checkbox selection mode for bulk operations
- **[DECISION]**: Is bulk follow needed in Phase 2, or defer to Phase 4?

---

### Phase 3: Smarter Scheduling & Source Handling
**Estimated complexity: Medium-Large (4-6 hours)**

#### 3.1 Per-series check frequency
- **Migration**: Add `check_interval_minutes` (integer, default: null) to `user_series_follows`
  - `null` means "use global default" (currently 30 min)
  - User can override per follow: 15 min, 30 min, 1 hour, 6 hours, 12 hours, daily
- **File**: `app/jobs/check_new_chapters_job.rb`
  - Before enqueuing check, compare `series_source.last_checked_at` against the follow's check interval
  - Skip if checked too recently
- **UI**: Add interval selector to the follow settings area on series show page

**[DECISION] Should check frequency live on `UserSeriesFollow` (per-user-per-series) or on `SeriesSource` (global per-series)? Since this is a single-user app, `SeriesSource` might be simpler. But `UserSeriesFollow` is more correct if multi-user is ever added.**

#### 3.2 Source priority for chapter checking
- `UserSeriesFollow` already has `source_priority` (jsonb array)
- **Change**: When checking, respect source priority order. First source that returns chapters wins.
- If primary source fails, try next in priority list.
- **UI**: Add source priority reorder on series show page (drag and drop or select)
- **[DECISION]**: Use simple numbered select per source, or drag-and-drop reorder? Recommendation: Simple select with numbered priority.

#### 3.3 Staggered checking to avoid thundering herd
- Instead of checking all follows simultaneously every 30 minutes, distribute checks across the interval
- **Approach**: `CheckNewChaptersJob` calculates a per-series delay based on series ID hash: `delay = (series.id % interval_minutes).minutes`
- Use `perform_later` with a delay: `CheckSourceForChaptersJob.set(wait: delay).perform_later(...)`

#### 3.4 Rate limiting awareness
- Track rate limit responses from adapters (HTTP 429)
- If a source returns 429, exponentially back off for that source
- **Migration**: Add `rate_limited_until` (datetime) to `sources` table
- **File**: `app/jobs/check_source_for_chapters_job.rb` - Check `source.rate_limited_until` before making requests

#### 3.5 Error visibility
- **Migration**: Add `last_error` (text), `last_error_at` (datetime), `consecutive_failures` (integer, default: 0) to `series_sources`
- Update on check failure; reset on success
- Show error badge on series page when last check failed
- After N consecutive failures (e.g., 5), show warning and optionally pause checking
- **[DECISION]**: What N should trigger the warning? Recommendation: 3 for warning, 10 for auto-pause.

---

### Phase 4: Auto-Download Enhancements
**Estimated complexity: Medium (3-5 hours)**

#### 4.1 Download policy refinements
- Currently: `notify_only` / `auto_download`
- **Add**: `auto_download_wifi_only` (relevant if app ever runs on mobile/limited bandwidth)
- **Add**: Per-follow setting for "download from which source" (relevant when series has multiple sources)
- **[DECISION]**: Since this is a self-hosted app, `wifi_only` seems irrelevant. Skip? Recommendation: Skip, keep just `notify_only` and `auto_download`.

#### 4.2 Auto-download with source preference
- When auto-download is triggered in `CheckSourceForChaptersJob`, use the follow's `source_priority` to choose which source to download from
- If a download fails from one source, try next source in priority

#### 4.3 Download notifications via Turbo Streams
- When `CheckSourceForChaptersJob` creates a new chapter and triggers download, broadcast Turbo Stream to update the notification bell in real-time
- **Files**: Add Action Cable subscription in layout, broadcast from job

#### 4.4 Batch download new chapters
- Instead of downloading chapters one by one as they're discovered, batch them
- New chapters found → create all `NewChapterNotification` records → if auto-download, enqueue all via `DownloadAllJob`-style pattern

---

### Phase 5: Dashboard & Notifications Polish
**Estimated complexity: Medium (3-5 hours)**

#### 5.1 Enhanced library "Following" view
- Show "new chapters available" badge (unread notification count per series)
- Show "last checked" timestamp per series
- Show "last new chapter" date
- Sort options: alphabetical, recently updated, most unread

#### 5.2 Real-time notification updates
- Add Turbo Stream subscription for notifications in the layout header
- When `NewChapterNotification` is created, broadcast update to notification bell count
- **File**: `app/views/layouts/application.html.erb` - Add `turbo_stream_from current_user, :notifications`
- **File**: `app/jobs/check_source_for_chapters_job.rb` - Broadcast after creating notification

#### 5.3 Notification preferences
- **[DECISION]**: Do we need granular notification preferences (e.g., suppress notifications for certain series)? Probably not for MVP - the follow/unfollow toggle is sufficient.

#### 5.4 Calendar improvements
- Add download button directly in calendar chapter rows
- Show "new" badge for unread chapters
- Link directly to reader for downloaded chapters

#### 5.5 Notification cleanup
- Background job to clean up old notifications (> 30 days)
- Add to `recurring.yml`

---

### Phase 6: Edge Cases & Resilience
**Estimated complexity: Small-Medium (2-4 hours)**

#### 6.1 Source goes down temporarily
- Already partially handled by `ScraperRun` error tracking
- Add: If source returns error for check, log it but don't create error notifications for the user
- Retry on next scheduled check
- After N consecutive failures, show a subtle warning on the series page

#### 6.2 Duplicate chapter detection across sources
- Current: Chapters are unique per `(series_id, chapter_number, language, group)` - this already prevents cross-source duplicates within the same series
- BUT: Two sources might have the same chapter with different `group` values
- **Approach**: When checking for existing chapters, also check without `group` if group is nil from one source
- **[DECISION]**: How aggressive should de-duplication be? Current unique constraint seems sufficient for most cases. Only chapters with identical number AND language AND group are considered duplicates.

#### 6.3 Chapter numbering mismatches
- Some sources use "1" while others use "Chapter 1" or "1.0"
- Already handled by `chapter_number_value` (decimal) for ordering
- For duplicate detection: compare `chapter_number_value` when available, fall back to string comparison
- **Change**: In `CheckSourceForChaptersJob`, also check by `chapter_number_value` for existence

#### 6.4 Series renamed or removed from source
- If adapter.chapters() returns empty or errors, don't delete existing chapters
- Log a warning, increment `consecutive_failures`
- If series URL 404s, mark `series_source` as `stale` (new status)
- **[DECISION]**: Should we auto-remove stale series_sources? Recommendation: No, just mark and let user decide.

#### 6.5 Rate limiting / being blocked
- Handle in adapter layer with exponential backoff
- If blocked (403/451), mark source with `rate_limited_until`
- Show source health status on admin scrapers page

---

## Data Model Changes Summary

### New Migrations

```ruby
# 1. Add check frequency to user_series_follows
add_column :user_series_follows, :check_interval_minutes, :integer, default: nil

# 2. Add error tracking to series_sources
add_column :series_sources, :last_error, :text
add_column :series_sources, :last_error_at, :datetime
add_column :series_sources, :consecutive_failures, :integer, default: 0, null: false

# 3. Add rate limiting to sources
add_column :sources, :rate_limited_until, :datetime
```

### Existing columns already in schema (just need to start using):
- `series_sources.last_checked_at` - exists, needs to be updated by `CheckSourceForChaptersJob`
- `user_series_follows.source_priority` - exists as jsonb, needs UI

---

## Job Architecture

```
recurring.yml (every 30 min)
  └── CheckNewChaptersJob (concurrency: 1)
        ├── Loads all UserSeriesFollows with library_series → series → series_sources
        ├── Skips if series_source.last_checked_at < follow.check_interval (or global default)
        ├── Skips if source.rate_limited_until > now
        └── For each series_source needing check:
              └── CheckSourceForChaptersJob.set(wait: stagger_delay).perform_later(series_id, follow_id, source_id)
                    ├── Fetches adapter.chapters(source_series_id)
                    ├── Diffs against existing chapters
                    ├── Creates new Chapter records
                    ├── Creates NewChapterNotification for each
                    ├── Updates series_source.last_checked_at
                    ├── Records ScraperRun for observability
                    ├── If follow.auto_download?:
                    │     └── DownloadChapterJob.perform_later(...)
                    └── Broadcasts Turbo Stream notification update

recurring.yml (every day)
  └── CleanOldNotificationsJob (new)
        └── Deletes read notifications older than 30 days

recurring.yml (every minute - existing)
  └── RestartStalledDownloadsJob (existing, no changes)
```

---

## Implementation Priority & Dependencies

```
Phase 1 (Bug fixes)    ──→ Phase 2 (Follow flow)     ──→ Phase 5 (Polish)
                         ╲                              ╱
                          ──→ Phase 3 (Smart scheduling) ──→ Phase 6 (Edge cases)
                         ╱
Phase 4 (Auto-download) ──────────────────────────────────╱
```

**Recommended order**: Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6

Phase 1 is a prerequisite for everything (fixes broken jobs).
Phases 2-4 can proceed in parallel after Phase 1.
Phases 5-6 are polish and can be done last.

---

## Decision Summary

| # | Decision | Recommendation | Status |
|---|----------|----------------|--------|
| 1 | Deploy Phase 1 independently? | Yes, fix bugs first | **[DECIDE]** |
| 2 | Auto-follow on import? | No, just surface follow button prominently | **[DECIDE]** |
| 3 | Bulk follow in Phase 2 or Phase 4? | Defer to Phase 4 | **[DECIDE]** |
| 4 | Check frequency on UserSeriesFollow or SeriesSource? | UserSeriesFollow (forward-compatible) | **[DECIDE]** |
| 5 | Source priority UI: drag-drop or numbered select? | Numbered select (simpler) | **[DECIDE]** |
| 6 | Consecutive failure threshold for warning? | 3 for warning, 10 for auto-pause | **[DECIDE]** |
| 7 | Add wifi_only download policy? | Skip (self-hosted app) | **[DECIDE]** |
| 8 | Cross-source chapter dedup strategy? | Current unique constraint is sufficient | **[DECIDE]** |
| 9 | Auto-remove stale series_sources? | No, mark stale and let user decide | **[DECIDE]** |

---

## Files Touched Per Phase

### Phase 1
- `app/jobs/check_new_chapters_job.rb`
- `app/jobs/check_source_for_chapters_job.rb`
- `test/jobs/check_new_chapters_job_test.rb` (new or update)
- `test/jobs/check_source_for_chapters_job_test.rb` (new or update)

### Phase 2
- `app/controllers/library_controller.rb`
- `app/views/library/index.html.erb`
- `app/controllers/sources_controller.rb`
- `app/views/series/show.html.erb` (minor)

### Phase 3
- `db/migrate/xxx_add_check_interval_to_follows.rb` (new)
- `db/migrate/xxx_add_error_tracking_to_series_sources.rb` (new)
- `db/migrate/xxx_add_rate_limiting_to_sources.rb` (new)
- `app/jobs/check_new_chapters_job.rb`
- `app/jobs/check_source_for_chapters_job.rb`
- `app/models/user_series_follow.rb`
- `app/models/series_source.rb`
- `app/views/series/show.html.erb`

### Phase 4
- `app/jobs/check_source_for_chapters_job.rb`
- `app/models/user_series_follow.rb`

### Phase 5
- `app/views/library/index.html.erb`
- `app/views/layouts/application.html.erb`
- `app/views/notifications/index.html.erb`
- `app/views/calendar/index.html.erb`
- `app/jobs/clean_old_notifications_job.rb` (new)
- `config/recurring.yml`

### Phase 6
- `app/jobs/check_source_for_chapters_job.rb`
- `app/models/series_source.rb`
- `app/scrapers/base_adapter.rb` (error handling)
