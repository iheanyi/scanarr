# WeebCentral

## Overview

| Property | Value |
|----------|-------|
| **Site URL** | https://weebcentral.com |
| **Keiyoushi Reference** | N/A (newer site, no Keiyoushi extension) |
| **Type** | HTML Scraping |
| **Status** | ✅ Implemented |
| **Adapter Path** | `app/scrapers/weeb_central/adapter.rb` |

WeebCentral is a newer manga aggregator that uses modern web techniques including HTMX for dynamic content loading. Unlike API-based sources, this adapter parses HTML responses.

## Configuration

```yaml
# config/sources.yml
weeb_central:
  base_url: "https://weebcentral.com"
  delay_ms: 400
  open_timeout: 10
  read_timeout: 20
  max_retries: 2
  proxy_url:  # Optional proxy
  headers:
    User-Agent: "ScanarrScraper/0.1"
```

### Optional Configuration

```yaml
max_chapter_pages: 10  # Limit chapter pagination (for testing)
```

---

## Search

### Endpoint

- **Method**: POST
- **URL**: `/search/simple`
- **Parameters**: `location=main` (query param)
- **Body**: `text={query}` (form data)

### Implementation

```ruby
response = http.post("/search/simple", 
  params: { location: "main" }, 
  body: { text: query }
)
doc = Nokogiri::HTML(response.body)
```

### Selectors

| Element | Selector | Notes |
|---------|----------|-------|
| Series links | `a[href*='/series/']` | Filter by href pattern |
| Title | Link text | `.strip` to clean whitespace |
| Cover | `img` inside link | Check both `src` and `data-src` |

### Post-Processing

- Deduplicate results by URL
- Exclude `/series/random` links (random series feature)

### Notes

- Search uses POST with form data, not GET
- Results are HTML fragments embedded in page

---

## Series Detail

### Endpoint

- **URL Pattern**: `/series/{id}` or `/series/{id}-{slug}`
- The site redirects `/series/{id}` to the full slug URL

### Selectors

| Field | Selector | Notes |
|-------|----------|-------|
| Title | `h1` | First h1 on page |
| Cover | `img[alt$=" cover"]` or `img[width="400"]` | 400x600 dimensions |
| Author | `dt:contains("Author") + dd` | Uses labeled text extraction |
| Artist | `dt:contains("Artist") + dd` | Uses labeled text extraction |
| Description | `p` | First paragraph |

### Labeled Text Extraction

The site uses definition lists (`<dt>`/`<dd>`) or tables for metadata. The adapter searches for labels in multiple formats:

```ruby
def extract_labeled_text(doc, label)
  # Try <dt>/<dd> pairs
  dt = doc.css("dt").find { |node| node.text.strip.downcase == label.downcase }
  return dt.next_element&.text&.strip if dt
  
  # Try <th>/<td> pairs
  th = doc.css("th").find { |node| node.text.strip.downcase == label.downcase }
  return th.next_element&.text&.strip if th
  
  # Try labeled spans
  span = doc.css("span, strong, b").find { |node| node.text.strip.downcase == label.downcase }
  return span.next_element&.text&.strip if span
end
```

### Notes

- Status and tags are not currently extracted (site structure varies)
- Series type defaults to "manga"

---

## Chapter List

### Endpoint

- **URL**: Same as series page (chapters embedded)
- **Pagination**: HTMX-based lazy loading

### Selectors

| Element | Selector |
|---------|----------|
| Chapter links | `a[href*='/chapters/']` |
| Load more button | `[hx-get]` or `[data-hx-get]` |

### Pagination Handling

WeebCentral uses HTMX for infinite scroll/load more. The adapter:

1. Collects chapter links from initial page
2. Finds "load more" element with `hx-get` attribute
3. Fetches the next page URL
4. Repeats until no more pages or `max_chapter_pages` reached

```ruby
next_url = doc.at_css("[hx-get],[data-hx-get]")
path = next_url&.[]("hx-get") || next_url&.[]("data-hx-get")
```

### Chapter Number Extraction

```ruby
def extract_chapter_number(text)
  text.to_s[/(\d+(\.\d+)?)/, 1]  # Matches "123" or "123.5"
end
```

### Title Cleaning

Chapter titles may contain UI elements like "Last Read" markers:

```ruby
def clean_chapter_title(text)
  cleaned = text.gsub(/\s+/, " ").strip
  cleaned.split("Last Read").first.strip
end
```

### Notes

- Chapters are returned in site order (usually newest first)
- Volume information is not available

---

## Page Extraction

### Endpoint

- **URL Pattern**: `/chapters/{id}` or `/chapters/{id}-{slug}`

### Image Loading

The site uses HTMX to lazy-load images. The adapter:

1. Finds the images endpoint via `hx-get` attribute containing `/images`
2. Fetches with `reading_style=long_strip` for all images at once
3. Falls back to inline images if no HTMX endpoint

```ruby
images_url = doc.css("[hx-get]")
  .map { |node| node["hx-get"] }
  .find { |path| path.include?("/images") }

if images_url
  response = http.get(images_url, params: { reading_style: "long_strip" })
  # Parse images from response
end
```

### Selectors

| Element | Selector | Notes |
|---------|----------|-------|
| Page images | `img` | Check `data-src` first, then `src` |

### Image Filtering

Not all images are manga pages. The adapter filters:

```ruby
def content_image?(src)
  return false if src.match?(%r{/assets/}i)  # Site assets
  return false if src.match?(/logo|icon/i)   # UI elements
  
  # Valid content patterns
  src.include?("/chapters/") || 
  src.include?("/manga/") || 
  src.match?(/\.(jpg|jpeg|png|webp)(\?|$)/i)
end
```

---

## Known Quirks / Gotchas

1. **HTMX Dynamic Loading**: The site heavily uses HTMX. Chapter lists and page images are loaded via AJAX-like requests with `hx-get` attributes.

2. **Lazy-Loaded Images**: Always check `data-src` before `src` for actual image URLs.

3. **Rate Limiting**: 400ms delay between requests is recommended to avoid being blocked.

4. **URL Slugs**: Series and chapter URLs include slugs that may change. The adapter extracts IDs from URL patterns.

5. **Reading Styles**: The images endpoint supports `reading_style` parameter:
   - `long_strip`: All images in vertical scroll
   - `paged`: One image at a time

6. **Cover Images**: Look for images with "cover" in alt text or specific dimensions (400x600).

7. **Chapter Ordering**: Chapters come from the site in display order, which may not match chapter numbers.

---

## Test URLs

### Search

```
Query: "one piece"
Expected: Should return One Piece series
```

### Series

```
URL: https://weebcentral.com/series/{id}-one-piece
Expected:
- Title: One Piece
- Cover: 400x600 image
- Author: Eiichiro Oda
```

### Chapter

```
URL: https://weebcentral.com/chapters/{id}
Expected: Array of page image URLs (typically 15-25 pages)
```

---

## Implementation Status

- [x] `search()` - POST-based search with deduplication
- [x] `series()` - HTML parsing with labeled text extraction
- [x] `chapters()` - HTMX pagination handling
- [x] `pages()` - HTMX images endpoint with fallback
- [x] Image filtering (exclude assets/icons)
- [x] URL normalization
- [x] Rate limiting via HttpClient
