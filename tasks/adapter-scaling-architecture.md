# Adapter Scaling Architecture: Supporting 100+ Manga Sources

*Research document -- February 2026*

---

## Table of Contents

1. [Top 15 Sources to Support](#1-top-15-sources-to-support)
2. [Adapter Architecture for Scale](#2-adapter-architecture-for-scale)
3. [Source Discovery UX](#3-source-discovery-ux)
4. [Multi-Source Deduplication](#4-multi-source-deduplication)
5. [Performance at Scale](#5-performance-at-scale)
6. [Community Contribution Model](#6-community-contribution-model)
7. [Implementation Phases](#7-implementation-phases)

---

## 1. Top 15 Sources to Support

Sources ranked by a composite of traffic, catalog size, scan quality, reliability, and ease of adapter implementation. Traffic data sourced from SimilarWeb (Dec 2025) and Semrush where available.

### Tier 1: Must-Have (High traffic, reliable, good catalogs)

| # | Source | Category | Monthly Visits | Catalog | Notes |
|---|--------|----------|---------------|---------|-------|
| 1 | **MangaDex** | API-based | ~297M | 80K+ series | Already implemented. Public REST API, 5 req/s rate limit. Gold standard for scanlation aggregation. Community-driven, best metadata. |
| 2 | **ComicK** | API-based | ~30M | 50K+ series | JSON REST API at `api.comick.fun`. Very similar to MangaDex in philosophy. Fast, well-structured API. High priority to add. |
| 3 | **MangaFire** | Aggregator | ~25M (growing 22%/mo) | 20K+ series | Custom site, pulls from multiple upstream sources. Ranks #13 in Animation & Comics globally. Clean reader. |
| 4 | **Manga Plus** (Shueisha) | Official API | N/A (app-based) | ~500 series | Official publisher. Protobuf API (not REST). Free first/last 3 chapters. Only legal source for simultaneous release. Limited catalog but very high quality. |
| 5 | **MangaSee / Manga4Life** | JS-embedded data | ~400K (declining) | 5K+ series | Already implemented. Same backend (MangaSee = Manga4Life). JSON embedded in JavaScript. Declining traffic but still relevant catalog. |

### Tier 2: High Value (Large catalogs, different niches)

| # | Source | Category | Monthly Visits | Catalog | Notes |
|---|--------|----------|---------------|---------|-------|
| 6 | **Bato.to (MangaToto)** | Custom platform | ~34M | 40K+ series | User-uploaded scanlations. Uses CryptoAES for image decryption. Good catalog breadth. Multiple mirror domains. |
| 7 | **AsuraScans** | Custom (Next.js) | ~15M | ~300 series | Already implemented. Primarily manhwa. Small catalog but extremely popular titles. Domain changes frequently. |
| 8 | **WeebCentral** | Custom HTML | ~5M | 15K+ series | Already implemented. HTMX-based pagination. Solid English catalog. |
| 9 | **MangaBuddy / MangaKakalot** | Custom scraping | ~34M / ~20M | 20K+ | Network of mirror sites (mangakakalot, manganato, mangabuddy, chapmanganato). Same underlying data, different frontends. |
| 10 | **TCB Scans** | Custom HTML | ~5M | ~20 series | Niche but extremely important: fastest English scanlator for One Piece, JJK, MHA. Critical for speed-focused users. |

### Tier 3: Framework-Covered (Bulk coverage via shared adapters)

| # | Source | Category | Monthly Visits | Catalog | Notes |
|---|--------|----------|---------------|---------|-------|
| 11 | **MangaThemesia sites** (LuminousScans, FlameScans, etc.) | MangaThemesia template | Varies (1-10M each) | 50-500 each | 30+ sites share the same WordPress theme. One adapter class with config covers them all. Primarily manhwa/manhua scanlations. |
| 12 | **Madara sites** (various) | Madara WordPress | Varies (500K-5M each) | 50-500 each | 50+ sites share the Madara WordPress theme. One configurable adapter covers all. Huge collective catalog. |
| 13 | **MangaPill** | Custom HTML | ~2M | 10K+ series | Already implemented. Simple scraper, good English catalog. |
| 14 | **MangaPlus Creators** | Official API | App-based | ~1K series | Shueisha's platform for indie creators. Interesting niche. |
| 15 | **Keyoapp sites** | Keyoapp template | Varies | Varies | Emerging multi-source framework in the keiyoushi ecosystem. Worth monitoring. |

### Source Categories Summary

**API-based (easiest to port):**
- MangaDex (done), ComicK, Manga Plus, MangaPlus Creators
- These have structured JSON (or protobuf) responses, documented or reverse-engineered endpoints, pagination support

**Madara-based WordPress (50+ sites from one adapter):**
- 1st Kiss Manga, Manhua Plus, Manhwa18, IsekaiScan, S2Manga, many more
- All share: `/wp-admin/admin-ajax.php` chapter loading, `div.page-listing-item` chapter selectors, `div.summary_image` cover selectors

**MangaThemesia-based (30+ sites from one adapter):**
- LuminousScans, FlameScans, ReaperScans (defunct July 2024), AsuraScans forks
- Share: `div.chapternum` selectors, `/manga/` URL patterns, project page support

**Custom sites (need individual adapters):**
- MangaFire, Bato.to, TCBScans, MangaKakalot network
- Each has unique HTML structure or requires special handling (CryptoAES, JS rendering)

**Aggregators (pull from other sources):**
- MangaFire, MangaBuddy
- Good as fallback sources since they mirror content from multiple upstream sources

---

## 2. Adapter Architecture for Scale

### 2.1 Current Architecture Assessment

The current system has 5 adapters, each in `app/scrapers/<source_name>/adapter.rb`, inheriting from `BaseAdapter`. The `AdapterRegistry` is a static hash mapping source keys to lazy-loaded adapter classes. Configuration comes from `config/sources.yml`.

**What works well:**
- Clean `BaseAdapter` contract (`search`, `series`, `chapters`, `pages`, `browse`)
- `ResultTypes` structs provide consistent data shapes
- `HttpClient` handles rate limiting, retries, proxies per-config
- `Source` model with `reliability_score` tracks health
- `SeriesSource` tracks per-source check failures

**What breaks at 100+ adapters:**
- Static `ADAPTERS` hash in `AdapterRegistry` requires code changes to add sources
- `config/sources.yml` becomes a 2000+ line monolith
- No shared base classes for common site templates
- No way to add adapters without restarting the server
- No adapter versioning or compatibility metadata
- No distinction between adapter capabilities beyond `supports_browse?`

### 2.2 Plugin-Style Auto-Discovery

**Recommendation: Auto-discover via directory convention + Zeitwerk**

Rails 8 with Zeitwerk already auto-loads classes from `app/` directories. The key change is replacing the static `ADAPTERS` hash with dynamic discovery.

**Proposed directory structure:**
```
app/scrapers/
  base_adapter.rb                    # Existing
  api_adapter.rb                     # New: base for API sources
  html_adapter.rb                    # New: base for HTML scraping
  madara_adapter.rb                  # New: base for Madara WordPress sites
  manga_themesia_adapter.rb          # New: base for MangaThemesia sites
  configurable_adapter.rb            # New: config-driven adapter (see 2.5)
  http_client.rb                     # Existing
  result_types.rb                    # Existing
  adapter_registry.rb                # Rewritten: dynamic discovery

  # Individual adapters (unchanged pattern)
  mangadex/
    adapter.rb
  comick/
    adapter.rb
  weeb_central/
    adapter.rb

  # Config-driven adapters (new pattern)
  configs/
    madara/
      first_kiss_manga.yml
      manhua_plus.yml
      manhwa18.yml
      ...50 more YAML files
    manga_themesia/
      luminous_scans.yml
      flame_scans.yml
      ...30 more YAML files
```

**How auto-discovery works:**

1. **Code-based adapters**: Zeitwerk already handles this. Any class in `app/scrapers/*/adapter.rb` that inherits from `BaseAdapter` is auto-discovered.

2. **Config-driven adapters**: A `ConfigurableAdapter` reads YAML files from `app/scrapers/configs/` and dynamically registers sources.

3. **Registry rewrite**: Replace the static hash with a class-method-based registration + directory scanning.

```ruby
# Conceptual approach for AdapterRegistry
class AdapterRegistry
  class << self
    def for(source_or_key)
      key = normalize_key(source_or_key)
      config = source_config(key)

      # 1. Try code-based adapter
      if adapter_class = find_adapter_class(key)
        return adapter_class.new(config: config)
      end

      # 2. Try config-driven adapter
      if adapter_config = find_config(key)
        framework = adapter_config["framework"] # "madara", "manga_themesia", etc.
        base_class = framework_class(framework)
        return base_class.new(config: config.merge(adapter_config))
      end

      raise UnknownSourceError, "Unknown source: #{key}"
    end

    def registered_keys
      (code_adapter_keys + config_adapter_keys).uniq.sort
    end
  end
end
```

### 2.3 Shared Base Classes

**The hierarchy:**

```
BaseAdapter
  |-- ApiAdapter           # JSON API sources (MangaDex, ComicK)
  |-- HtmlAdapter          # HTML scraping sources (WeebCentral, MangaPill)
  |     |-- MadaraAdapter         # 50+ Madara WordPress sites
  |     |-- MangaThemesiaAdapter  # 30+ MangaThemesia sites
  |     |-- FMReaderAdapter       # FM-based sites
  |-- ConfigurableAdapter  # Purely YAML-driven (delegates to framework base)
```

**ApiAdapter** would provide:
- JSON response parsing helpers
- Pagination handling (offset-based, cursor-based)
- Standard error extraction from JSON error responses
- Content-type validation

**HtmlAdapter** would provide:
- Nokogiri document parsing from response
- CSS selector-based extraction helpers
- Common patterns: `extract_labeled_text`, `extract_links`, `extract_images`
- Next-page / HTMX fragment following
- Lazy-loading image resolution (`data-src` vs `src`)

**MadaraAdapter** would provide:
- Default selectors for Madara WordPress theme
- AJAX chapter loading via `wp-admin/admin-ajax.php`
- Configurable: `manga_path`, `chapter_selector`, `image_selector`, `date_format`
- Override points: `parse_chapter_date`, `extract_cover`, `build_chapter_url`

**MangaThemesiaAdapter** would provide:
- Default selectors for Themesia template
- Project page support
- Configurable: `series_path`, `chapter_pattern`, `image_selector`
- Override points: `parse_series_type`, `extract_tags`

### 2.4 Adapter Generator

A Rails generator to scaffold new adapters:

```bash
# Code-based adapter
rails generate adapter comick --type=api
rails generate adapter tcb_scans --type=html

# Config-driven adapter from framework
rails generate adapter first_kiss_manga --framework=madara --base-url=https://1stkissmanga.me
```

The generator would create:
- `app/scrapers/<name>/adapter.rb` with the correct base class
- Entry in `config/sources.yml` with sensible defaults
- `test/scrapers/<name>/adapter_test.rb` with smoke test template
- For config-driven: a YAML config file instead of Ruby code

### 2.5 Configuration-Driven Adapters

The biggest win for scale. Madara alone covers 50+ sites that differ only in domain and CSS selectors.

**Example YAML config for a Madara site:**

```yaml
# app/scrapers/configs/madara/first_kiss_manga.yml
key: "first_kiss_manga"
name: "1st Kiss Manga"
framework: "madara"
base_url: "https://1stkissmanga.me"
language: "en"
enabled: true

# Madara-specific config
manga_path: "manga"          # URL path (default: "manga")
chapter_loading: "ajax"       # "ajax" or "html" (default: "ajax")
use_new_chapter_endpoint: true

# Override selectors (optional, has Madara defaults)
selectors:
  search_results: "div.c-tabs-item__content"
  chapter_list: "li.wp-manga-chapter"
  chapter_link: "a"
  chapter_date: "span.chapter-release-date"
  page_images: "div.page-break img"

# Date parsing
date_format: "%B %d, %Y"     # "January 15, 2025"

# Rate limiting
delay_ms: 500
max_retries: 2

# Headers
headers:
  Referer: "https://1stkissmanga.me/"
```

**How it works at runtime:**

1. On boot, `AdapterRegistry` scans `app/scrapers/configs/**/*.yml`
2. Each YAML file is parsed and registered as a source
3. When `AdapterRegistry.for("first_kiss_manga")` is called, it:
   - Loads the YAML config
   - Instantiates `MadaraAdapter` with the config merged in
   - The `MadaraAdapter` uses config values for selectors, URLs, etc.
4. Adding a new Madara site = adding one YAML file. No Ruby code needed.

**Selector override system:**

The framework base classes define default selectors as class-level constants. YAML configs can override any selector. At runtime, `config.fetch("selectors", {})` is merged over defaults.

### 2.6 Hot-Reloading

**Goal**: Add/update adapters without restarting the server.

**For config-driven adapters:**
- Use `ActiveSupport::FileUpdateChecker` to watch `app/scrapers/configs/`
- On file change, re-scan and update the registry
- Since configs are YAML (no code execution), this is safe to reload

**For code-based adapters:**
- Zeitwerk already handles code reloading in development
- In production, code changes require a deploy (acceptable)
- The registry uses lazy loading (`-> { ClassName }`) so new classes are picked up

**For Source database records:**
- The `Source` model already has `enabled`, `base_url`, `capabilities` columns
- YAML config changes should sync to the database (source of truth for runtime state)
- A rake task or admin action: `AdapterRegistry.sync_sources!` creates/updates `Source` records from YAML configs

### 2.7 Adapter Versioning

Sites change their HTML structure. We need to track adapter compatibility.

**Proposed approach:**

Each adapter declares a `VERSION` and `LAST_VERIFIED` date:

```ruby
class SomeAdapter < HtmlAdapter
  VERSION = "1.2.0"
  LAST_VERIFIED = "2026-01-15"  # Last date the adapter was confirmed working

  def self.adapter_metadata
    {
      version: VERSION,
      last_verified: LAST_VERIFIED,
      capabilities: [:search, :series, :chapters, :pages, :browse],
      language: "en",
      nsfw: false
    }
  end
end
```

For config-driven adapters, metadata lives in the YAML:

```yaml
version: "1.0.0"
last_verified: "2026-01-15"
capabilities: [search, series, chapters, pages]
```

The existing `ScraperRun` and `ScraperSmokeJob` infrastructure already provides runtime verification. Combine this with declared metadata to show users:
- "Last verified working: 3 days ago" (from ScraperRun)
- "Adapter version: 1.2.0" (from metadata)
- "Capabilities: search, chapters, pages" (from metadata)

---

## 3. Source Discovery UX

### 3.1 Source Browser (Extension Manager)

Inspired by Mihon/Tachiyomi's extension manager and Prowlarr's indexer management.

**Three-tab layout:**

1. **Enabled Sources** -- Sources the user has activated, with health indicators
2. **Available Sources** -- Browse/search all supported sources to enable
3. **Source Health** -- Dashboard showing status of all enabled sources

**Available Sources view:**

```
[Search sources...]                    [Filter: Language v] [Filter: Type v]

RECOMMENDED
  MangaDex          API    80K+ series    [Enable]
  ComicK            API    50K+ series    [Enable]

POPULAR
  MangaFire         Agg    20K+ series    [Enable]
  Bato.to           User   40K+ series    [Enable]
  AsuraScans        Scan   300 series     [Enable]

MANHWA SCANLATORS
  LuminousScans     Scan   200 series     [Enable]
  FlameScans        Scan   150 series     [Enable]

ALL SOURCES (87 more)
  ...sortable, filterable list...
```

### 3.2 Categories and Grouping

**Primary grouping: by language**
- English, Japanese, Korean, Chinese, Spanish, Portuguese, French, etc.
- Most users care about one language; this is the primary filter

**Secondary grouping: by type**
- Official (Manga Plus, VIZ) -- legal, publisher-backed
- Scanlation (MangaDex, ComicK) -- community-translated
- Aggregator (MangaFire, MangaBuddy) -- mirror content from other sources
- Scan Group (AsuraScans, TCBScans) -- single group's releases

**Tertiary: by content focus**
- Manga (Japanese origin)
- Manhwa (Korean origin)
- Manhua (Chinese origin)
- Webtoon (long-strip format)

**Quality tiers** (for internal ranking, not exposed as filter):
- Gold: API-based, reliable, large catalog, fast
- Silver: HTML scraping, generally reliable, good catalog
- Bronze: Config-driven, community-verified, may break

### 3.3 Federated Search

When a user searches from the main search bar, search across multiple sources in parallel.

**Strategy:**
1. Search enabled sources in priority order (user-configurable)
2. Use `Concurrent::Promises` or parallel job enqueuing
3. Set per-source timeouts (5 seconds max per source)
4. Merge and deduplicate results (see Section 4)
5. Show results as they arrive (Turbo Streams for progressive loading)

**UI:**

```
Search: "Solo Leveling"

Results from MangaDex (3 results)
  Solo Leveling                    Manhwa    178 chapters
  Solo Leveling: Ragnarok          Manhwa     45 chapters

Results from ComicK (2 results)
  Solo Leveling                    Manhwa    178 chapters

Results from AsuraScans (1 result)
  Solo Leveling                    Manhwa    178 chapters

[Merge duplicates] -- links identical series across sources
```

### 3.4 Source Health Dashboard

Leverages the existing `ScraperRun` and `Source#reliability_score` infrastructure.

**Dashboard shows per-source:**
- Status: Healthy / Degraded / Down
- Last successful scrape time
- Response time (p50, p95)
- Success rate (30-day rolling)
- Number of series tracked from this source
- Last error message (if any)

**Implementation**: The existing `scraper_runs` table already tracks `status`, `started_at`, `finished_at`, `error`, and `stats_json`. The `Source#reliability_score` method computes 30-day success rate. Extend with:
- Store response time in `stats_json`
- Add a periodic health check job (lighter than smoke tests)
- Broadcast health changes via Turbo Streams to the admin dashboard

### 3.5 Enable/Disable Per Source

The `sources` table already has an `enabled` boolean and `default_priority`. The UX flow:

1. **First run**: Only MangaDex is enabled by default (most reliable, largest catalog)
2. **Source browser**: User enables additional sources with one click
3. **Per-source settings**: After enabling, user can configure:
   - Priority (higher priority = preferred for downloads)
   - Language filter
   - Auto-download preference
4. **Disable**: Soft-disable keeps data, stops new chapter checks

### 3.6 Recommendations

**"Suggested Sources" on first run:**
- Based on what series the user imports first, suggest sources that have good coverage
- Example: User adds Solo Leveling -> suggest AsuraScans, LuminousScans
- Based on user's language preference in settings

---

## 4. Multi-Source Deduplication

### 4.1 The Problem

"One Piece" exists on MangaDex, ComicK, MangaSee, MangaFire, MangaPill, and 50 other sources. When a user follows "One Piece", they should see one unified series with chapters from the best available source, not 50 duplicates.

### 4.2 Current Infrastructure

Scanarr already has the right data model for this:

```
LibrarySeries (canonical, source-agnostic)
  |-- Series (source-specific instances)
  |     |-- SeriesSource (links Series to Source with source_series_id)
  |     |-- Chapters (from that source)
  |-- UserSeriesFollow (user follows the LibrarySeries)
```

The `LibrarySeries` table has `anilist_id`, `mal_id`, `mangadex_id` columns for cross-referencing with external databases. The `Series#auto_link_library_series` callback already creates `LibrarySeries` records on import.

**What is missing**: Automatic matching of the *same* series across different sources into the same `LibrarySeries`.

### 4.3 Title Matching Strategy

**Multi-pass matching algorithm:**

**Pass 1: External ID match (highest confidence)**
- If a source provides a MangaDex UUID, AniList ID, or MAL ID, match directly
- MangaDex and ComicK both expose these IDs in their APIs
- Confidence: 99%

**Pass 2: Normalized title exact match**
- Normalize: lowercase, strip punctuation, collapse whitespace, remove common suffixes ("manga", "manhwa")
- `"Solo Leveling"` -> `"solo leveling"` matches across all sources
- Also check `alt_titles` array
- Confidence: 95%

**Pass 3: Fuzzy title match**
- Use Jaro-Winkler similarity (good for titles that differ slightly)
- Threshold: 0.92 similarity score
- Additional signal: same author/artist name
- Confidence: 80% (requires user confirmation above threshold, auto-match below)

**Pass 4: Manual linking**
- Admin UI to manually link/unlink series across sources
- "This MangaDex series is the same as this ComicK series"

**Implementation approach:**

```ruby
class SeriesMatcher
  NORMALIZE_REGEX = /[^a-z0-9\s]/i

  def find_matching_library_series(series)
    # Pass 1: External IDs
    match = match_by_external_ids(series)
    return match if match

    # Pass 2: Normalized title
    match = match_by_normalized_title(series)
    return match if match

    # Pass 3: Fuzzy match (returns candidates for review)
    candidates = fuzzy_match_candidates(series)
    return candidates.first if candidates.first&.confidence > 0.95

    # Pass 4: No match found, create new LibrarySeries
    nil
  end
end
```

### 4.4 Enrichment from External APIs

Use AniList GraphQL API to enrich `LibrarySeries` records with canonical metadata:

- **AniList**: Free GraphQL API, covers ~90% of manga/manhwa. Returns canonical title (romaji, English, native), alternative titles, MAL ID, cover image, genres, status.
- **MyAnimeList**: Jikan API (unofficial MAL REST API). Backup for series not on AniList.
- **MangaDex**: Already integrated. Provides UUIDs that are widely used as cross-reference IDs.

**Flow:**
1. When a new `LibrarySeries` is created, enqueue `EnrichLibrarySeriesJob`
2. Job queries AniList by title -> gets AniList ID, MAL ID, canonical metadata
3. Updates `LibrarySeries` with `anilist_id`, `mal_id`, canonical title, description
4. Future imports can match on these IDs (Pass 1)

### 4.5 Best-Source Selection

When multiple sources have the same chapter, which one to prefer for downloads?

**Source priority factors (weighted scoring):**

| Factor | Weight | Rationale |
|--------|--------|-----------|
| User preference | 5x | User explicitly set source priority in follow settings |
| Source reliability | 3x | `Source#reliability_score` from `scraper_runs` |
| Scan quality | 2x | Higher resolution, better translations (metadata on Source) |
| Release speed | 1x | How quickly chapters appear after raw release |
| Download success rate | 3x | Historical success rate for this specific source+series |

The `user_series_follows.source_priority` JSONB column already exists for per-follow source ordering.

**Algorithm:**
```
score = (user_pref * 5) + (reliability * 3) + (quality * 2) + (speed * 1) + (dl_success * 3)
```

Select the source with the highest score. If download fails, automatically fall back to the next-highest source.

### 4.6 Source Fallback

When the primary source is down or a chapter download fails:

1. **Automatic retry from same source** (already handled by `HttpClient` retries)
2. **Fallback to next source**: If the primary source returns errors 3 times (`consecutive_failures >= 3` on `SeriesSource`), automatically try the next-priority source
3. **User notification**: "Downloaded Chapter 120 from ComicK (MangaDex was unavailable)"
4. **Automatic recovery**: When the primary source comes back (next successful smoke test), resume using it

---

## 5. Performance at Scale

### 5.1 Parallel Chapter Checking

**Current problem**: `CheckNewChaptersJob` iterates all follows and enqueues `CheckSourceForChaptersJob` per series per source. With 100+ sources, this could mean thousands of jobs.

**Proposed strategy:**

**Dedicated queues:**
```yaml
# config/recurring.yml
check_new_chapters:
  class: CheckNewChaptersJob
  schedule: every 30 minutes
  queue: chapter_checks
```

```yaml
# config/queue.yml
queues:
  - default
  - chapter_checks     # Separate queue, controlled concurrency
  - downloads          # Separate queue for download jobs
  - enrichment         # Low-priority metadata enrichment
```

**Per-source concurrency limits:**
- Already using `limits_concurrency` on `CheckSourceForChaptersJob`
- Extend to per-source: `key: ->(_, _, source_id) { "check_chapters:source:#{source_id}" }`
- MangaDex: 3 concurrent checks (generous rate limit)
- HTML scrapers: 1-2 concurrent checks (be polite)

**Staggered scheduling:**
- Don't check all sources at once
- Prioritize sources with active follows
- Check popular sources more frequently (every 15 min), niche sources less (every 2 hours)
- Respect each source's rate limits via `delay_ms` config

**Job coalescing:**
- If multiple users follow the same series on the same source, check once and apply to all
- `CheckSourceForChaptersJob` should check by `(series_id, source_id)`, not by follow

### 5.2 Database Impact

**Current scale** (5 sources): Hundreds of series, thousands of chapters.
**Projected scale** (100+ sources): Tens of thousands of series, millions of chapters.

**Indexing strategy (already good):**

The schema already has excellent indexes:
- `chapters`: Composite index on `(series_id, source_id, chapter_number)` -- perfect for chapter existence checks
- `chapters`: Index on `(series_id, created_at)` -- good for "latest chapters" queries
- `series_sources`: Index on `(source_id, source_series_id)` -- fast source lookups
- `library_series`: Indexes on `anilist_id`, `mal_id`, `mangadex_id` -- fast dedup matching

**Additional indexes needed at scale:**
- `chapters`: Consider partial index on `source_url` WHERE `source_url IS NOT NULL` (for dedup)
- `series`: Full-text search index on `canonical_title` + `alt_titles` for fuzzy matching
- `library_series`: Full-text search index on `canonical_title`

**Partitioning consideration:**
- Not needed until millions of chapters
- When needed: partition `chapters` by `series_id` range (keeps per-series queries fast)
- Partition `scraper_runs` by `created_at` (time-series data, old runs can be archived)

**Counter caches:**
- `series.chapters_count` already exists
- Add: `library_series.series_count` (how many source-series are linked)
- Add: `source.series_count`, `source.chapters_count` (for the source browser)

### 5.3 API Rate Limits

**Per-source rate limiting is already handled** by `HttpClient#with_rate_limit` using `delay_ms` config. This needs to be extended for scale:

**Source-level rate limit configs:**

| Source | Rate Limit | `delay_ms` | Concurrent Jobs |
|--------|-----------|------------|-----------------|
| MangaDex | 5 req/s globally | 200ms | 3 |
| ComicK | Unknown (be conservative) | 500ms | 2 |
| MangaFire | Unknown | 500ms | 2 |
| Madara sites | Varies (WordPress hosting) | 1000ms | 1 |
| MangaThemesia sites | Varies | 800ms | 1 |

**Global rate limiter:**

The current per-adapter-instance rate limiting works for single jobs, but not across concurrent jobs hitting the same source. Need a shared rate limiter:

```ruby
# Conceptual: Redis-backed rate limiter
class SourceRateLimiter
  def self.acquire(source_key, &block)
    # Use Redis SETNX with TTL for distributed locking
    # Or Solid Queue's concurrency controls
    with_rate_limit(source_key) { yield }
  end
end
```

**Backoff strategy:**
- On HTTP 429: Exponential backoff (1s, 2s, 4s, 8s, 16s max)
- On HTTP 503: Back off longer (30s, then retry)
- On 3 consecutive failures: Disable source for 5 minutes, then retry
- Track backoff state in `SeriesSource#consecutive_failures`

### 5.4 Caching

**Source metadata caching:**
- Cache source catalog/directory data (MangaSee's `_search.php` is 2MB+ JSON)
- Use `Rails.cache` (Solid Cache) with TTL: 1 hour for catalog data, 5 min for chapter lists
- Key pattern: `"source:#{key}:catalog"`, `"source:#{key}:chapters:#{series_id}"`

**Chapter list caching:**
- Cache chapter lists per series per source
- Invalidate on successful chapter check
- TTL: 15 minutes (balance freshness vs. load)

**Cover image caching:**
- Already using Active Storage for downloaded covers
- For remote covers: cache the URL resolution (some sources use CDN URLs that expire)

**Search result caching:**
- Short TTL (2 minutes) to avoid stale results
- Cache key includes query and source
- Useful for federated search where multiple sources are hit simultaneously

---

## 6. Community Contribution Model

### 6.1 Adapter Submission Flow

Inspired by Prowlarr's Cardigann system and keiyoushi's extension contribution model.

**Two contribution paths:**

**Path A: Config-only (low barrier)**
- Contributor creates a YAML config file for a Madara/MangaThemesia site
- Tests it locally with the smoke test
- Submits PR with just the YAML file
- Maintainer reviews and merges

**Path B: Code adapter (higher barrier)**
- Contributor scaffolds with `rails generate adapter`
- Implements the 4 required methods
- Writes tests (see 6.2)
- Submits PR with adapter code + tests + config

### 6.2 Testing Requirements

Every adapter must pass:

**1. Smoke test (automated, required):**
```ruby
class AdapterSmokeTest
  # Search for a known popular title
  # Verify search returns results with required fields
  # Fetch series metadata for first result
  # Verify series has title, cover, status
  # Fetch chapters for the series
  # Verify chapters have numbers and URLs
  # Fetch pages for first chapter
  # Verify pages have image URLs
end
```

The existing `ScraperSmokeJob` already does this. Extend it into a test helper.

**2. Fixture tests (for code adapters):**
- Record HTTP responses with VCR or Webmock
- Test parsing logic against known HTML/JSON structures
- Assert specific fields are extracted correctly

**3. Integration test (CI, nightly):**
- Run smoke tests against live sources
- Track success/failure rates over time
- Alert on breakage

### 6.3 Adapter Quality Tiers

| Tier | Label | Requirements | UI Treatment |
|------|-------|-------------|--------------|
| **Official** | Built by Scanarr team | Full test coverage, monitored | No badge needed |
| **Verified** | Community-submitted, team-reviewed | Smoke tests pass, code reviewed | "Verified" badge |
| **Community** | Community-submitted, minimal review | Config-only or basic code review | "Community" badge |
| **Experimental** | Untested or known flaky | Submitted but not fully verified | "Experimental" badge, hidden by default |

**Promotion path:**
- Experimental -> Community: Smoke tests pass for 7 days
- Community -> Verified: Code review + 30 days of reliability > 90%
- Verified -> Official: Scanarr team adopts maintenance

### 6.4 Documentation for Contributors

Provide:
- `CONTRIBUTING_ADAPTERS.md` with step-by-step guide
- Example adapters annotated with comments
- YAML config template with all available options
- Test helper that makes writing adapter tests easy
- Reference to keiyoushi Kotlin implementations for parsing logic

---

## 7. Implementation Phases

### Phase 1: Foundation (2-3 weeks)

**Goal**: Refactor adapter infrastructure to support dynamic discovery without breaking existing functionality.

1. **Extract shared base classes**: Create `ApiAdapter` and `HtmlAdapter` from patterns in existing adapters. Refactor MangaDex to extend `ApiAdapter`, WeebCentral/MangaPill to extend `HtmlAdapter`.

2. **Rewrite AdapterRegistry**: Replace static `ADAPTERS` hash with auto-discovery. Scan `app/scrapers/*/adapter.rb` for classes inheriting from `BaseAdapter`. Keep backward compatibility.

3. **Config-driven framework**: Implement `MadaraAdapter` base class with configurable selectors. Create the YAML config loading system. Add 2-3 Madara sites as proof of concept.

4. **Adapter generator**: `rails generate adapter <name> --type=<api|html> --framework=<madara|themesia>`

5. **Source sync**: Rake task to sync YAML configs to `Source` database records.

**Deliverables**: 5 existing adapters still work, MadaraAdapter with 3 configs, generator, dynamic registry.

### Phase 2: Scale Out (2-3 weeks)

**Goal**: Add 20+ sources using the new infrastructure.

1. **ComicK adapter**: High-priority API-based adapter. Similar to MangaDex.
2. **MangaThemesiaAdapter**: Base class + 5-10 configs for manhwa scanlation sites.
3. **Madara configs**: Add 10-15 more Madara sites via YAML configs.
4. **Bato.to adapter**: Custom adapter with CryptoAES handling.
5. **TCBScans adapter**: Small but important for One Piece/JJK fans.
6. **MangaKakalot network adapter**: One adapter covering mangakakalot/manganato/mangabuddy variants.

**Deliverables**: 30+ total sources, two framework base classes, proven config-driven pattern.

### Phase 3: Deduplication + Source Management (2-3 weeks)

**Goal**: Handle multi-source series matching and user-facing source management.

1. **SeriesMatcher**: Implement the multi-pass matching algorithm (external IDs, normalized title, fuzzy match).
2. **AniList enrichment**: Background job to fetch AniList/MAL IDs for `LibrarySeries`.
3. **Source browser UI**: Three-tab layout (Enabled/Available/Health).
4. **Source enable/disable**: User-facing toggle with per-source settings.
5. **Federated search**: Search across enabled sources with Turbo Stream progressive results.
6. **Source health dashboard**: Extend existing ScraperRun data into admin dashboard.

**Deliverables**: Automatic dedup, source browser, federated search, health monitoring.

### Phase 4: Performance + Polish (2-3 weeks)

**Goal**: Handle 100+ sources without performance degradation.

1. **Shared rate limiter**: Cross-job rate limiting per source.
2. **Staggered scheduling**: Prioritize sources with active follows, check less-popular sources less often.
3. **Caching layer**: Source catalog caching, chapter list caching, search result caching.
4. **Source fallback**: Automatic fallback when primary source fails.
5. **Best-source selection**: Weighted scoring for download source preference.
6. **Hot-reloading**: `FileUpdateChecker` for YAML configs in development.

**Deliverables**: Production-ready performance at 100+ sources.

### Phase 5: Community + Ecosystem (Ongoing)

**Goal**: Enable community contributions and expand source coverage.

1. **Contribution documentation**: `CONTRIBUTING_ADAPTERS.md`, annotated examples, config templates.
2. **Adapter quality tiers**: Implement tier badges in source browser.
3. **CI adapter tests**: Nightly smoke tests against live sources.
4. **Manga Plus adapter**: Official source with protobuf API (complex but valuable).
5. **Multi-language expansion**: Add non-English sources (French, Spanish, Portuguese, etc.)
6. **Config-driven growth**: Add Madara/Themesia sites as YAML configs (community PRs).

**Deliverables**: Self-sustaining contribution model, 100+ sources.

---

## Appendix A: Keiyoushi Multi-Source Framework Reference

The keiyoushi/extensions-source repository provides Kotlin implementations that serve as the reference for building Scanarr adapters. Key frameworks to port:

| Framework | Sites Covered | Key Patterns |
|-----------|--------------|--------------|
| Madara | 50+ | AJAX chapter loading, `wp-admin/admin-ajax.php`, configurable selectors |
| MangaThemesia | 30+ | Project pages, `div.chapternum`, customizable directory |
| FMReader | 10+ | FM-specific parsing |
| Keyoapp | 5+ | Emerging framework |
| GreenShit | 5+ | Portuguese sources, auth |

**For each framework, the Kotlin source provides:**
- Base class with default selectors and URL patterns
- Override points for site-specific behavior
- Date parsing for various locale formats
- Image URL extraction (including lazy-loading, encrypted URLs)
- Pagination handling

These serve as a direct porting reference. Most Kotlin parsing logic translates cleanly to Ruby + Nokogiri.

## Appendix B: External API References

| API | Base URL | Auth | Rate Limit | Use Case |
|-----|----------|------|-----------|----------|
| MangaDex | `api.mangadex.org` | None (public) | 5 req/s/IP | Chapters, search, metadata |
| ComicK | `api.comick.fun` | None (public) | Unknown | Chapters, search, metadata |
| AniList | `graphql.anilist.co` | None (public) | 90 req/min | Series metadata enrichment |
| Jikan (MAL) | `api.jikan.moe/v4` | None (public) | 3 req/s | Fallback metadata |
| MangaPlus | Protobuf (reverse-engineered) | None | Unknown | Official chapters |

## Appendix C: Database Schema Additions (Projected)

New columns/tables that may be needed:

**`sources` table additions:**
- `category` (string): "official", "scanlation", "aggregator", "scan_group"
- `language` (string): Primary language
- `content_focus` (string): "manga", "manhwa", "manhua", "mixed"
- `quality_tier` (string): "official", "verified", "community", "experimental"
- `adapter_type` (string): "code", "config"
- `framework` (string, nullable): "madara", "manga_themesia", etc.
- `config_path` (string, nullable): Path to YAML config file
- `last_health_check_at` (datetime)
- `avg_response_time_ms` (integer)

**`source_title_mappings` table (new):**
- `id`
- `source_id` (FK)
- `external_id` (string): The series ID on the source
- `library_series_id` (FK)
- `confidence` (decimal): How confident the match is
- `verified` (boolean): Manually verified by user
- `created_at`, `updated_at`

Purpose: Track which external series IDs on each source map to which `LibrarySeries`. Enables instant matching for known series and supports the multi-pass matching algorithm.

---

*This document is research only. No implementation code should be written until the approach is reviewed and approved.*
