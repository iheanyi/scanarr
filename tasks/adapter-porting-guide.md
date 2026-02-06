# Adapter Porting Guide: keiyoushi/extensions-source to Scanarr

This document provides a comprehensive reference for porting manga source adapters from the
[keiyoushi/extensions-source](https://github.com/keiyoushi/extensions-source) Kotlin project
to Ruby for the Scanarr Rails application. Each section covers one target source with all the
technical details needed to implement the adapter.

**Existing adapters (skip these):** MangaDex, WeebCentral, AsuraScans, MangaSee, MangaPill.

---

## Table of Contents

1. [Scanarr Adapter Architecture](#scanarr-adapter-architecture)
2. [ComicK (comick.live)](#1-comick-comicklive)
3. [MangaKakalot / Manganato](#2-mangakakalot--manganato)
4. [MangaFire](#3-mangafire)
5. [TCBScans](#4-tcbscans)
6. [FlameComics (Flame Scans)](#5-flamecomics-flame-scans)
7. [New Adapter Scaffold Template](#new-adapter-scaffold-template)
8. [Common Patterns and Tips](#common-patterns-and-tips)

---

## Scanarr Adapter Architecture

### BaseAdapter (`app/scrapers/base_adapter.rb`)

All adapters inherit from `BaseAdapter` and must implement four required methods:

```ruby
class BaseAdapter
  attr_reader :config, :http

  def initialize(config:, http: HttpClient.new(config: config))
    @config = config
    @http = http
  end

  # REQUIRED: Search for series by query string
  # @return [Array<ResultTypes::SearchResult>]
  def search(query)

  # REQUIRED: Fetch series details by ID or URL
  # @return [ResultTypes::Series]
  def series(id_or_url)

  # REQUIRED: Fetch chapter list for a series
  # @return [Array<ResultTypes::Chapter>]
  def chapters(series_url)

  # REQUIRED: Fetch page image URLs for a chapter
  # @return [Array<ResultTypes::Page>]
  def pages(chapter_url)

  # OPTIONAL: Browse the catalog
  # @return [Array<ResultTypes::BrowseResult>]
  def browse(sort: "latest", page: 1, limit: 20)

  # OPTIONAL: Whether browsing is supported
  def supports_browse?  # default: false

  # Built-in: normalize status strings
  def normalize_status(status)
end
```

### ResultTypes (`app/scrapers/result_types.rb`)

```ruby
module ResultTypes
  SearchResult = Struct.new(:id, :title, :url, :cover_url, :language, :author, keyword_init: true)

  BrowseResult = Struct.new(
    :id, :title, :url, :cover_url, :language, :author,
    :status, :last_updated, :chapter_count, :description,
    keyword_init: true
  )

  Series = Struct.new(
    :id, :title, :alt_titles, :description, :author, :artist,
    :status, :tags, :series_type, :cover_url, :url,
    keyword_init: true
  )

  Chapter = Struct.new(
    :id, :title, :number, :volume, :language, :group, :published_at, :url,
    keyword_init: true
  )

  Page = Struct.new(:index, :url, :mime_type, keyword_init: true)
end
```

### HttpClient (`app/scrapers/http_client.rb`)

The `HttpClient` wraps Faraday and provides:
- `http.get(path_or_url, headers: {}, params: {})` - returns `Response` struct
- `http.post(path_or_url, headers: {}, params: {}, body: {})` - returns `Response` struct
- Automatic rate limiting via `delay_ms` config
- Retry logic (configurable `max_retries`)
- Proxy support
- Custom headers from config

`Response` struct: `status`, `body`, `headers`, `url`

### Source Configuration (`config/sources.yml`)

Each source needs an entry:

```yaml
source_key:
  base_url: "https://example.com"
  delay_ms: 400
  open_timeout: 10
  read_timeout: 20
  max_retries: 2
  headers:
    User-Agent: "ScanarrScraper/0.1"
    Referer: "https://example.com/"  # if needed
```

### File Structure

```
app/scrapers/
  base_adapter.rb
  http_client.rb
  result_types.rb
  source_name/
    adapter.rb
```

The adapter class is defined in a module matching the directory name (snake_case),
inherits from `::BaseAdapter`, and registers in the `Scrapers` namespace:

```ruby
module SourceName
  class Adapter < ::BaseAdapter
    # ...
  end
end

module Scrapers
  module SourceName
    Adapter = ::SourceName::Adapter
  end
end
```

---

## 1. ComicK (comick.live)

### Overview

| Property | Value |
|----------|-------|
| **Source type** | API-based (JSON REST API) |
| **Difficulty** | Easy-Medium |
| **Priority** | 1 (highest) |
| **keiyoushi class** | `src/all/comicklive/.../Comick.kt` + `Dto.kt` + `Filters.kt` |

### Base URLs and Domain History

- **Current domains:** `https://comick.live`, `https://comick.art`
- **Historical:** `comick.io` (shut down), `comick.fun` (deprecated API), `comick.app` (deprecated)
- **API base:** Same as site domain (e.g., `https://comick.live/api/...`)
- The API path changed from `/comic/{id}/chapter` to `/comic/{hid}/chapters`

### Authentication and Anti-Scraping

- **CloudFlare:** Yes, the site is behind CloudFlare. API endpoints return 403 without proper headers.
- **Required headers:** `Referer: https://comick.live/` is critical
- **Rate limiting:** Be respectful; 400-500ms delay recommended
- **No authentication required** for read-only access

### Key Endpoints

#### Search

```
GET /api/search?q={query}&type=comic&page={page}
```

Response structure:
```json
{
  "data": [
    {
      "default_thumbnail": "https://...",
      "slug": "one-piece",
      "title": "One Piece"
    }
  ],
  "next_cursor": "abc123"  // null if no more pages
}
```

Additional search parameters (all optional):
- `order_by`: `created_at`, `user_follow_count`, `rating`, `uploaded`
- `order_direction`: `asc` or `desc`
- `genres`: genre slug (repeatable)
- `excludes`: excluded genre slug (repeatable)
- `tags`: tag slug (repeatable)
- `demographic`: 0-4 (repeatable)
- `country`: `jp`, `kr`, `cn`, `others` (repeatable)
- `status`: 1=ongoing, 2=completed, 3=cancelled, 4=hiatus
- `minimum`: minimum chapter count
- `time`: created within N days
- `content_rating`: `safe`, `suggestive`, `erotica`
- `showAll`: `false`
- `type`: `comic`
- `cursor`: pagination cursor from previous response

#### Popular / Top

```
GET /api/comics/top?days={7|30|90}&type={follow|most_follow_new}
```

Response:
```json
{
  "data": [
    {
      "default_thumbnail": "...",
      "slug": "...",
      "title": "..."
    }
  ]
}
```

#### Latest Updates

```
GET /api/chapters/latest?order=new&page={page}
```

Same response structure as top.

#### Series Details

```
GET /comic/{slug}  (HTML page)
```

The series data is embedded in the HTML as JSON inside a `#comic-data` script element.
Parse the HTML, find `#comic-data`, extract its text content, and parse as JSON.

JSON structure:
```json
{
  "title": "One Piece",
  "slug": "one-piece",
  "default_thumbnail": "https://...",
  "status": 1,
  "translation_completed": true,
  "authors": [{"name": "Oda Eiichiro"}],
  "artists": [{"name": "Oda Eiichiro"}],
  "desc": "<p>HTML description</p>",
  "content_rating": "safe",
  "country": "jp",
  "md_comic_md_genres": [{"md_genres": {"name": "Action"}}],
  "md_titles": {"en": {"title": "One Piece"}, "ja": {"title": "..."}}
}
```

Status mapping: 1=ongoing, 2=completed (check `translation_completed`), 3=cancelled, 4=hiatus.
Country mapping: `jp`=manga, `ko`=manhwa, `cn`=manhua.

#### Chapter List

```
GET /api/comics/{slug}/chapter-list?lang=en&page={page}
```

Response:
```json
{
  "data": [
    {
      "hid": "abc123",
      "chap": "1094",
      "vol": "105",
      "lang": "en",
      "title": "Chapter title",
      "created_at": "2024-01-15T12:00:00.000000Z",
      "group_name": ["TCB Scans"]
    }
  ],
  "pagination": {
    "current_page": 1,
    "last_page": 5
  }
}
```

Paginate by incrementing `page` until `current_page >= last_page`.

Chapter URL construction: `/comic/{manga_slug}/{hid}-chapter-{chap}-{lang}`

#### Page List (Images)

```
GET /comic/{manga_slug}/{chapter_hid}-chapter-{chap}-{lang}  (HTML page)
```

The page data is embedded in a `#sv-data` script element in the HTML.
Parse the HTML, find `#sv-data`, extract its text content, and parse as JSON.

JSON structure:
```json
{
  "chapter": {
    "images": [
      {"url": "https://meo.comick.pictures/..."}
    ]
  }
}
```

Image URLs are direct -- no descrambling or special handling needed.

### Ruby Implementation Notes

- This is the most straightforward source to port since it uses a clean JSON API
- Main challenge is CloudFlare; ensure `Referer` header is set
- Series details and page list require HTML parsing to extract embedded JSON from script tags
- Use `Nokogiri::HTML(body).at_css("#comic-data")&.text` to extract embedded JSON
- Date format: `yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'` (ISO 8601 with microseconds)
- Pagination uses cursor-based approach for search, page numbers for chapters

---

## 2. MangaKakalot / Manganato

### Overview

| Property | Value |
|----------|-------|
| **Source type** | Hybrid (JSON API for chapters, HTML for series/search, JS arrays for pages) |
| **Difficulty** | Medium |
| **Priority** | 2 |
| **keiyoushi class** | `src/en/mangakakalot/.../Mangakakalot.kt` extends `lib-multisrc/mangabox/MangaBox.kt` |

### Base URLs and Domain History

- **Current primary domain:** `https://www.mangakakalot.gg`
- **Mirror domains:** `https://www.mangakakalove.com`
- **Legacy domains (no longer active):**
  - `mangakakalot.com` (2018-2021)
  - `manganelo.com`
  - `readmanganato.com`
  - `chapmanganato.to`
  - `manganato.com`
- **Related current domains:** `nelomanga.com`, `natomanga.com`, `manganato.gg`

The site has undergone many domain changes. The current `.gg` domain has been stable since 2024.

### Authentication and Anti-Scraping

- **CloudFlare:** Yes, uses CloudFlare client
- **Required headers:** `Referer: {base_url}/` is required
- **Rate limiting:** 400-500ms delay recommended
- **CDN fallback:** The site uses multiple CDN servers for images. If one CDN fails,
  try alternative CDNs discovered from the page's JavaScript variables.

### Key Endpoints

#### Search

```
GET /search/story/{normalized_query}?page={page}
```

The query must be "normalized" using MangaBox's `change_alias` function:
1. Lowercase the query
2. Replace Vietnamese diacritical characters with ASCII equivalents
3. Replace all special characters (`!@%^*()+=<>?/,.:;'"&#[]~-$_` and spaces) with `_`
4. Collapse multiple underscores
5. Strip leading/trailing underscores

**Selector:** `.panel_story_list .story_item, div.list-truyen-item-wrap, div.list-comic-item-wrap`

Each element contains:
- Link: `h3 a` with `href` (series URL) and text (title)
- Thumbnail: `img` with `src`

Pagination: `a.page_select + a:not(.page_last), a.page-select + a:not(.page-last)`

#### Alternative: Genre-based Browse

```
GET /genre/{genre}?page={page}&type={latest|newest|topview}&state={all|completed|ongoing|drop}
```

#### Popular

```
GET /manga-list/hot-manga?page={page}
```

**Selector:** `div.truyen-list > div.list-truyen-item-wrap, div.comic-list > .list-comic-item-wrap`

#### Latest

```
GET /manga-list/latest-manga?page={page}
```

Same selector as popular.

#### Series Details

```
GET /manga/{slug}
```

or the full URL from search results.

Parse HTML:
- **Main selector:** `div.manga-info-top, div.panel-story-info`
- **Title:** `h1` or `h2` inside main selector
- **Author:** `li:contains(author) a` or `td:containsOwn(author) + td a`
- **Status:** `li:contains(status)` or `td:containsOwn(status) + td`
- **Genres:** `div.manga-info-top li:contains(genres) a` or `td:containsOwn(genres) + td a`
- **Description:** `div#noidungm, div#panel-story-info-description, div#contentBox` (use `ownText`)
- **Thumbnail:** `div.manga-info-pic img, span.info-image img`
- **Alt names:** `.story-alternative` or `tr:has(.info-alternative) h2`

#### Chapter List (JSON API)

```
GET /api/manga/{slug}/chapters?limit=1000&offset=0
```

Response:
```json
{
  "data": {
    "chapters": [
      {
        "chapter_name": "Chapter 1094: Five Elders",
        "chapter_slug": "chapter-1094",
        "chapter_num": 1094.0,
        "updated_at": "2024-01-15T12:00:00.000000Z"
      }
    ],
    "pagination": {
      "has_more": true
    }
  }
}
```

If `has_more` is true, increment offset by the limit and fetch again.

Chapter page URL: `/manga/{slug}/{chapter_slug}`

#### Page List (JavaScript Extraction)

```
GET /manga/{manga_slug}/{chapter_slug}
```

Parse the HTML and extract JavaScript variables from `<script>` tags:

```javascript
var cdns = ["https://cdn1.example.com", "https://cdn2.example.com"];
var backupImage = ["https://backup.example.com"];
var chapterImages = ["/path/to/image1.jpg", "/path/to/image2.jpg"];
```

Extract these arrays using regex:
```ruby
content = doc.css("script:contains('cdns =')").map(&:text).join("\n")
cdns = extract_js_array(content, "cdns") + extract_js_array(content, "backupImage")
images = extract_js_array(content, "chapterImages")
```

Construct image URLs: `{cdn_url}/{image_path}`

**Fallback:** If no JS arrays found, fall back to: `div.container-chapter-reader > img[src]`

### Ruby Implementation Notes

- The query normalization function is critical -- implement the Vietnamese diacritical replacement
- Chapter listing uses a JSON API (easy), but page listing requires JS variable extraction (trickier)
- Multiple CDN URLs may be available; use the first one, fall back to others on failure
- Images require the Referer header to download
- Date format: ISO 8601 with microseconds

---

## 3. MangaFire

### Overview

| Property | Value |
|----------|-------|
| **Source type** | HTML scraping + AJAX API + image descrambling |
| **Difficulty** | HARD (requires WebView/browser for VRF tokens + image descrambling) |
| **Priority** | 3 |
| **keiyoushi class** | `src/all/mangafire/.../MangaFire.kt` + `ImageInterceptor.kt` + `WebViewHelper.kt` |

### WARNING: Significant Anti-Scraping

MangaFire is the **hardest source to port** due to two major obstacles:

1. **VRF Token Requirement:** Search and page list requests require a `vrf` parameter that is
   generated client-side by JavaScript. The keiyoushi extension uses an Android WebView to
   execute the site's JS and capture the generated VRF token. In a Ruby server-side adapter,
   this would require a headless browser (Selenium, Playwright, Ferrum, etc.).

2. **Image Scrambling:** Page images are scrambled (tile-shuffled) and must be descrambled
   client-side. The offset value determines the shuffle pattern. This requires image
   processing (e.g., with MiniMagick or ImageProcessing gem).

**Recommendation:** Defer this source or implement it last. The complexity is significantly
higher than all other sources. Consider whether the catalog overlap with other sources
justifies the engineering effort.

### Base URL

- **Current:** `https://mangafire.to`
- **CDN for scripts:** `mfcdn.cc`

### Authentication and Anti-Scraping

- **CloudFlare:** Yes, aggressive CloudFlare protection
- **VRF tokens:** Required for search and page list API calls
- **Image scrambling:** Images are tile-shuffled with a per-chapter offset
- **SSL:** Uses a custom SSL configuration (accepts all certificates)
- **Rate limiting:** Strict; HTTP 429 errors common. 2 requests per 7 seconds.

### Key Endpoints

#### Search / Browse / Filter

```
GET /filter?keyword={query}&language[]={lang}&page={page}&sort={sort}&vrf={vrf_token}
```

Filters available: type, genre, genre_mode, status, year_range, min_chapters, sort.

Sort options: `most_viewed`, `recently_updated`, `newest`, `oldest`, `title_az`, `title_za`.

**VRF token:** Generated by JavaScript at `mangafire.to/assets/t1/min/all.js`. The keiyoushi
extension spawns a WebView, navigates to `/home`, and injects JS to trigger a search which
generates an AJAX request to `/ajax/manga/search?...&vrf={token}`. The VRF is captured from
that intercepted request.

**Selector:** `.original.card-lg .unit .inner`
- Title: `.info > a` (text + href)
- Thumbnail: `img[src]`

Pagination: `.page-item.active + .page-item .page-link`

#### Series Details

```
GET /manga/{slug}.{id}  (HTML page)
```

Parse HTML:
- **Container:** `.main-inner:not(.manga-bottom)`
- **Title:** `h1`
- **Thumbnail:** `.poster img[src]`
- **Status:** `.info > p` text (releasing, completed, on_hiatus, discontinued)
- **Synopsis:** `#synopsis .modal-content` text nodes
- **Alt title:** `h6`
- **Author:** `.meta span:contains(Author:) + span`
- **Type:** `.meta span:contains(Type:) + span`
- **Genres:** `.meta span:contains(Genres:) + span`

Status mapping: "releasing"=ongoing, "completed"=publishing_finished,
"on_hiatus"=hiatus, "discontinued"=cancelled.

#### Chapter List (AJAX)

```
GET /ajax/manga/{manga_id}/chapter/{lang}
```

Where `manga_id` is the numeric ID extracted from the URL (the part after the last `.`).

Response: JSON with `result` containing HTML string.

Parse the HTML fragment:
- Chapters in `li` elements
- Each has `data-number` attribute (chapter number)
- Link: `a[href]`
- Title: first `span` text
- Date: second `span` text (format: "MMM dd, yyyy")

#### Page List (AJAX + VRF)

**This is the hardest part.** Requires:

1. Load the chapter page in a WebView/headless browser
2. The page's JavaScript makes an AJAX call to `/ajax/read/chapter/{chapter_id}?...&vrf={token}`
3. Intercept that request to get the VRF token
4. Make the AJAX call server-side with the captured VRF

Response:
```json
{
  "result": {
    "images": [
      ["https://image-url.jpg", 800, 5]
    ]
  }
}
```

Each image array: `[url, width, offset]`. If `offset > 0`, the image is scrambled.

#### Image Descrambling Algorithm

The images are tile-shuffled. The algorithm from `ImageInterceptor.kt`:

```
PIECE_SIZE = 200
MIN_SPLIT_COUNT = 5

pieceWidth = min(PIECE_SIZE, ceil(imageWidth / MIN_SPLIT_COUNT))
pieceHeight = min(PIECE_SIZE, ceil(imageHeight / MIN_SPLIT_COUNT))
xMax = ceil(imageWidth / pieceWidth) - 1
yMax = ceil(imageHeight / pieceHeight) - 1

For each tile (x, y):
  if x == xMax: xSrc = x  (margin tile, no shuffle)
  else: xSrc = (xMax - x + offset) % xMax

  if y == yMax: ySrc = y  (margin tile, no shuffle)
  else: ySrc = (yMax - y + offset) % yMax

  Copy tile from (xSrc * pieceWidth, ySrc * pieceHeight)
       to (x * pieceWidth, y * pieceHeight)
```

### Ruby Implementation Notes

- **VRF tokens** are the biggest blocker. Options:
  - Use a headless browser gem (Ferrum/Playwright) to execute JS and capture tokens
  - Reverse-engineer the VRF generation algorithm from the JS bundle
  - Cache VRF tokens and refresh periodically
- **Image descrambling** can be done with MiniMagick or Vips:
  - Download the scrambled image
  - Create a new canvas
  - Copy tiles from source positions to destination positions
  - Save the descrambled image
- Consider adding a `descramble_images: true` flag to the adapter config
- The SSL certificate bypass in keiyoushi suggests the CDN sometimes has cert issues

---

## 4. TCBScans

### Overview

| Property | Value |
|----------|-------|
| **Source type** | HTML scraping (simple) |
| **Difficulty** | Easy |
| **Priority** | 4 |
| **keiyoushi class** | `src/en/tcbscans/.../TCBScans.kt` |

### Base URLs and Domain History

- **Current primary:** `https://tcbonepiecechapters.com`
- **Historical/alternates:**
  - `tcbscans.com`
  - `tcbscans.me` (redirects to primary)
  - `tcbscans3.com`
  - `tcbscansonepiecechapters.com`
  - `tcbscansonepiece.com`
- **Domain changes frequently** due to legal pressure

**Important:** As of early 2025, TCBScans may have narrowed their catalog to primarily One Piece
and a few other Jump series. Verify current catalog before implementing.

### Authentication and Anti-Scraping

- **CloudFlare:** Yes, uses CloudFlare client
- **No special tokens** or encryption needed
- **Latest updates not supported** -- only a project list

### Key Endpoints

#### Project List (acts as both Popular and Search)

```
GET /projects
```

**Selector:** `div.bg-card`

Each card contains:
- Link: `a[href].text-white` with series URL and title text
- Thumbnail: `img[src]`

**Search:** TCBScans does not have a search endpoint. The keiyoushi extension fetches
all projects and filters client-side:
```ruby
all_projects.select { |p| p.title.downcase.include?(query.downcase) }
```

**No pagination** -- all projects on one page (small catalog).

#### Series Details

```
GET /mangas/{slug}  or  GET /{series_path}
```

Parse HTML:
- **Container:** `div.order-1`
- **Title:** `h1`
- **Thumbnail:** `img[src]` inside container
- **Description:** `p` inside container

Note: The URL format changed in Feb 2025 from `/mangas/{id}/{slug}` to just `/{slug}`.

#### Chapter List

On the same series detail page.

**Selector:** `div.grid a`

Each element contains:
- Link: `a[href]` with chapter URL
- Title: `div.font-bold:not(.flex)` text
- Description: `.text-gray-500` text (may be blank)
- Chapter number: extracted via regex `\d+.?\d+$` from the title

Chapter name construction:
```ruby
chap_number = title.match(/(\d+\.?\d+)$/)&.[](1)
if chap_number
  name = "Chapter #{chap_number}"
  name += ": #{description}" if description.present?
end
```

#### Page List

```
GET /chapters/{id}/{slug}  or  GET /{chapter_path}
```

**Selector:** `picture img, .image-container img`

Image URLs are direct `img[src]` -- no descrambling needed.

### Ruby Implementation Notes

- This is the simplest source to implement -- small catalog, no API, no encryption
- The main risk is frequent domain changes; make `base_url` easily configurable
- No browse support needed (too small a catalog)
- `supports_browse?` can return `false`; search just filters the project list
- Consider caching the project list since it's small and changes infrequently

---

## 5. FlameComics (Flame Scans)

### Overview

| Property | Value |
|----------|-------|
| **Source type** | Next.js JSON API (via `_next/data/{buildId}/...`) |
| **Difficulty** | Medium |
| **Priority** | 5 |
| **keiyoushi class** | `src/en/flamecomics/.../FlameComics.kt` + `FlameComicsDto.kt` |

### Base URLs

- **Site:** `https://flamecomics.xyz`
- **CDN:** `https://cdn.flamecomics.xyz`
- **Historical:** Previously known as FlameScans / Luminous Scans

### Authentication and Anti-Scraping

- **CloudFlare:** Yes, uses CloudFlare client
- **Rate limiting:** Strict -- 2 requests per 7 seconds enforced in keiyoushi
- **Dynamic Build ID:** The site is a Next.js app. API requests go through
  `/_next/data/{buildId}/...` and the `buildId` changes on every deployment.
  Must be fetched dynamically.
- **Composed images:** Some pages are split into multiple images that must be stitched together
  (indicated by a `?comp` suffix in the URL)

### Key Concepts

#### Build ID

The Build ID is embedded in the HTML of any page inside `<script id="__NEXT_DATA__">`:

```json
{"buildId": "abc123def456", ...}
```

You must:
1. Fetch any page (e.g., the homepage)
2. Parse out `__NEXT_DATA__` JSON
3. Extract `buildId`
4. Use it in all subsequent API calls

If a request returns 404 with `text/html`, the build ID is stale. Re-fetch it from the
404 page's `__NEXT_DATA__` and retry.

#### API Request Pattern

All data API requests follow this pattern:
```
GET /_next/data/{buildId}/{path}.json?{params}
```

### Key Endpoints

#### Browse / Search

```
GET /_next/data/{buildId}/browse.json
```

Response:
```json
{
  "pageProps": {
    "series": [
      {
        "title": "Solo Leveling",
        "altTitles": ["Na Honjaman Level-Up"],
        "description": "...",
        "cover": "cover-filename.jpg",
        "type": "Manhwa",
        "tags": ["Action", "Fantasy"],
        "author": ["Chugong"],
        "artist": ["Dubu"],
        "status": "Completed",
        "series_id": 42,
        "last_edit": 1705334400,
        "views": 50000
      }
    ]
  }
}
```

**Search:** Client-side filtering. The keiyoushi extension downloads the full series list
and filters by title (case-insensitive, special chars removed):
```ruby
query_normalized = query.downcase.gsub(/[^a-z0-9 ]/, "")
series.select do |s|
  titles = [s["title"]] + (s["altTitles"] || [])
  titles.any? { |t| t.downcase.gsub(/[^a-z0-9 ]/, "").include?(query_normalized) }
end
```

**Popular sort:** Sort by `views` descending.

**Pagination:** Client-side. Page through the full list with a page size of 20.

#### Latest Updates

```
GET /_next/data/{buildId}/index.json
```

Response:
```json
{
  "pageProps": {
    "latestEntries": {
      "blocks": [
        {
          "series": [
            {
              "title": "...",
              "series_id": 42,
              "cover": "cover.jpg",
              "last_edit": 1705334400
            }
          ]
        }
      ]
    }
  }
}
```

#### Series Details + Chapter List

Both come from the same endpoint:

```
GET /_next/data/{buildId}/series/{series_id}.json?id={series_id}
```

Response (series data):
```json
{
  "pageProps": {
    "series": {
      "title": "Solo Leveling",
      "description": "<p>HTML description</p>",
      "cover": "cover.jpg",
      "type": "Manhwa",
      "tags": ["Action"],
      "author": ["Chugong"],
      "artist": ["Dubu"],
      "status": "Ongoing"
    }
  }
}
```

Response (chapter data -- same endpoint):
```json
{
  "pageProps": {
    "chapters": [
      {
        "chapter": 179.0,
        "title": "The Final Battle",
        "release_date": 1705334400,
        "series_id": 42,
        "token": "abc123"
      }
    ]
  }
}
```

Status mapping: "ongoing"=ongoing, "completed"=completed, "hiatus"=hiatus, "dropped"=cancelled.

**Thumbnail URL:** `https://cdn.flamecomics.xyz/uploads/images/series/{series_id}/{cover}?{last_edit}`

**Chapter URL:** `/series/{series_id}/{token}`

#### Page List

```
GET /_next/data/{buildId}/series/{series_id}/{token}.json?id={series_id}&token={token}
```

Response:
```json
{
  "pageProps": {
    "chapter": {
      "release_date": 1705334400,
      "series_id": 42,
      "token": "abc123",
      "images": {
        "0": {"name": "001.webp"},
        "1": {"name": "002.webp"},
        "2": {"name": "003.webp"}
      }
    }
  }
}
```

Note: `images` is a **map** (object with string keys), not an array. Sort by key numerically.

**Image URL:** `https://cdn.flamecomics.xyz/uploads/images/series/{series_id}/{token}/{page_name}?{release_date}`

#### Composed Images

Some pages may have URLs ending in `?comp`. These are actually multiple image URLs separated
by `|` (URL-encoded as `%7C`). They must be fetched individually and stitched side-by-side
horizontally.

### Ruby Implementation Notes

- **Build ID management** is the main complexity. Implement a class-level cache with staleness
  detection (re-fetch on 404).
- The `images` field in page list is a map, not an array. Use `images.sort_by { |k, _| k.to_i }`
  to get ordered pages.
- Composed images (`?comp`) can be handled with MiniMagick or Vips if needed, but may be rare.
  Could also be deferred and handled at the download layer.
- `release_date` in chapter data is a Unix timestamp in **seconds** (multiply by 1000 for
  milliseconds if needed).
- Rate limiting is strict: 2 requests per 7 seconds minimum.
- The site description may contain HTML; strip tags with `Nokogiri::HTML.fragment(desc).text`.

---

## New Adapter Scaffold Template

Use this as a starting point when creating a new adapter:

```ruby
# frozen_string_literal: true

require "json"
require "nokogiri"

# {SourceName} adapter
# Reference: https://github.com/keiyoushi/extensions-source/tree/main/src/en/{source_dir}
module SourceName
  class Adapter < ::BaseAdapter
    BASE_URL = "https://example.com"

    def supports_browse?
      false  # Set to true if browse is supported
    end

    def search(query)
      # TODO: Implement search
      # Return: Array<ResultTypes::SearchResult>
      []
    end

    def series(id_or_url)
      # TODO: Implement series details
      # Return: ResultTypes::Series
      url = normalize_url(id_or_url)
      response = http.get(url)
      return nil unless response.status == 200

      # Parse response...
      nil
    end

    def chapters(series_url)
      # TODO: Implement chapter listing
      # Return: Array<ResultTypes::Chapter>
      []
    end

    def pages(chapter_url)
      # TODO: Implement page listing
      # Return: Array<ResultTypes::Page>
      []
    end

    private

    def normalize_url(id_or_url)
      if id_or_url.start_with?("http")
        id_or_url
      elsif id_or_url.include?("/")
        "#{BASE_URL}/#{id_or_url}"
      else
        "#{BASE_URL}/manga/#{id_or_url}"
      end
    end

    def detect_series_type(tags)
      tags_lower = (tags || []).map(&:downcase)
      return "manhwa" if tags_lower.any? { |t| t.include?("manhwa") || t.include?("korean") }
      return "manhua" if tags_lower.any? { |t| t.include?("manhua") || t.include?("chinese") }
      "manga"
    end
  end
end

# Register with legacy namespace
module Scrapers
  module SourceName
    Adapter = ::SourceName::Adapter
  end
end
```

And the corresponding `config/sources.yml` entry:

```yaml
source_name:
  base_url: "https://example.com"
  delay_ms: 400
  open_timeout: 10
  read_timeout: 20
  max_retries: 2
  headers:
    User-Agent: "ScanarrScraper/0.1"
    Referer: "https://example.com/"
```

---

## Common Patterns and Tips

### 1. API-based vs HTML Scraping

| Source | Type | Complexity |
|--------|------|------------|
| ComicK | JSON API + embedded JSON in HTML | Easy-Medium |
| MangaKakalot | JSON API (chapters) + HTML + JS arrays (pages) | Medium |
| MangaFire | HTML + AJAX + VRF tokens + image descrambling | Hard |
| TCBScans | Pure HTML scraping | Easy |
| FlameComics | Next.js JSON API | Medium |

### 2. CloudFlare Handling

All five sources use CloudFlare. The `HttpClient` with proper `User-Agent` and `Referer`
headers handles most cases. If a source starts aggressively blocking:

- Add `Referer: {base_url}/` to headers
- Use a realistic `User-Agent`
- Respect rate limits (increase `delay_ms`)
- Consider adding proxy support via `proxy_url` config

### 3. Domain Changes

Manga sites change domains frequently. Best practices:

- Use `config["base_url"]` from `sources.yml` rather than hardcoded constants
- The `BASE_URL` constant is just a default/fallback
- Log warnings when redirects are detected
- Document known domain history in comments

### 4. Error Handling Conventions

Follow the existing pattern from other adapters:

```ruby
def search(query)
  # ... implementation ...
rescue StandardError => e
  Rails.logger.error "[SourceName] Search error: #{e.message}"
  []
end

def series(id_or_url)
  # ... implementation ...
rescue StandardError => e
  Rails.logger.error "[SourceName] Series error: #{e.message}"
  nil
end
```

For specific error types, raise the appropriate `BaseAdapter` error:
- `ChapterNotFoundError` -- chapter no longer available
- `SeriesNotFoundError` -- series not found
- `RateLimitError` -- rate limited by source
- `SourceUnavailableError` -- source is down or returning unexpected responses

### 5. Extracting JavaScript Variables

Several sources embed data in JS variables. Common pattern:

```ruby
def extract_js_variable(body, var_name)
  match = body.match(/#{Regexp.escape(var_name)}\s*=\s*(\[.*?\]|\{.*?\});/m)
  return nil unless match
  JSON.parse(match[1])
rescue JSON::ParserError
  nil
end
```

### 6. Date Parsing

Different sources use different date formats:

```ruby
# ISO 8601 (ComicK, MangaKakalot)
Time.parse("2024-01-15T12:00:00.000000Z")

# Human-readable (MangaFire)
Date.strptime("Jan 15, 2024", "%b %d, %Y")

# Unix timestamp in seconds (FlameComics)
Time.at(1705334400)

# Relative dates ("3 hours ago", "2 days ago") -- handle if needed
```

### 7. Recommended Implementation Order

1. **TCBScans** -- Simplest, good warm-up exercise
2. **ComicK** -- Clean API, high value, moderate complexity
3. **FlameComics** -- Next.js API pattern, medium complexity
4. **MangaKakalot** -- Hybrid approach, JS extraction needed
5. **MangaFire** -- Defer unless critical; VRF tokens and image descrambling are significant hurdles

### 8. Testing Strategy

For each adapter, test:
1. `search("one piece")` returns results with valid URLs and cover images
2. `series(url)` returns complete metadata (title, author, status, tags)
3. `chapters(url)` returns ordered chapter list with proper numbering
4. `pages(url)` returns image URLs that are accessible (200 status)
5. Edge cases: series with decimals (Chapter 1.5), volumes, no chapters, locked content
