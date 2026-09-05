# Self-hosting codebase audit — September 5, 2026

This pass reviewed the Rails application structure, request queries, scraper interfaces, download and polling jobs, storage and backup paths, test harness, JavaScript reader lifecycle, CI, and Compose/runtime configuration. Findings below distinguish implemented changes from remaining work. This is a broad code review with local regression checks, not a claim that every adapter has been exercised against its live source or that production capacity has been load-tested.

## Implemented

| Area | Problem | Change |
| --- | --- | --- |
| Chapter archives | Each packaging worker retained a whole compressed chapter in a StringIO. | `ChapterPackager` writes a temporary archive on disk and attaches it before automatic cleanup. Existing CBZ content/order/key tests remain. |
| Backup memory | `pg_dump` output, all blob metadata, and serialized metadata accumulated in memory; attachments caused one query per blob. | Stream dump output to gzip, drain stderr concurrently with a 500-byte diagnostic tail, and stream metadata JSON with batched attachment preloading. |
| Download correctness | Non-200 pages were skipped and incomplete or empty chapters could become complete. Completion preceded successful packaging. | Verify expected and attached page counts, count actual successful downloads, and publish completion only after packaging. Missing/corrupt image blobs produce a recoverable failed download. |
| Bulk download selection | `order(created_at: :desc).find_each` ignored the requested ordering and could select the oldest duplicate chapter. | Use a descending `(created_at, id)` batch cursor; regression deliberately gives the newest chapter a lower ID. |
| Storage migration | Orphan checks used the default storage service, misclassifying existing files after switching backends. | Check the blob's recorded service; regression changes the default to an empty disk backend. |
| Progress rendering | Every periodic download progress update rendered the admin row twice. | Remove the extra periodic admin broadcast. |
| Worker shutdown | Compose did not give Sidekiq an explicit grace period matching its 25-second timeout. | Set the worker's shutdown grace to 30 seconds. |
| Test value | Empty scaffolds, duplicate enum assertions, method-presence assertions duplicating actual calls, and test filename enforcement. | Remove those checks while retaining adapter behavior and source override coverage. Make a fixture-backed follow test unconditional instead of silently skipping. |

Incomplete HTTP downloads now finish as failed and can be restarted through the existing download controls. This change does not introduce automatic per-page retry scheduling or fix concurrent writers to the same release.

## Measured packaging result

A standalone Rubyzip comparison packaged 64 MiB of synthetic, poorly compressible data using the previous in-memory writer and the new file writer. On this Mac, peak resident memory was **160.4 MiB versus 78.3 MiB**, about **51% lower**. Both produced approximately 64 MiB archives. Single-run elapsed times were 2.42 seconds and 2.08 seconds; these are not a throughput benchmark.

The measurement isolates archive writing, not an entire Rails/Sidekiq process. Temporary disk capacity is now required for the archive in addition to Active Storage's per-image temporary file. Image decoding, HTTP response bodies, and Rubyzip's entry metadata still consume memory.

## Prioritized remaining work

### 1. Enforce download claims and source concurrency (high)

`app/jobs/application_job.rb:3` turns `limits_concurrency` into a no-op under Sidekiq. The declarations on downloads, polling, cleanup, and backups therefore do not provide their advertised protection. Multiple jobs can race on the same release's deterministic storage paths, while source traffic can exceed the declared cap.

Introduce an explicit download lifecycle module with atomic ownership and a shared, bounded source concurrency mechanism. Keep acquisition, expiry, cancellation, and release together behind its interface. Verify with two actual worker processes, including worker termination and retry; a single-process mock would miss the failure mode.

### 2. Poll once and notify all eligible followers (high)

`app/jobs/check_new_chapters_job.rb` enqueues source checks per follow. `app/jobs/check_source_for_chapters_job.rb` skips existing chapter numbers/languages and only notifies or auto-downloads for the follow whose job discovers the chapter. Later followers can miss notifications and download policies while causing repeated scraper traffic.

Create one chapter-discovery module per series/source and fan newly discovered chapters out to eligible follows. The interface should own deduplication and notification delivery. Test two followers with different policies, retry delivery, and concurrent discovery before changing scheduling.

### 3. Bound search work across requests (high)

`app/controllers/search_controller.rb:81` creates up to six threads for every request. Each future separately waits up to eight seconds, so eight seconds is not a total request deadline. Shutdown followed by a one-second wait does not cancel outstanding work.

Move fan-out into one search module with process-wide capacity, bounded admission, a single deadline, and HTTP operations that honor remaining time. Test several stalled sources and overlapping requests, including requests that finish while source work is outstanding. Avoid force-killing threads that may own locks or database connections.

### 4. Apply the hardened HTTP policy to cover downloads (high)

`app/services/cover_downloader.rb` follows remote cover redirects through direct `Net::HTTP` calls, bypassing the public-address checks in `Scrapers::HttpClient`. It also retries TLS failures with certificate verification disabled. `SeriesImporter` passes source-provided cover URLs into this path.

Consolidate cover fetching with the hardened HTTP module, validate every redirect destination, retain certificate verification, and bound response size. Cover fetches should not be able to reach the host's internal network simply because a remote source supplied a URL. This finding comes from code inspection; no internal-network probe was performed.

### 5. Stream library exports and preserve preloads (medium)

`app/services/library_export_service.rb` loads the whole library graph and creates full JSON and gzip representations. Its `series.chapters.order(...)` issues a new query despite preloading chapters, and `series_sources` does not preload each mapping's source.

Use a batched export module that owns ordering, preloads, serialization, and temporary output. Preserve format/version compatibility with import round-trip tests and a query-growth test. Large exports should run in a job with a downloadable result rather than occupying a web request.

### 6. Give download status one definition (medium)

`Series#download_progress`, series detail queries, and library aggregation select releases differently: first, newest, or any completed release. Restart/cancel/enqueue logic is also repeated in chapter, series, and admin controllers.

Define which release determines reader availability and UI status, then concentrate that policy in the download lifecycle module. This improves locality: state changes and tests move together instead of requiring coordinated edits across screens. Keep bulk purge work out of web requests and record cancellation before deleting files.

### 7. Make resource tuning consistent (medium)

`config/database.yml` derives maximum connections from `RAILS_MAX_THREADS` with a default of five. Compose exposes `SIDEKIQ_CONCURRENCY` for the worker without passing a corresponding database pool setting. Increasing worker concurrency can therefore exceed available database connections.

Expose a deliberate worker database pool setting and document the aggregate PostgreSQL connection budget across worker processes, Puma workers, and administrative tasks. Verify effective configuration in both containers before changing defaults. Measure realistic library size, image dimensions, search concurrency, and disk space before publishing minimum hardware requirements.

### 8. Reduce test setup cost without reducing behavior coverage (medium)

`test/test_helper.rb` loads all fixtures and defaults to processor-count parallelism for every Rails test, including otherwise pure adapter and component checks. The JavaScript suite has 46 tests across only two files, leaving much of reader/offline lifecycle behavior outside those checks.

Benchmark a small non-database test base for pure modules and use explicit bounded workers in constrained environments. Add browser-level reader/offline lifecycle tests where they cover actual missing behavior. Do not delete behavior regressions merely because they are small or fast; the cleanup in this pass only removes demonstrably redundant or empty checks.

## Validation

- Initial broad Ruby run: 1,381 tests, 4,499 assertions, no failures/errors/skips. It overlapped early audit edits and is a starting check, not an isolated pristine-checkout comparison.
- Focused regressions: 40 tests, 589 assertions, no failures/errors/skips before the final storage-cleanup regression was included.
- JavaScript: 46 tests passed; installed dependencies also built successfully during full Rails test preparation.
- Changed Ruby files: RuboCop passed with cache disabled.
- Brakeman: zero reported warnings/errors using the repository's existing ignore file. This does not establish that the application has no security issues; see the manually identified cover-fetch path above.
- Compose configuration: `docker compose config --quiet` passed without displaying resolved environment values.
- Final full Ruby suite: **1,388 tests, 4,550 assertions, zero failures/errors/skips**. Live source availability, browser behavior, real S3 access, and container startup are outside the verification completed in this pass.

The first Rails invocation could not reach the package registry; subsequent runs used `SKIP_YARN_INSTALL=1` with installed dependencies. Local PostgreSQL access required sandbox escalation. All database tests targeted the test environment.

## Follow-up performance status

Source replacement now renders its initial page without upstream requests,
then uses a queue of at most three browser requests to progressively search
all eligible providers. It no longer fetches chapter lists during discovery.
Requests have explicit deadlines, queued work is cancelled on navigation,
and completed results survive page reconnection. These are page-local limits;
they do not solve global provider concurrency across users or general search.

The measured archive RSS reduction above remains the concrete memory result.
Streaming backups remove known whole-output allocations, but no whole-server
backup RSS or production throughput claim has been established. Global download
claims, shared polling/fan-out, general-search admission, and streamed library
exports remain the highest-value performance follow-ups.
