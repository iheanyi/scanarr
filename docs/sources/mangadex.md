# MangaDex

## Overview

| Property | Value |
|----------|-------|
| **Site URL** | https://mangadex.org |
| **API URL** | https://api.mangadex.org |
| **Keiyoushi Reference** | [extensions-source/src/all/mangadex](https://github.com/keiyoushi/extensions-source/tree/main/src/all/mangadex) |
| **Type** | REST API (JSON) |
| **Status** | ✅ Implemented |
| **Adapter Path** | `app/scrapers/mangadex/adapter.rb` |

MangaDex is the largest free manga aggregator with a well-documented public API. Unlike most sources, it doesn't require HTML scraping—all data is available via JSON endpoints.

## Configuration

```yaml
# config/sources.yml
mangadex:
  base_url: "https://api.mangadex.org"
  delay_ms: 200
  open_timeout: 10
  read_timeout: 20
  max_retries: 2
  headers:
    User-Agent: "ScanarrScraper/0.1"
```

## API Reference

Full API documentation: https://api.mangadex.org/docs/

## Search

### Endpoint

- **Method**: GET
- **URL**: `/manga`
- **Parameters**:
  - `title`: Search query
  - `limit`: Results per page (max 100)
  - `includes[]`: Related data to embed (`cover_art`, `author`)

### Implementation

```ruby
response = http.get("/manga", params: { 
  title: query, 
  limit: 20, 
  includes: ["cover_art", "author"] 
})
```

### Response Structure

```json
{
  "result": "ok",
  "data": [
    {
      "id": "uuid",
      "type": "manga",
      "attributes": {
        "title": { "en": "Title" },
        "altTitles": [{ "ja": "日本語タイトル" }],
        "description": { "en": "Description" },
        "originalLanguage": "ja",
        "status": "ongoing"
      },
      "relationships": [
        { "type": "cover_art", "attributes": { "fileName": "cover.jpg" } },
        { "type": "author", "attributes": { "name": "Author Name" } }
      ]
    }
  ]
}
```

### Notes

- Title/description are localized objects—we prefer English (`en`) then fallback to first available
- Cover URL pattern: `https://uploads.mangadex.org/covers/{manga_id}/{filename}`

---

## Series Detail

### Endpoint

- **Method**: GET
- **URL**: `/manga/{id}`
- **Parameters**:
  - `includes[]`: `cover_art`, `author`, `artist`

### Implementation

```ruby
response = http.get("/manga/#{id}", params: { 
  includes: ["cover_art", "author", "artist"] 
})
```

### Field Mapping

| API Field | Scanarr Field |
|-----------|---------------|
| `attributes.title.en` | `title` |
| `attributes.altTitles` | `alt_titles` |
| `attributes.description.en` | `description` |
| `attributes.status` | `status` |
| `attributes.originalLanguage` | → `series_type` mapping |
| `relationships[type=author].attributes.name` | `author` |
| `relationships[type=artist].attributes.name` | `artist` |
| `relationships[type=cover_art].attributes.fileName` | → `cover_url` |

### Series Type Mapping

| Original Language | Series Type |
|-------------------|-------------|
| `ja` | `manga` |
| `ko` | `manhwa` |
| `zh` | `manhua` |
| Other | `manga` |

---

## Chapter List

### Endpoint

- **Method**: GET
- **URL**: `/chapter`
- **Parameters**:
  - `manga`: Manga UUID
  - `limit`: Max 100
  - `offset`: Pagination offset
  - `translatedLanguage[]`: Filter by language (default: `en`)
  - `contentRating[]`: `safe`, `suggestive`, `erotica`, `pornographic`
  - `includeFuturePublishAt`: Include scheduled chapters
  - `includeExternalUrl`: Include external chapters
  - `order[chapter]`: `asc` or `desc`
  - `includes[]`: `scanlation_group`

### Implementation

```ruby
loop do
  response = http.get("/chapter", params: {
    manga: id,
    limit: 100,
    offset: offset,
    translatedLanguage: ["en"],
    contentRating: %w[safe suggestive erotica pornographic],
    includeFuturePublishAt: 1,
    includeExternalUrl: 1,
    order: { chapter: "asc" },
    includes: ["scanlation_group"]
  })
  
  # Accumulate chapters...
  break if offset >= total
end
```

### Deduplication

Multiple scanlation groups may upload the same chapter. We deduplicate by chapter number, keeping the most recently published version.

### Notes

- Pagination is required—API returns max 100 chapters per request
- `total` field in response indicates total available chapters
- Some chapters are external (link to scanlator's site)

---

## Page Extraction

### Endpoint

- **Method**: GET  
- **URL**: `/at-home/server/{chapter_id}`

This uses MangaDex's "at-home" CDN system where volunteer servers host chapter images.

### Implementation

```ruby
response = http.get("/at-home/server/#{chapter_id}")
```

### Response Structure

```json
{
  "result": "ok",
  "baseUrl": "https://uploads.mangadex.org",
  "chapter": {
    "hash": "abc123...",
    "data": ["page1.jpg", "page2.jpg", ...],
    "dataSaver": ["page1.jpg", "page2.jpg", ...]
  }
}
```

### Image URL Construction

- **Full quality**: `{baseUrl}/data/{hash}/{filename}`
- **Data saver**: `{baseUrl}/data-saver/{hash}/{filename}`

### Error Handling

| Error | Handling |
|-------|----------|
| Chapter not found | Raise `ChapterNotFoundError` |
| Rate limit exceeded | Raise `RateLimitError` |
| Unexpected response | Raise `SourceUnavailableError` |

---

## Known Quirks / Gotchas

1. **Rate Limiting**: MangaDex has rate limits (~5 req/s for most endpoints). Our 200ms delay is conservative.

2. **UUID Format**: All IDs are UUIDs (36 characters with hyphens). The adapter extracts them from full URLs.

3. **At-Home Servers**: Page images are served from volunteer-run servers. Occasionally a server may be slow or down.

4. **Content Ratings**: Must explicitly request all content ratings to get all chapters (even safe ones).

5. **External Chapters**: Some chapters link to external sites—we include these but they can't be downloaded through MangaDex.

6. **Localization**: Titles, descriptions, and tags are localized objects. Always check for English first, then fallback.

7. **Future Chapters**: Some chapters have future publish dates (scheduled releases).

---

## Test URLs

### Search

```
Query: "chainsaw man"
Expected: Should return Chainsaw Man by Tatsuki Fujimoto
```

### Series

```
URL: https://mangadex.org/title/a77742b1-befd-49a4-bff5-1f51c53c1d94/chainsaw-man
ID: a77742b1-befd-49a4-bff5-1f51c53c1d94
Expected:
- Title: Chainsaw Man
- Author: Tatsuki Fujimoto
- Status: ongoing
- Type: manga
```

### Chapter

```
URL: https://mangadex.org/chapter/{uuid}
Expected: Array of page image URLs from at-home server
```

---

## Implementation Status

- [x] `search()` - Search manga by title
- [x] `series()` - Get manga details with cover, author, artist
- [x] `chapters()` - Paginated chapter list with deduplication
- [x] `pages()` - At-home server page URLs
- [x] Error handling for API errors
- [x] Rate limiting via HttpClient
