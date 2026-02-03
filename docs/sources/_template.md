# Source Name

> Template for documenting a new source adapter. Copy this file and fill in the details.

## Overview

| Property | Value |
|----------|-------|
| **Site URL** | https://example.com |
| **Keiyoushi Reference** | [extensions-source/src/en/example](https://github.com/keiyoushi/extensions-source/tree/main/src/en/example) |
| **Type** | API / HTML Scraping |
| **Status** | 🔲 Planned / 🚧 In Progress / ✅ Implemented |
| **Adapter Path** | `app/scrapers/source_name/adapter.rb` |

## Configuration

```yaml
# config/sources.yml
source_name:
  base_url: "https://example.com"
  delay_ms: 500
  open_timeout: 10
  read_timeout: 20
  max_retries: 2
  headers:
    User-Agent: "ScanarrScraper/0.1"
    # Add any required headers (Referer, etc.)
```

## Search

### Endpoint

- **Method**: GET / POST
- **URL**: `/search` or `/api/search`
- **Parameters**:
  - `q` or `query`: Search term
  - `page`: Page number (if paginated)

### Response Format

```
API: JSON response structure
HTML: CSS selectors for results
```

### Selectors (HTML)

| Element | Selector |
|---------|----------|
| Result container | `.search-results` |
| Series link | `a.series-link` |
| Title | `.title` |
| Cover image | `img.cover` |

### Notes

- Any quirks with search (encoding, special characters, etc.)

---

## Series Detail

### Endpoint

- **URL Pattern**: `/manga/{id}` or `/series/{slug}`

### Selectors / Fields

| Field | Selector / JSON Path |
|-------|---------------------|
| Title | `h1.title` |
| Cover | `img.cover` |
| Author | `.author` |
| Artist | `.artist` |
| Description | `.description` |
| Status | `.status` |
| Tags/Genres | `.tags a` |

### Status Mapping

| Site Value | Scanarr Value |
|------------|---------------|
| "Ongoing" | `ongoing` |
| "Completed" | `completed` |
| "Hiatus" | `hiatus` |

### Notes

- Any quirks with series parsing

---

## Chapter List

### Endpoint

- **URL Pattern**: `/manga/{id}/chapters` or embedded in series page
- **Pagination**: Infinite scroll / Load more button / Page numbers

### Selectors / Fields

| Field | Selector / JSON Path |
|-------|---------------------|
| Chapter container | `.chapter-list` |
| Chapter link | `a.chapter` |
| Chapter number | Extract from text |
| Chapter title | `.chapter-title` |
| Published date | `.date` |
| Scanlation group | `.group` |

### Chapter Number Extraction

```ruby
# Regex pattern for extracting chapter number from title
title[/Chapter\s*(\d+(?:\.\d+)?)/i, 1]
```

### Pagination Handling

Describe how pagination works:
- AJAX loading with offset/limit
- Infinite scroll with intersection observer
- Traditional page numbers

### Notes

- Any quirks with chapter parsing (date formats, sorting, etc.)

---

## Page Extraction

### Endpoint

- **URL Pattern**: `/chapter/{id}` or `/read/{manga}/{chapter}`

### Image Sources

| Type | Selector / Method |
|------|-------------------|
| Direct | `img.page-image` |
| Lazy-loaded | `img[data-src]` |
| AJAX endpoint | `/chapter/{id}/images` |

### Image URL Patterns

```
https://cdn.example.com/manga/{id}/{chapter}/{page}.jpg
```

### Headers Required

```yaml
# Headers needed for image requests
Referer: "https://example.com"
```

### Notes

- Image loading patterns (long strip vs paged)
- CDN/server selection logic
- Any obfuscation or encoding

---

## Known Quirks / Gotchas

1. **Rate Limiting**: Describe any rate limit behavior
2. **Cloudflare**: Does it use Cloudflare protection?
3. **Dynamic Content**: JavaScript-rendered content?
4. **Image Hotlinking**: Referer header requirements?
5. **URL Encoding**: Special character handling?
6. **Regional Restrictions**: Geo-blocking?

---

## Test URLs

Use these URLs for testing the adapter:

### Search

```
Query: "solo leveling"
Expected: Should return Solo Leveling series
```

### Series

```
URL: https://example.com/manga/solo-leveling
Expected fields:
- Title: Solo Leveling
- Author: Chugong
- Status: Completed
- Chapters: 200+
```

### Chapter

```
URL: https://example.com/chapter/12345
Expected: 15-20 page images
```

---

## Implementation Checklist

- [ ] Research site structure
- [ ] Document in this file
- [ ] Create adapter skeleton
- [ ] Implement `search()`
- [ ] Implement `series()`
- [ ] Implement `chapters()`
- [ ] Implement `pages()`
- [ ] Add configuration to `sources.yml`
- [ ] Write tests with VCR cassettes
- [ ] Handle edge cases and errors
- [ ] Test with real data
