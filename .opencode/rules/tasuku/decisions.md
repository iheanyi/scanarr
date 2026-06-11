# Tasuku Decisions

_Auto-synced from .tasuku/context/decisions.md_

## adapter-reference-source (2026-02-06)

**Chose**: Use keiyoushi/extensions-source (Mihon/Tachiyomi community extensions) as the reference for building new adapters

**Over**: Writing adapters from scratch by reverse-engineering each site, Using other aggregator projects as reference

**Because**: keiyoushi has Kotlin implementations for hundreds of manga sources with parsing logic, URL patterns, and API structures already mapped out. Much faster to port to Ruby than reverse-engineering from scratch. Community-maintained and up-to-date.

## perf-image-variants (2026-02-09)

**Chose**: libvips with ActiveStorage variants (WebP, 1400px max, quality 82) + pre-processing in download job

**Over**: Pure Ruby processing, On-the-fly variant generation only, ImageMagick/MiniMagick as primary

**Because**: libvips is 2-3x faster than ImageMagick, uses less memory. Pre-processing during download means zero delay when reading. Graceful fallback serves originals if libvips unavailable.

## active-storage-proxy-mode (2026-02-09)

**Chose**: Proxy mode (rails_storage_proxy) for serving Active Storage files

**Over**: Redirect mode (default), CDN/S3 direct serving

**Because**: Proxy mode serves files in 1 HTTP request instead of 2 (no redirect). For a self-hosted app with local disk storage, the extra Rails CPU is negligible. CDN/S3 is overkill for single-instance deployment.

## redis-backed-search-metrics (2026-02-10)

**Chose**: Defer source-performance metrics engine work until Redis/Sidekiq migration is complete

**Over**: Implement source-performance metrics/underperformer reporting immediately on current DB-backed flow, Skip source-performance instrumentation work entirely

**Because**: Redis gives a better foundation for low-overhead aggregation and time-windowed metrics needed for a search metrics engine.

## turbo-toast-navigation-boundary (2026-02-15)

**Chose**: Use Turbo Stream toasts for in-place UI mutations and keep redirects for navigation-intent actions, including Turbo requests.

**Over**: Use Turbo Stream toasts for every mutating action regardless of navigation intent, Always redirect after mutations even when an in-place update is more responsive

**Because**: Preserves expected navigation flow for actions that should move users to a different page, while still providing fast in-place feedback where the user stays on the current screen.

## adapter-update-distribution (2026-06-11)

**Chose**: In-tree Ruby adapters shipped with app releases, plus a declarative source manifest (config/sources/manifest.yml) as the single source of truth for identity, metadata, per-adapter integer version (Mihon extVersionCode analog), and curation flags (enabled/dead). An optional remote data-only definitions override is designed but deferred.

**Over**: Mihon-literal remote extension loading (runtime-loaded Ruby adapter packages from a repo index), Gem-per-adapter with Bundler-managed versions

**Because**: Runtime-loading remote Ruby into a self-hosted server is RCE-by-design; Mihon only gets away with APK loading because Android sandboxes and signs packages. Gems add 25 release pipelines without removing the deploy step. For a self-hosted Docker monolith, the app image IS the distribution channel; what needs out-of-band updating is data (domains, dead flags, theme params), which a schema-validated manifest covers safely. Mirrors what keiyoushi multisrc converged to: most extension churn is domain changes and theme-param tweaks.

## source-health-model (2026-06-11)

**Chose**: A derived health_status enum on Source (healthy/degraded/broken/dead) recomputed idempotently from existing signals (smoke-run history, series_source consecutive failures), with evidence windowed to runs after the last adapter_version bump; dead is manifest-curated only, never automatic.

**Over**: Event-sourced health state machine with explicit transitions, Keep health implicit in reliability_score + consecutive_failures with no unified status

**Because**: Signals already exist in three models but nothing answers 'is this source usable?' in one place. Derivation (not stored transitions) means recomputation converges regardless of crashes or ordering, and windowing evidence to the current adapter version gives a shipped fix a clean probation period instead of being damned by stale failures. Auto-marking a source dead risks false positives from transient Cloudflare blocks, so dead stays a curation decision.

## upstream-catalog-piggyback (2026-06-11)

**Chose**: Mirror the keiyoushi (Mihon community) extensions index daily into an upstream_sources table as a data-only, schema-validated catalog; link our manifest entries by curated mihon_id; functional parity stays adapter-by-adapter since the feed carries no scraping logic or selectors.

**Over**: Maintain our own remote definitions feed, Blindly adopt feed baseUrls for working sources, Import feed sources directly into the sources table

**Because**: The user did not want to maintain a feed. The keiyoushi index gives canonical name/lang/baseUrl/nsfw/version for ~2100 sources for free, but its baseUrl can lag reality (their Asura entry points at asurascans.com while asuracomic.net is what works), so blind adoption can break working adapters. Keeping catalog rows out of the sources table keeps thousands of unimplemented entries from polluting every operator dropdown and scraping query.

## broken-source-recovery (2026-06-11)

**Chose**: Broken sources are skipped by all scheduled work and recovered by a single cheap recheck probe inside the hourly health sweep, on a downtime-scaled backoff (6h under 3 days broken, daily under 14 days, weekly after). When the current domain fails the probe, it tries the upstream catalog's domain and adopts it stickily (persisted as sources.adopted_base_url) on success. Dead remains curated-only.

**Over**: A separate daily active probe fleet (cancelled by user as redundant with the hourly sweep), Conditional base_url override while broken (rejected: heals then flips back to the dead domain), No active recovery (rejected: skipped sources produce no signals and could never self-heal)

**Because**: Skipping checks for broken sources removes the very traffic that would notice recovery, so recovery needs exactly one knock on a polite schedule. Sticky adoption converges: once the new domain works the source stays on it. The health evaluator also discounts series-check failures older than the latest successful run, otherwise stale failure rows that nothing updates would keep a healed source broken forever.

