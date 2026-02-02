# Tasks (Overseer)

## Completed (previous plan)
- [x] Milestone `task_01KGDVR714NJXGR6EBTV74HGS6`: Manga manager spec
- [x] Task `task_01KGDVR71NTBH7KCPEKRYYCN4N`: Scaffold design doc
- [x] Task `task_01KGDVR724B4D1E7VEE2GST509`: Write architecture, services, data model
- [x] Task `task_01KGDVR72FG6B1WBMN4H4S78FR`: Integrations (Mihon, Paperback, AniList/MAL/Kitsu)
- [x] Task `task_01KGDVR72YXA3XWSXE0M7A7BBE`: Security, networking, observability, testing
- [x] Task `task_01KGDVR73RQYAEB40NQPXQDPS9`: Reader testing + refine

## Current plan: Rails scraper framework
- [x] Update design doc for Rails stack + scraper runtime
- [x] Scaffold Rails API app at repo root
- [x] Implement scraper framework base + HTTP client
- [x] Implement WeebCentral adapter parsing
- [x] Add rake tasks + parsing tests

## Follow-up: WeebCentral VCR + browser check
- [x] Add VCR cassettes for live WeebCentral requests
- [x] Validate WeebCentral pages in browser

## Review
- Recorded `weeb_central_live` cassette and verified search/series/chapter pages.

## Review (Overseer tasking rule)
- Added Overseer-first rule in `.cursor/rules` and updated `CLAUDE.md`.
- Confirmed existing rake parsing tasks in `lib/tasks/scraper.rake`.

## Current plan: Overseer tasking rule
- [x] Define Overseer-first tasking rule (.cursor/rules)
- [x] Update `CLAUDE.md` task management guidance
- [x] Confirm existing rake parsing tasks cover request

Notes:
- Overseer start/complete requires a VCS repo (git or jj). This workspace is not a repo yet, so use CRUD-only for now.
- Status here can lead Overseer until VCS is initialized.

## Current plan: Fix chapter ordering
- [x] Write failing ordering + navigation tests
- [x] Add chapter_number_value column + backfill + index
- [x] Populate chapter_number_value in model
- [x] Sort chapters by numeric value in controllers
- [x] Verify updated tests

## Current plan: Manga manager design spec
- Overseer milestone: task_01KGDVR714NJXGR6EBTV74HGS6
- Use: `os task list --db /Users/iheanyi/.overseer/tasks.db`
