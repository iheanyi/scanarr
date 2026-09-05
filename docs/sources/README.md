# Source Adapters

This directory contains documentation for Scanarr's manga source adapters. Each adapter enables fetching series metadata, chapter lists, and page images from a specific manga aggregator site.

## Keiyoushi Extensions Reference

Our adapters are informed by the [Keiyoushi extensions-source](https://github.com/keiyoushi/extensions-source) repository, which maintains Tachiyomi/Mihon extensions in Kotlin. Studying their implementations helps understand:

- Site structure and API patterns
- Rate limiting requirements
- Common quirks and workarounds
- Selectors and parsing strategies

## Target Sources

For current active backlog and missing adapter swarm targets, see
`tasks/adapter-swarm-missing-extensions.md`.

| Source | Status | Type | Keiyoushi Reference |
|--------|--------|------|---------------------|
| [MangaDex](mangadex.md) | ✅ Implemented | API | [extensions-source/src/all/mangadex](https://github.com/keiyoushi/extensions-source/tree/main/src/all/mangadex) |
| [Comix](comix.md) | Planned; browser runtime required | Browser + protected API | [extensions-source/src/en/comix](https://github.com/keiyoushi/extensions-source/tree/main/src/en/comix) |
| [WeebCentral](weeb_central.md) | ✅ Implemented | HTML | N/A (newer site) |
| MangaSee | ✅ Implemented | HTML | [extensions-source/src/en/mangasee](https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangasee) |
| AsuraScans | ✅ Implemented | HTML (Madara) | [lib-multisrc/madara](https://github.com/keiyoushi/extensions-source/tree/main/lib-multisrc/madara) |
| ReaperScans | 🔲 Planned | HTML | [extensions-source/src/en/reaperscans](https://github.com/keiyoushi/extensions-source/tree/main/src/en/reaperscans) |
| FlameScans | ✅ Implemented (as FlameComics) | HTML/API | [extensions-source/src/en/flamecomics](https://github.com/keiyoushi/extensions-source/tree/main/src/en/flamecomics) |
| MangaKakalot | ✅ Implemented | HTML | [extensions-source/src/en/mangakakalot](https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangakakalot) |
| TCBScans | ✅ Implemented | HTML | [extensions-source/src/en/tcbscans](https://github.com/keiyoushi/extensions-source/tree/main/src/en/tcbscans) |

## Adding a New Source Adapter

### Provider challenges

The shared HTTP client recognizes Cloudflare's `cf-mitigated: challenge`
response header and raises `ChallengeRequiredError` before an adapter parses
the response. Existing source and reader error views display the explanation.
It also recognizes Comix's observed `/@waf/challenge` redirect. This does not
solve CAPTCHAs or detect every provider's custom verification page.

A future human-assisted resolution flow needs a browser session on the server,
provider-scoped session storage, an authenticated operator interface, expiration
handling, and bounded job retries. Provider requests must use the verified session;
opening the provider in a user's separate browser is not sufficient. Do not store
clearance cookies in public source configuration or logs. Comix additionally needs
the runtime and image-processing work described in its source document.

References: [Cloudflare challenge detection](https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/)
and [clearance semantics](https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/).

### 1. Research the Source

1. Study the Keiyoushi extension if available (see links above)
2. Use browser DevTools to observe:
   - Search API/form submission
   - Series page structure
   - Chapter list loading (pagination, infinite scroll, AJAX)
   - Chapter reader page structure
3. Document findings in `docs/sources/<source_name>.md` using the [template](_template.md)

### 2. Create the Adapter

```ruby
# app/lib/scrapers/<source_name>/adapter.rb
module SourceName
  class Adapter < ::BaseAdapter
    def search(query)
      # Return Array<ResultTypes::SearchResult>
    end

    def series(id_or_url)
      # Return ResultTypes::Series
    end

    def chapters(series_url)
      # Return Array<ResultTypes::Chapter>
    end

    def pages(chapter_url)
      # Return Array<ResultTypes::Page>
    end
  end
end
```

### 3. Add Configuration

```yaml
# config/sources.yml
source_name:
  base_url: "https://example.com"
  delay_ms: 500  # Rate limit between requests
  open_timeout: 10
  read_timeout: 20
  max_retries: 2
  headers:
    User-Agent: "ScanarrScraper/0.1"
```

### 4. Write Tests

Create tests in `test/scrapers/<source_name>/adapter_test.rb` with VCR cassettes for reproducible HTTP fixtures.

## Key Patterns in Keiyoushi Kotlin Code

When studying Keiyoushi extensions, look for these patterns:

### Base URLs and Rate Limiting

```kotlin
override val baseUrl = "https://example.com"
override val client = network.cloudflareClient.newBuilder()
    .rateLimitHost(baseUrl.toHttpUrl(), 2, 1) // 2 requests per second
    .build()
```

### Search Implementation

- Look for `searchMangaRequest()` and `searchMangaParse()`
- Note whether it's a GET with query params or POST with form data
- Check for pagination handling

### Series Parsing

- Look for `mangaDetailsParse()`
- Note CSS selectors used for title, cover, author, description, tags
- Check for status mapping (ongoing, completed, etc.)

### Chapter List

- Look for `chapterListParse()` or `chapterListRequest()`
- Watch for AJAX-loaded content or infinite scroll
- Note date format parsing
- Check for chapter number extraction regex

### Page Extraction

- Look for `pageListParse()` or `imageUrlParse()`
- Note if images are lazy-loaded (data-src vs src)
- Check for image server selection or CDN patterns
- Watch for obfuscation or encoded URLs

### Common Gotchas

- **Cloudflare protection**: Some sites require solving challenges
- **Rate limiting**: Aggressive sites may ban IPs
- **Dynamic content**: JavaScript-rendered pages need different handling
- **Image hotlinking**: Some sites check Referer headers
- **URL encoding**: Non-ASCII characters in URLs
- **Timezone issues**: Chapter dates may be in different timezones

## Adapter Interface

All adapters inherit from `BaseAdapter` and must implement:

| Method | Returns | Description |
|--------|---------|-------------|
| `search(query)` | `Array<SearchResult>` | Search for series by title |
| `series(id_or_url)` | `Series` | Get series metadata |
| `chapters(series_url)` | `Array<Chapter>` | Get chapter list |
| `pages(chapter_url)` | `Array<Page>` | Get page image URLs |

See `app/lib/scrapers/result_types.rb` for the result type definitions.
