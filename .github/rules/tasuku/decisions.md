# Tasuku Decisions

_Auto-synced from .tasuku/context/decisions.md_

## adapter-reference-source (2026-02-06)

**Chose**: Use keiyoushi/extensions-source (Mihon/Tachiyomi community extensions) as the reference for building new adapters

**Over**: Writing adapters from scratch by reverse-engineering each site, Using other aggregator projects as reference

**Because**: keiyoushi has Kotlin implementations for hundreds of manga sources with parsing logic, URL patterns, and API structures already mapped out. Much faster to port to Ruby than reverse-engineering from scratch. Community-maintained and up-to-date.

