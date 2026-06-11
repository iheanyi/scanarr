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

