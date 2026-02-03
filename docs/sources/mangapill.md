# MangaPill

## Source Information

| Property | Value |
|----------|-------|
| **Base URL** | https://mangapill.com |
| **Type** | HTML Scraping |
| **Rate Limit** | ~400ms delay recommended |
| **Language** | English |
| **Keiyoushi Reference** | [src/en/mangapill](https://github.com/keiyoushi/extensions-source/tree/main/src/en/mangapill) |

## Implementation Notes

### Search

- **Endpoint**: `/search?q={query}`
- **Method**: GET with URL-encoded query parameter
- **Selectors**: 
  - Results container: `.grid > div`
  - Title: `a > div` (last child)
  - Cover: `img[data-src]` or `img[src]`
  - URL: `a[href]`

### Series Details

- **URL Format**: `/manga/{id}/{slug}`
- **Selectors**:
  - Title: `h1`
  - Cover: `img[data-src]` (first match)
  - Description: `p.text--secondary` or `[class*='summary']`
  - Author/Status: Look for label text followed by value

### Chapter List

- **Location**: Same page as series details
- **Selectors**: `a[href*='/chapters/']`
- **URL Format**: `/chapters/{manga_id}-{chapter_num}000/{slug}-chapter-{num}`
- **Chapter Number Extraction**: 
  - From URL: `-(\d+)000\/` pattern
  - From text: `chapter[- ]?(\d+(?:\.\d+)?)`

### Page Images

- **Selectors**: `img[data-src]` (lazy-loaded images)
- **Fallback**: `.container img`, `[id*='reader'] img`
- **Image Filtering**: Exclude logos, avatars, icons, favicons

## Known Quirks

1. Images use lazy loading with `data-src` attribute
2. Chapter numbers are embedded in URL with trailing zeros (e.g., `1117` becomes `11117000`)
3. Some series have alternative titles in `h2.text--secondary`
4. Page images may be served from various CDN domains

## Test URLs

- **Search**: https://mangapill.com/search?q=one+piece
- **Series**: https://mangapill.com/manga/2/one-piece
- **Chapter**: https://mangapill.com/chapters/2-11117000/one-piece-chapter-1117

## Status

- [x] Search implemented
- [x] Series details implemented
- [x] Chapter list implemented
- [x] Page images implemented
- [ ] Tests with VCR cassettes
