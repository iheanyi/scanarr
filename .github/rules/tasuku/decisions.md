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

