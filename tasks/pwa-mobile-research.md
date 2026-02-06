# PWA & Mobile Reading Research for Scanarr

> Research document. No implementation code. Last updated: 2026-02-06.

---

## Table of Contents

1. [Mihon UX Audit](#1-mihon-ux-audit)
2. [Technical PWA Implementation Plan for Rails 8](#2-technical-pwa-implementation-plan-for-rails-8)
3. [Mobile Reader Improvements](#3-mobile-reader-improvements)
4. [Offline Reading Strategy](#4-offline-reading-strategy)
5. [Mobile Navigation Overhaul](#5-mobile-navigation-overhaul)
6. [Recommended Implementation Phases](#6-recommended-implementation-phases)
7. [Libraries & Tools](#7-libraries--tools)
8. [Sources & References](#8-sources--references)

---

## 1. Mihon UX Audit

### 1.1 App Navigation Structure

Mihon uses a **5-tab bottom navigation bar** on phones and a **side rail** on tablets:

| Tab | Purpose | Scanarr Equivalent |
|---|---|---|
| **Library** | User's manga collection (default landing) | `/library` |
| **Updates** | New chapter notifications | `/calendar` + notifications |
| **History** | Reading history with timestamps | `/history` |
| **Browse** | Source discovery, extensions, migrations | `/` (Sources) |
| **More** | Settings, downloads, categories, about | Admin section |

**Key navigation patterns:**
- Re-tapping the active tab scrolls to top / resets state
- Back button from any tab returns to Library
- Tab badges show unread update count and extension update count
- Tablet mode uses `NavigationRail` (vertical side tabs) instead of bottom bar
- Tab transitions use material fade-through animations

**Mapping to Scanarr:** Scanarr currently has a desktop sidebar with: Sources, Library, Calendar, Search, Stats, History, Downloads, Jobs, Scrapers, Design System. On mobile, this collapses to a hamburger menu dialog. The Mihon model suggests promoting the 4 most-used items (Library, Browse/Sources, History, More) to a persistent bottom tab bar on mobile.

### 1.2 Reader UX

#### 1.2.1 Reading Modes

Mihon supports 6 reading modes (Scanarr currently supports 4):

| Mihon Mode | Viewer Type | Direction | Scanarr Status |
|---|---|---|---|
| Left-to-Right | Pager (page-by-page) | Horizontal | Supported |
| Right-to-Left | Pager (page-by-page) | Horizontal | Supported |
| Vertical | Pager (page-by-page) | Vertical | Not supported (distinct from long strip) |
| Webtoon | Continuous scroll | Vertical | Supported ("Long Strip") |
| Continuous Vertical | Continuous scroll | Vertical | Supported ("Webcomic") |
| Default | Per-series override | N/A | Not supported |

**Gap analysis:** Scanarr is missing (a) a vertical pager mode (page-by-page with vertical flip, not continuous scroll) and (b) per-series default reading mode that overrides the global default.

#### 1.2.2 Tap Zone Navigation

This is the biggest UX gap between Scanarr and Mihon. Mihon implements 5 configurable tap zone layouts for page navigation. When reading, tapping different screen regions triggers prev/next/menu without any visible buttons.

**Kindle-style (most popular):**
```
+---------------------------+
|          MENU (top 33%)   |
+--------+------------------+
| PREV   |                  |
| (left  |   NEXT           |
|  33%)  |   (right 67%)    |
+--------+------------------+
```

**Right-and-Left:**
```
+--------+--------+--------+
|        |        |        |
| PREV   |  MENU  |  NEXT  |
| (33%)  | (34%)  | (33%)  |
|        |        |        |
+--------+--------+--------+
```

**L-Shaped:**
```
+---------------------------+
|      PREV (top 33%)       |
+--------+--------+---------+
| PREV   |  MENU  |  NEXT  |
| (33%)  | (34%)  | (33%)  |
+--------+--------+---------+
|      NEXT (bottom 33%)    |
+---------------------------+
```

**Edge Navigation:**
```
+--------+--------+--------+
| NEXT   |        | NEXT   |
| (left  |  MENU  | (right |
|  33%)  | (34%)  |  34%)  |
+--------+--+-----+--------+
             | PREV (center|
             | bottom 33%) |
             +-------------+
```

**Additional features:**
- All modes reserve the **top 5% of screen as a constant menu region** (always accessible)
- **Tapping inversion** — can flip horizontal/vertical tap zones for different reading directions
- **Disabled navigation** — option to turn off tap zones entirely
- RTL mode automatically mirrors tap zones

**Scanarr gap:** Currently, Scanarr has no tap-zone navigation. The reader relies on keyboard navigation, visible buttons, and scroll. Adding configurable tap zones (even just the Kindle-style default) would dramatically improve the mobile reading experience.

#### 1.2.3 Reader Toolbar/Overlay

Mihon's reader toolbar appears/hides on tap (center of screen) and contains:
- **Top bar:** Chapter title, series name, back button
- **Bottom bar:** Page slider, reading mode selector, settings button
- **Page indicator:** Small floating indicator showing current page/total
- The toolbar auto-hides after a delay, then the reader goes fullscreen

**Scanarr gap:** Scanarr's reader has a sticky progress bar at top and navigation buttons above the viewport. These are always visible and take up screen real estate. The Mihon model of hide-on-read, show-on-tap is much better for mobile.

#### 1.2.4 Reader Preferences (Per-Series + Global)

Mihon allows both global defaults and per-series overrides for:

| Setting | Mihon | Scanarr |
|---|---|---|
| Reading mode | Global default + per-series | Per-session only (URL param) |
| Orientation lock | 7 modes (free, portrait, landscape, locked variants) | None |
| Image scaling | 6 modes (fit screen/width/height, stretch, original, smart) | CSS-based (max-height constraint) |
| Zoom | Double-tap zoom with configurable speed | None (lightbox only) |
| Keep screen on | Toggle | None |
| Page transitions | Enable/disable animation | CSS snap (horizontal mode) |
| Crop borders | Auto-remove white space | None |
| Navigate to pan | Scroll large images before advancing page | None |
| Color filter | Tint overlay, grayscale, inverted colors | None |
| Custom brightness | -75 to 100 with overlay | None |
| Webtoon side padding | 0-25 configurable padding | None |

**Priority for Scanarr:** Keep screen on (Wake Lock API), per-series reading mode (store in DB), pinch-to-zoom, and fullscreen mode are the highest-impact additions.

#### 1.2.5 Chapter Transitions

Mihon shows a transition card between chapters with:
- "Finished: [Chapter Title]" header
- "Next: [Chapter Title]" with chapter info
- Missing chapters warning if there are gaps
- Auto-load of next chapter on scroll past transition

**Scanarr comparison:** Scanarr already has a "Continue Reading?" overlay with auto-advance countdown (5s). This is functionally similar but could be improved by showing missing chapter warnings and making the transition feel more seamless (inline rather than full-screen overlay).

#### 1.2.6 Page Preloading

Mihon preloads:
- Adjacent pages in the current chapter (pager mode preloads 2-3 ahead)
- The next/previous chapter in the background via `requestPreloadChapter()`
- Uses a `SubsamplingImageView` for efficient rendering of large manga images

**Scanarr comparison:** Scanarr uses native `loading="lazy"` on images (eager for first 3). No explicit JavaScript preloading of upcoming pages or next chapter preloading.

### 1.3 Library UX

Mihon's library features worth emulating:
- **Grid view with covers** as primary view (Scanarr already has this)
- **Category tabs** for organizing manga into custom groups
- **Compact grid** option (smaller covers, more per row)
- **List view** alternative with title + cover thumbnail
- **Long-press for multi-select** with batch operations
- **Quick search/filter** within library
- **Unread badge** on cover showing number of unread chapters
- **Download badge** showing download status

**Scanarr comparison:** Scanarr's library already has grid view, search, status filters (Downloaded/In Progress/Not Downloaded/Following), and download progress badges. Missing: category tabs, list view toggle, compact grid, unread chapter badges, long-press multi-select.

### 1.4 Download/Offline UX

Mihon's download features:
- **Download queue** with pause/resume per item
- **Download chapters individually or by range** (download next 5, download all unread)
- **Automatic download of new chapters** for followed series
- **Storage management** per-series and global
- **Download badges** visible on library covers

**Scanarr comparison:** Scanarr already has downloads (individual chapter, bulk download, queue via SolidQueue), cancel/restart, and download progress on library covers. The main gap for PWA is making these downloads available offline in the browser via service worker caching.

---

## 2. Technical PWA Implementation Plan for Rails 8

### 2.1 Rails 8 Built-in PWA Support

Rails 8 ships with PWA scaffolding out of the box:

**File structure:**
```
app/views/pwa/
  manifest.json.erb    # Web app manifest (dynamic with ERB)
  service-worker.js.erb # Service worker (dynamic with ERB)
```

**Route configuration** (add to `config/routes.rb`):
```ruby
# These are commented out by default in Rails 8, uncomment to enable:
get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
```

**Head tags** (add to `application.html.erb`):
```html
<link rel="manifest" href="/manifest.json">
<meta name="theme-color" content="#0a0a0a"> <!-- bg-background -->
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="apple-touch-icon" href="/icon-192.png">
```

**Scanarr is Rails 8.1.2** and does not currently have these files. They need to be created.

### 2.2 Web App Manifest

The manifest controls how Scanarr appears when installed:

```json
{
  "name": "Scanarr",
  "short_name": "Scanarr",
  "description": "Self-hosted manga library and reader",
  "start_url": "/library",
  "scope": "/",
  "display": "standalone",
  "orientation": "any",
  "theme_color": "#0a0a0a",
  "background_color": "#0a0a0a",
  "icons": [
    { "src": "/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ],
  "screenshots": [],
  "categories": ["entertainment", "books"]
}
```

**Key decisions:**
- `start_url: "/library"` — Library is the "home" screen for returning users (matches Mihon)
- `display: "standalone"` — Removes browser chrome for app-like feel
- `orientation: "any"` — Allow rotation, let the reader lock orientation per-series
- `theme_color` and `background_color` should match the dark theme (`#0a0a0a`)
- Need 3 icon sizes: 192px, 512px, and a maskable 512px variant

### 2.3 Service Worker Strategy

The service worker is the core of PWA functionality. The strategy should be layered:

**Layer 1: App Shell (Cache-First)**
Cache the structural assets that make up the UI:
- CSS bundle (`application.css`)
- JS bundle (`application.js`)
- Font files (Geist from Google Fonts)
- App icons and static images

These change rarely and can be served from cache instantly, with updates happening in the background on the next visit.

**Layer 2: HTML Pages (Network-First with Offline Fallback)**
For Turbo Drive navigations:
- Try network first (with 3-second timeout)
- Fall back to cached version if offline
- Cache each visited page for offline access
- Show a custom offline page if no cached version exists

**Layer 3: Manga Page Images (Cache-First for Downloaded, Network-First for Streaming)**
- Images from locally downloaded chapters (served from Rails ActiveStorage): **Cache-First** — these won't change
- Images from remote sources (streaming): **Network-First** — cache on visit for offline reading of previously viewed pages
- Preload next 2-3 pages ahead of current reading position

**Layer 4: API Responses (Network-First)**
- Reading progress PATCH requests: Queue when offline, sync when back online
- Series/chapter data: Network-first with cache fallback

### 2.4 Hotwire + Service Worker Compatibility

**Turbo Drive considerations:**
- Turbo Drive uses `fetch()` for navigation, which the service worker intercepts naturally
- The `Accept: text/vnd.turbo-stream.html` header distinguishes Turbo Stream requests from full page loads — the service worker should NOT cache Turbo Stream responses (they are partial updates)
- Turbo's preview cache (`data-turbo-cache`) works alongside service worker caching — they serve different purposes (Turbo cache is in-memory for instant back button, service worker cache is persistent for offline)
- Turbo Drive's `data-turbo-preload` attribute can be used alongside service worker prefetching

**Turbo Frames:**
- Frame requests use `Turbo-Frame` header — the service worker should pass these through to network (they are partial page updates, not cacheable app shell)

**Turbo Streams (WebSocket/SSE):**
- Action Cable broadcasts (used for download progress updates) do NOT go through the service worker
- These will simply not work offline, which is acceptable — downloads are a server-side operation

**Upcoming: `@hotwired/turbo/offline`:**
- Turbo has an [open PR #1427](https://github.com/hotwired/turbo/pull/1427) adding official offline support
- Provides `addRule()` with configurable caching strategies (cache-first, network-first, stale-while-revalidate)
- When merged, this would be the preferred approach over a hand-rolled service worker
- **Current status: Unmerged** as of Feb 2026 — plan to use a manual service worker first, migrate when the Turbo offline bundle ships

**Service worker registration** (add to `app/javascript/application.ts`):
```typescript
// Register service worker for PWA
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js", { scope: "/" })
}
```

### 2.5 Install Prompt (Add to Home Screen)

The browser shows the install prompt automatically when:
1. The app has a valid manifest
2. A service worker is registered with a fetch handler
3. The app is served over HTTPS
4. The user has engaged with the app sufficiently

**Custom install prompt:**
- Capture the `beforeinstallprompt` event
- Show a custom install banner (e.g., "Install Scanarr for offline reading")
- Dismiss after install or after user declines
- Can be a Stimulus controller (`install_prompt_controller.ts`)

**iOS considerations:**
- iOS Safari does not fire `beforeinstallprompt`
- Must use `<meta name="apple-mobile-web-app-capable" content="yes">`
- Users add to home screen manually via Share menu
- Consider showing an instruction banner for iOS users

---

## 3. Mobile Reader Improvements

### 3.1 Tap Zone Navigation

**Implementation approach:** A Stimulus controller (`reader_touch_controller.ts`) that overlays invisible tap zones on the reader viewport.

**Recommended default: Kindle-style layout**
```
Screen divided into 3x3 grid:
- Top row (0-33% Y): MENU (show/hide toolbar)
- Bottom-left (0-33% X, 33-100% Y): PREVIOUS
- Bottom-right (33-100% X, 33-100% Y): NEXT
```

**Technical details:**
- Use `pointer events` (not touch events) for cross-device compatibility
- `event.clientX / window.innerWidth` and `event.clientY / window.innerHeight` give normalized 0-1 coordinates
- Must distinguish tap from swipe/pinch (use a threshold: if pointer moves < 10px and duration < 300ms, it's a tap)
- Tap zones should be configurable (store preference in localStorage, later in user settings)
- Show a one-time overlay visualization (like Mihon) to teach users the tap zones

**RTL handling:** Mirror the left/right zones when reading RTL. Scanarr already tracks `is_rtl` in the reader controller.

### 3.2 Swipe Gestures

**Horizontal swipe for pager modes:**
- Swipe left/right to advance/go back pages
- Scanarr's horizontal mode already uses CSS `snap-x snap-mandatory` which provides native swipe behavior
- Consider adding velocity-based swipe detection for faster page turns

**Vertical swipe in webtoon mode:**
- Already works naturally via scroll
- No additional gesture handling needed

**Swipe-back navigation:**
- Edge swipe (from left 20px of screen) to go back to series page
- Must not conflict with reader page navigation
- iOS Safari already handles this natively in standalone mode

### 3.3 Pinch-to-Zoom

**Current state:** Scanarr has a lightbox for zoomed viewing but no pinch-to-zoom on pages.

**Implementation options:**

| Approach | Pros | Cons |
|---|---|---|
| CSS `touch-action: manipulation` + native zoom | Zero JS, uses browser zoom | Hard to control, affects whole page |
| Pointer Events + CSS transform | Full control, no library needed | Complex to implement well |
| Library (e.g., PinchZoom.js or panzoom) | Battle-tested, handles edge cases | Dependency |

**Recommended approach:** Use the `panzoom` library (12KB gzipped, zero dependencies) on the page image container. Enable only in single-page reading modes (not webtoon/long strip, where vertical scroll must remain natural).

**Key behaviors:**
- Double-tap to zoom to 2x / reset
- Pinch to freely zoom between 1x and 4x
- When zoomed in, pan to see different parts of the page
- "Navigate to pan" setting: when zoomed in, swiping pans first; only advances page when at image edge (Mihon feature)
- Reset zoom when advancing to next page

### 3.4 Fullscreen API

**Implementation:**
```javascript
// Enter fullscreen when opening reader (on user gesture)
document.documentElement.requestFullscreen()

// Exit when leaving reader
document.exitFullscreen()
```

**Considerations:**
- Fullscreen requires a user gesture (can't auto-enter on page load)
- Add a "fullscreen" button to the reader toolbar
- Auto-request fullscreen when user starts reading (first tap/swipe)
- Exit fullscreen on back navigation or Escape
- In standalone PWA mode, the app is already "fullscreen" (no browser chrome), so this is mainly for browser users
- iOS Safari standalone mode is already fullscreen; the Fullscreen API has limited support on iOS

### 3.5 Screen Wake Lock API

Prevent the screen from dimming while reading:

```javascript
// Request wake lock
let wakeLock = await navigator.wakeLock.request("screen")

// Release when leaving reader
wakeLock.release()

// Re-acquire on visibility change (browser wakes from background)
document.addEventListener("visibilitychange", async () => {
  if (document.visibilityState === "visible") {
    wakeLock = await navigator.wakeLock.request("screen")
  }
})
```

**Browser support:** Chrome 84+, Edge 84+, Safari 16.4+, Firefox 126+. Good coverage.

**Implementation:** Add to `reader_controller.ts` — acquire on `connect()`, release on `disconnect()`. Make it a user preference (default: on while reading).

### 3.6 Screen Orientation Lock

Lock orientation per reading mode or per series:

```javascript
// Lock to portrait for manga
screen.orientation.lock("portrait")

// Lock to landscape for double-page spread
screen.orientation.lock("landscape")

// Unlock
screen.orientation.unlock()
```

**Caveats:**
- Only works in fullscreen mode on most browsers
- iOS Safari does not support `screen.orientation.lock()`
- Android Chrome supports it in standalone PWA mode
- Should be a user preference, not forced

**Practical approach:** Offer orientation preference in reader settings. When the user selects portrait/landscape, enter fullscreen and lock. When set to "auto" (default), do nothing.

### 3.7 Page Preloading

**Current state:** Scanarr uses `loading="lazy"` with the first 3 images set to `eager`. This is decent but passive.

**Proposed active preloading strategy:**

1. **Current chapter:** Preload 3 pages ahead of current position using `new Image()`:
   ```javascript
   function preloadPage(url: string) {
     const img = new Image()
     img.src = url
     // Browser caches the decoded image
   }
   ```

2. **Next chapter:** When user reaches page N-3 (3 pages from end), start fetching the next chapter's page URLs via a lightweight JSON endpoint. Then preload the first 3 pages of the next chapter.

3. **Service worker cache:** The preloaded images are automatically cached by the service worker (cache-on-fetch for image responses).

4. **IntersectionObserver with rootMargin:** Extend the intersection observer to trigger preloading before images enter the viewport:
   ```javascript
   new IntersectionObserver(callback, {
     rootMargin: "200% 0px" // Start loading 2 viewports ahead
   })
   ```

### 3.8 Viewport and Safe Area Management

**Prevent accidental zoom:**
```html
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
```
Note: `user-scalable=no` is an accessibility concern. Better to use `touch-action: manipulation` on the reader container, which prevents double-tap-to-zoom but allows pinch-to-zoom.

**Handle notch/safe areas:**
```css
/* Reader container */
.reader-fullscreen {
  padding-top: env(safe-area-inset-top, 0);
  padding-bottom: env(safe-area-inset-bottom, 0);
  padding-left: env(safe-area-inset-left, 0);
  padding-right: env(safe-area-inset-right, 0);
}
```

**Viewport fit:** `viewport-fit=cover` in the meta tag tells the browser to extend the page into the notch area, and `env(safe-area-inset-*)` provides the safe margins.

### 3.9 Reader Toolbar (Show/Hide)

Redesign the reader UI for mobile with a hide-on-read pattern:

**Behavior:**
- On entering the reader, toolbar is visible for 3 seconds then auto-hides
- Tapping the menu zone (center of screen or top 5%) toggles toolbar visibility
- Toolbar slides in/out with animation (translate + opacity)
- When toolbar is hidden, reader goes immersive (no UI chrome)

**Toolbar contents (mobile):**
- **Top bar:** Back button, series title (truncated), chapter number
- **Bottom bar:** Page slider (range input), reading mode icon, settings gear, fullscreen toggle
- **Floating indicator:** Small "3/24" page counter, always visible, semi-transparent

---

## 4. Offline Reading Strategy

### 4.1 Architecture Overview

```
+------------------+     +-------------------+     +------------------+
| Rails Server     |     | Service Worker    |     | Browser Storage  |
| (ActiveStorage)  |<--->| (Proxy/Cache)     |<--->| (Cache API +     |
|                  |     |                   |     |  IndexedDB)      |
+------------------+     +-------------------+     +------------------+
        |                         |                         |
   Downloaded         Intercepts all          Manga images in
   chapter images     fetch requests          Cache API; reading
   served via         and applies             progress + metadata
   blob URLs          caching strategy        in IndexedDB
```

### 4.2 What to Cache

| Content Type | Strategy | Storage | Eviction |
|---|---|---|---|
| App shell (CSS, JS, fonts) | Cache-first, update on deploy | Cache API | Version-based |
| HTML pages | Network-first (3s timeout) | Cache API | LRU, max 50 pages |
| Downloaded chapter images | Cache-first (immutable) | Cache API | Manual (user deletes chapter) |
| Streamed source images | Cache-first after first load | Cache API | LRU, max 500 images |
| Series cover images | Stale-while-revalidate | Cache API | LRU, max 200 covers |
| Reading progress | Network-first, queue offline | IndexedDB | Sync on reconnect |
| Series/chapter metadata | Network-first, cache fallback | IndexedDB | Stale after 1 hour |

### 4.3 Storage Quotas

**Browser limits:**
- Chrome: ~6% of total disk space per origin (e.g., 6GB on a 100GB device)
- Firefox: ~50% of free disk space globally, 2GB max per origin group
- Safari: ~1GB per origin (strictest)
- **Conservative planning target: 500MB per device**

**Manga storage estimates:**
- Average manga page: 200-500KB (JPEG, 1200-1800px wide)
- Average chapter: 20-40 pages = 4-20MB
- 10 downloaded chapters = 40-200MB
- 50 downloaded chapters = 200MB-1GB

**Implications:** Need to be aggressive about eviction. Downloaded chapters should have priority. Streamed/cached pages should be evicted LRU. Show storage usage in settings.

### 4.4 Cache API for Manga Images

The Cache API is the right choice for manga page images (not IndexedDB) because:
- Cache API stores `Request`/`Response` pairs — the service worker can intercept image fetches and serve from cache transparently
- No need to convert images to/from blobs
- The browser handles memory-efficient streaming of large images
- Better integration with `<img>` tags (the cached response is served directly)

**Cache naming strategy:**
```
scanarr-app-shell-v1       # App assets (versioned)
scanarr-pages-downloaded   # Downloaded chapter images (persistent)
scanarr-pages-streamed     # Streamed source images (evictable)
scanarr-covers             # Cover images (evictable)
scanarr-html               # Cached HTML pages (evictable)
```

### 4.5 IndexedDB for Metadata

Use IndexedDB (via a lightweight wrapper like `idb` or raw API) for:
- **Offline reading queue:** Which chapters are cached for offline reading
- **Reading progress queue:** Progress updates made while offline, to be synced on reconnect
- **Chapter metadata cache:** Chapter lists, page URLs, series info for offline navigation
- **User preferences:** Reader settings, tap zone config, cached per-series preferences

### 4.6 Background Sync for Progress

When the user is reading offline and makes progress:

1. The reader controller calls the progress PATCH endpoint
2. Service worker intercepts the failed fetch (offline)
3. Stores the progress update in IndexedDB
4. Registers a Background Sync event: `registration.sync.register("sync-progress")`
5. When connectivity returns, the service worker receives the `sync` event
6. Replays all queued progress updates from IndexedDB to the server

**Fallback for browsers without Background Sync (Safari):**
- On reconnect (detected via `navigator.onLine` event), flush the IndexedDB queue
- Or flush on next page navigation

### 4.7 Download for Offline Flow

For chapters already downloaded server-side (via Scanarr's existing download system):

1. User taps "Save for offline" on a chapter (distinct from server-side download)
2. JavaScript fetches the chapter page URLs from a JSON API endpoint
3. Service worker pre-caches all page images into `scanarr-pages-downloaded` cache
4. UI shows download progress (X/Y pages cached)
5. Chapter is marked as "Available offline" in the UI
6. When reading offline, service worker serves images from cache

For chapters NOT downloaded server-side:
- Streaming source images are cached on first view (opportunistic offline)
- User can explicitly request "cache this chapter" which fetches all pages into cache
- Cached pages work even when the source goes down

### 4.8 Offline Fallback Page

When a user navigates to a page that is not cached and they are offline:

- Show a branded offline page with: app logo, "You're offline" message, list of chapters available offline, button to go to library (if cached)
- This is a pre-cached HTML page served by the service worker as a last resort

---

## 5. Mobile Navigation Overhaul

### 5.1 Bottom Navigation Bar

**Design (mobile only, hidden on `lg:` breakpoint):**

```
+------+--------+--------+--------+
|      |        |        |        |
| Lib  | Browse | History|  More  |
| (*)  |  (o)   |  (o)   |  (o)  |
+------+--------+--------+--------+
```

- Fixed to bottom of viewport
- `position: fixed; bottom: 0; z-index: 40`
- Respects safe area: `padding-bottom: env(safe-area-inset-bottom, 0)`
- Active tab has accent color highlight
- Badge on Browse tab for new chapters
- **Hidden when in reader** (fullscreen reading mode)

**Tab mapping:**

| Tab | Icon | Path | Content |
|---|---|---|---|
| Library | `book-open` | `/library` | User's manga collection |
| Browse | `globe` | `/` (Sources root) | Source browsing, search |
| History | `history` | `/history` | Reading history |
| More | `menu` | Sheet/modal | Settings, Downloads, Stats, Calendar, Admin |

The "More" tab opens a bottom sheet (not a new page) with links to: Downloads, Calendar, Stats, Search, Admin sections.

### 5.2 Responsive Layout Changes

**Current layout:** `lg:grid lg:grid-cols-[240px_minmax(0,1fr)]` — sidebar on desktop, hamburger on mobile.

**Proposed layout:**
- **Desktop (`lg:` and up):** Keep the current sidebar layout, no changes
- **Mobile (below `lg:`):** Remove hamburger menu button, add bottom tab bar, add padding at bottom of content to account for tab bar height (~60px + safe area)
- **Reader view:** Hide both sidebar and bottom tab bar for immersive reading

### 5.3 Pull-to-Refresh

**Implementation approach:**
- Disable browser's native pull-to-refresh: `overscroll-behavior-y: contain` on `<html>` or `<body>`
- Implement custom pull-to-refresh as a Stimulus controller
- Show a spinner/indicator when pulling down past threshold
- On release past threshold, trigger Turbo visit to reload the current page
- Apply on: Library page (refresh chapter counts), Series page (check new chapters), History page

**CSS:**
```css
html {
  overscroll-behavior-y: contain; /* Prevent native pull-to-refresh in PWA */
}
```

### 5.4 Haptic Feedback

**Vibration API** for tactile feedback on:
- Page turn in reader (short 10ms vibration)
- Download complete notification
- Pull-to-refresh trigger
- Tab bar tap

**Limitation:** Not supported on iOS Safari. Android Chrome only. Use as progressive enhancement:
```javascript
if ("vibrate" in navigator) {
  navigator.vibrate(10)
}
```

### 5.5 Reader-Specific Navigation

When in the reader, replace the standard app navigation with:
- **Swipe from left edge:** Back to series page
- **Tap center/top 5%:** Toggle reader toolbar
- **Tap zones:** Page navigation (configurable)
- **Hardware back button (Android):** Back to series page, or close toolbar first if open
- **Volume buttons (Android PWA):** Optional page navigation (Mihon feature, may not be available in PWA)

---

## 6. Recommended Implementation Phases

### Phase 1: PWA Foundation (1-2 days)

**Goal:** Make Scanarr installable as a PWA with basic offline shell caching.

1. Create `app/views/pwa/manifest.json.erb` with app metadata
2. Create `app/views/pwa/service-worker.js.erb` with app shell caching
3. Add PWA routes to `config/routes.rb`
4. Add `<link rel="manifest">` and Apple meta tags to layout
5. Add service worker registration to `app/javascript/application.ts`
6. Create app icons (192px, 512px, maskable)
7. Create offline fallback page
8. Test install flow on Android Chrome and iOS Safari

**Deliverables:** Installable PWA, app shell cached, offline fallback page.

### Phase 2: Mobile Reader UX (3-5 days)

**Goal:** Transform the reader into a touch-optimized, immersive reading experience.

1. **Tap zone navigation** — New Stimulus controller with Kindle-style default
2. **Show/hide toolbar** — Redesign reader header as toggle-able overlay
3. **Wake Lock** — Keep screen on while reading
4. **Fullscreen mode** — Enter immersive mode on reader open
5. **Page preloading** — Preload 3 pages ahead + next chapter prefetch
6. **Per-series reading mode** — Store in DB, load as default when opening series
7. **Viewport/safe area** — Handle notch, prevent accidental zoom in reader

**Deliverables:** Touch-optimized reader with tap zones, immersive mode, wake lock, preloading.

### Phase 3: Bottom Navigation + Mobile Layout (2-3 days)

**Goal:** App-like navigation on mobile.

1. **Bottom tab bar** — Stimulus component, visible on mobile, hidden on desktop and in reader
2. **Tab mapping** — Library, Browse, History, More (bottom sheet)
3. **Responsive layout update** — Adjust content padding for bottom bar
4. **Pull-to-refresh** — Custom implementation on key pages
5. **Safe area handling** — Bottom bar respects device safe areas

**Deliverables:** Mobile-native navigation feel, pull-to-refresh.

### Phase 4: Offline Reading (3-5 days)

**Goal:** Enable offline reading for downloaded chapters.

1. **Service worker image caching** — Cache-first for downloaded chapter images
2. **"Save for offline" UI** — Button per chapter to cache in browser
3. **Offline chapter list** — Show which chapters are available offline
4. **Background Sync** — Queue reading progress updates when offline
5. **Storage management UI** — Show cache usage, clear cached chapters
6. **IndexedDB metadata cache** — Chapter lists and series info for offline navigation
7. **Offline indicator** — Show connection status in UI

**Deliverables:** Offline reading for cached chapters, progress sync, storage management.

### Phase 5: Advanced Reader Features (2-3 days)

**Goal:** Parity with native manga reader apps.

1. **Pinch-to-zoom** — Using panzoom library on reader pages
2. **Orientation lock** — Per-series preference, tied to fullscreen
3. **Configurable tap zones** — Settings UI for choosing navigation layout
4. **Reader settings panel** — Slide-up sheet with reading mode, brightness, orientation
5. **Unread chapter badges** — On library covers
6. **Vertical pager mode** — New reading mode (page-by-page vertical)

**Deliverables:** Feature-rich reader matching native app capabilities.

### Phase 6: Polish & Progressive Enhancement (2-3 days)

**Goal:** Native-feel polish.

1. **Haptic feedback** — Vibration API on page turns and interactions
2. **Install prompt** — Custom A2HS banner for first-time visitors
3. **App updates** — Service worker update flow with "New version available" prompt
4. **Splash screen** — Loading screen for PWA launch
5. **Keyboard shortcuts help** — Overlay showing available shortcuts
6. **Performance audit** — Lighthouse PWA score, Core Web Vitals

**Deliverables:** Polished PWA experience scoring 90+ on Lighthouse PWA audit.

---

## 7. Libraries & Tools

### Must-Have (New Dependencies)

| Library | Size | Purpose | Alternative |
|---|---|---|---|
| None required for Phase 1-4 | — | Rails 8 PWA + native APIs | — |

### Recommended (Optional Dependencies)

| Library | Size | Purpose | Alternative |
|---|---|---|---|
| [panzoom](https://github.com/anvaka/panzoom) | 12KB gzip | Pinch-to-zoom on reader pages | Hand-rolled pointer events |
| [idb](https://github.com/jakearchibald/idb) | 1.2KB gzip | Promise-based IndexedDB wrapper | Raw IndexedDB API |
| [workbox](https://developer.chrome.com/docs/workbox) | Modular | Service worker toolkit (caching strategies, precaching) | Hand-rolled service worker |

### Built-In Web APIs (No Dependencies)

| API | Purpose | Browser Support |
|---|---|---|
| [Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API) | Offline caching, request interception | All modern browsers |
| [Cache API](https://developer.mozilla.org/en-US/docs/Web/API/Cache) | Store request/response pairs for offline | All modern browsers |
| [IndexedDB](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API) | Structured offline data storage | All modern browsers |
| [Screen Wake Lock](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API) | Keep screen on while reading | Chrome 84+, Safari 16.4+, Firefox 126+ |
| [Fullscreen API](https://developer.mozilla.org/en-US/docs/Web/API/Fullscreen_API) | Immersive reader mode | All modern browsers |
| [Screen Orientation](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Orientation_API) | Lock orientation in reader | Chrome, Firefox (not Safari) |
| [Pointer Events](https://developer.mozilla.org/en-US/docs/Web/API/Pointer_events) | Tap zones, gestures | All modern browsers |
| [Background Sync](https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API) | Queue offline progress updates | Chrome, Edge (not Safari/Firefox) |
| [Vibration API](https://developer.mozilla.org/en-US/docs/Web/API/Vibration_API) | Haptic feedback on page turn | Chrome, Firefox (not Safari) |
| [Storage API](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API) | Check/manage cache quota | All modern browsers |
| [Web App Manifest](https://developer.mozilla.org/en-US/docs/Web/Manifest) | PWA install, icons, theme | All modern browsers |

### Existing Scanarr Stack (No Changes Needed)

- **Stimulus** — All new controllers fit naturally into the existing Stimulus architecture
- **Turbo Drive** — Compatible with service worker caching (network requests are standard `fetch`)
- **Turbo Frames** — No changes needed; frame requests should bypass service worker cache
- **Tailwind CSS v4** — Bottom bar, safe areas, responsive breakpoints all use existing utilities

### Tools for Development & Testing

| Tool | Purpose |
|---|---|
| Chrome DevTools > Application > Service Workers | Debug service worker lifecycle, cache contents |
| Chrome DevTools > Application > Manifest | Validate manifest, test install |
| Lighthouse PWA Audit | Score PWA compliance, identify gaps |
| Chrome DevTools > Network > Offline checkbox | Test offline behavior |
| `about:serviceworker-internals` (Chrome) | Debug service worker internals |
| ngrok or similar | Test on real mobile device with HTTPS (required for service worker) |

---

## 8. Sources & References

### Mihon/Tachiyomi
- [Mihon GitHub Repository](https://github.com/mihonapp/mihon)
- [Reader viewer implementation](https://github.com/mihonapp/mihon/tree/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer)
- [Navigation tap zones](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer/ViewerNavigation.kt)
- [Reader preferences](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/setting/ReaderPreferences.kt)
- [Home screen / bottom nav](https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/home/HomeScreen.kt)

### Rails PWA
- [Rails 8 PWA support announcement](https://www.gauravvarma.dev/blog/rails-8-adds-web-push-notifications-and-improved-pwa-support)
- [DHH's PR adding PWA defaults to Rails](https://github.com/rails/rails/pull/50528)
- [Everything You Need to Ace PWAs in Rails](https://blog.codeminer42.com/everything-you-need-to-ace-pwas/)
- [Joy of Rails: Add to Home Screen](https://joyofrails.com/articles/add-your-rails-app-to-the-home-screen)
- [Yaroslav Shmarov's Rails 8 PWA guide](https://github.com/yshmarov/yshmarov.github.io/blob/master/_posts/2024-05-09-rails-8-pwa.md)

### Hotwire + Offline
- [Turbo Offline PR #1427](https://github.com/hotwired/turbo/pull/1427)
- [Building Offline-Capable Rails Apps](https://www.endpointdev.com/blog/2025/08/offline-capable-rails/)
- [Hotwire Weekly: Turbo Offline Support](https://www.hotwireweekly.com/archive/week-33-turbo-offline-support-css-functions/)

### Web APIs
- [Screen Wake Lock API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Screen_Wake_Lock_API)
- [Fullscreen API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Fullscreen_API)
- [Pointer Events: Pinch zoom (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Pointer_events/Pinch_zoom_gestures)
- [Background Sync API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Background_Synchronization_API)
- [Storage Quotas (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Storage_API/Storage_quotas_and_eviction_criteria)
- [Vibration API (MDN)](https://developer.mozilla.org/en-US/docs/Web/API/Vibration_API)
- [PWA Caching Strategies](https://web.dev/learn/pwa/caching)
- [PWA Offline Data](https://web.dev/learn/pwa/offline-data)

### PWA Design Patterns
- [Smashing Magazine: Sticky Elements in PWA](https://www.smashingmagazine.com/2020/01/mobile-pwa-sticky-bars-elements/)
- [Flowbite: Tailwind Bottom Navigation](https://flowbite.com/docs/components/bottom-navigation/)
- [Avoid notches in PWA with CSS](https://dev.to/marionauta/avoid-notches-in-your-pwa-with-just-css-al7)
- [Chrome: overscroll-behavior for pull-to-refresh](https://developer.chrome.com/blog/overscroll-behavior)
- [PWA Offline Storage: IndexedDB vs Cache API](https://dev.to/tianyaschool/pwa-offline-storage-strategies-indexeddb-and-cache-api-3570)
- [IndexedDB Max Storage](https://rxdb.info/articles/indexeddb-max-storage-limit.html)

### Touch/Gesture Libraries
- [PinchZoom.js](https://manuelstofer.github.io/pinchzoom/)
- [panzoom](https://github.com/anvaka/panzoom)
- [ZingTouch gesture library](https://zingchart.github.io/zingtouch/)
- [CSS touch-action (MDN)](https://developer.mozilla.org/en-US/docs/Web/CSS/touch-action)

### Other Manga Reader PWAs (Reference)
- [MangaOfflineViewer (Angular PWA)](https://github.com/zarar384/MangaOfflineViewer)
- [manga.up (PWA manga reader)](https://github.com/Fazendaaa/manga.up)
- [Kavita (self-hosted digital library)](https://www.kavitareader.com/)
- [Komga (self-hosted comics server)](https://komga.org/)
