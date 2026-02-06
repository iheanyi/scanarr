# *arr Ecosystem & Manga App Research

> Research conducted February 2026 to guide Scanarr's product direction.
> Covers: Sonarr, Radarr, Lidarr, Prowlarr, Overseerr, Komga, Kavita, Tachiyomi/Mihon, Mylar3.

---

## Table of Contents

1. [Feature Comparison Matrix](#1-feature-comparison-matrix)
2. [Key Features Scanarr Should Adopt](#2-key-features-scanarr-should-adopt)
3. [Architecture Patterns Worth Following](#3-architecture-patterns-worth-following)
4. [UX Patterns to Emulate](#4-ux-patterns-to-emulate)
5. [What Makes *arr Apps Feel Professional](#5-what-makes-arr-apps-feel-professional)
6. [Manga-Specific Table Stakes](#6-manga-specific-table-stakes)
7. [Recommended Feature Roadmap](#7-recommended-feature-roadmap)

---

## 1. Feature Comparison Matrix

### Legend
- **Y** = Has feature
- **P** = Partial / basic implementation
- **N** = Missing
- **N/A** = Not applicable to this app type

### Core Features

| Feature | Scanarr | Sonarr | Radarr | Komga | Kavita | Mihon | Mylar3 |
|---------|---------|--------|--------|-------|--------|-------|--------|
| **Library Management** | P (library page, series list) | Y (root folders, series overview, mass editor) | Y (root folders, movie overview) | Y (multiple libraries, per-library settings) | Y (multiple libraries, smart filters) | Y (categories, per-source organization) | Y (watchlist-based) |
| **Metadata Handling** | P (scraped from sources only) | Y (TVDB/TMDB, auto-enrichment) | Y (TMDB, auto-enrichment) | Y (ComicInfo.xml, EPUB metadata, manual edit) | Y (filename parsing, ComicInfo, Kavita+ enrichment) | P (from extensions) | Y (ComicVine) |
| **Source/Indexer Management** | Y (5 adapters: MangaDex, AsuraScans, WeebCentral, MangaSee, MangaPill) | Y (Newznab/Torznab, via Prowlarr) | Y (same as Sonarr) | N/A (reads local files) | N/A (reads local files) | Y (extension system, 500+ sources) | Y (NZB/torrent indexers) |
| **Monitoring / Tracking** | P (follow series, check for new chapters job) | Y (series monitoring, season/episode level) | Y (movie monitoring, collection monitoring) | P (read progress tracking) | Y (read progress, re-read tracking, sessions) | Y (library tracking, update checking) | Y (watchlist monitoring, pull-list tracking) |
| **Auto Downloads** | P (auto-download on follow) | Y (quality profiles, RSS monitoring, auto-upgrade) | Y (same + custom formats) | N/A | N/A | Y (auto-download new chapters) | Y (auto-download, watchlist-based) |
| **Quality Profiles** | N | Y (cutoff, upgrade, preferred formats) | Y (quality + custom formats scoring) | N/A | N/A | N/A | P (preferred format) |
| **Notifications** | P (in-app only, new chapters) | Y (20+ services: Discord, email, Slack, Telegram, webhooks, etc.) | Y (same) | N | P (basic) | N | P (email, webhook) |
| **Calendar / Schedule** | Y (calendar view) | Y (episode calendar) | Y (movie release calendar) | N | N | N | P (pull-list calendar) |
| **Search & Discovery** | Y (cross-source search) | Y (add series search via TVDB) | Y (add movie + TMDb discovery/recommendations) | Y (Lucene full-text search) | Y (full-text + smart filters) | Y (per-source search + browse) | Y (ComicVine search) |
| **Import/Export** | N | Y (import lists from Trakt, IMDb, etc.) | Y (import lists, TMDb lists) | Y (ComicRack import, copy/move/upgrade modes) | Y (reading list import, send to Kindle) | Y (backup/restore) | P (manual import) |
| **API** | N | Y (REST v3/v5, OpenAPI docs, API key auth) | Y (REST v3, OpenAPI) | Y (REST v1, OpenAPI 3.1, comprehensive) | Y (REST API, OPDS feeds) | N/A (mobile app) | P (basic API) |
| **Activity / Queue** | P (admin downloads page) | Y (queue, history, blocklist) | Y (same) | N/A | N/A | N | P (queue) |
| **System Status / Health** | N | Y (health checks, disk space, indexer status) | Y (same) | P (tasks, library status) | P (server stats) | N | P (basic) |
| **Mass Editor** | N | Y (bulk series management) | Y (bulk movie management) | Y (bulk metadata editing) | P | N | P |
| **Reading** | Y (chapter reader with progress) | N/A | N/A | Y (web reader: single, double, webtoon, continuous) | Y (web reader, EPUB reader, annotation) | Y (mobile reader, multiple modes) | N |
| **OPDS Support** | N | N/A | N/A | Y (v1.2 + v2.0) | Y | N/A | N |
| **User Management** | P (single admin user) | P (single user + API keys) | P (same) | Y (multi-user, roles, per-library ACL) | Y (multi-user, OIDC, age restrictions) | N/A | P (single user) |
| **External Tracking Sync** | N | N/A | N/A | P (via Komf/MAL-Sync) | Y (AniList/MAL via Kavita+) | Y (MAL, AniList, Kitsu, MangaUpdates) | N |
| **Mobile App** | N | Y (3rd-party: LunaSea, Ruddarr) | Y (same) | Y (Mihon extension + OPDS readers) | Y (OPDS readers, Mihon) | Y (native Android) | N |
| **Bulk Download** | Y (download all chapters) | Y (search all missing) | Y (search all missing) | N/A | N/A | Y (download all) | Y |
| **Collections / Lists** | N | Y (tags) | Y (collections, tags) | Y (collections, read lists) | Y (collections, reading lists, smart filters) | Y (categories) | Y (story arcs) |

### Scanarr's Current Strengths
- **Multi-source aggregation**: 5 manga sources with adapter pattern (MangaDex, AsuraScans, WeebCentral, MangaSee, MangaPill)
- **Chapter reader**: Built-in reading with progress tracking
- **Calendar view**: Upcoming/recent chapter releases
- **Download management**: Per-chapter and bulk download with status tracking
- **Follow system**: Series following with auto-download policy (notify-only vs auto-download)
- **Cross-source search**: Search across all sources simultaneously
- **Source browsing**: Browse, search, and preview within individual sources

### Scanarr's Key Gaps
- No quality profiles or download preferences
- No external notifications (Discord, email, webhooks)
- No public API
- No OPDS support (can't connect to Mihon/other readers)
- No import/export
- No system health monitoring
- No external tracking sync (AniList, MAL)
- No mass editor / bulk operations
- No collections or reading lists
- Limited metadata enrichment
- Single-user only (no multi-user, no ACL)

---

## 2. Key Features Scanarr Should Adopt

### From *arr Apps (High Priority)

#### 2a. Wanted / Missing System (from Sonarr)
Sonarr's "Wanted" section is one of its most valuable features:
- **Missing**: Chapters you're monitoring that haven't been downloaded yet
- **Cutoff Unmet**: Downloaded chapters that don't meet your quality preference (e.g., you have a low-quality scan but want a higher-quality source)
- **Search All Missing**: One-click to search and download all missing chapters

**Scanarr equivalent**: "Wanted" page showing:
- Chapters from followed series that aren't downloaded
- Downloaded chapters where a better source exists
- Ability to search all missing with one click

#### 2b. Activity Feed (from Sonarr/Radarr)
The Activity section has two sub-pages:
- **Queue**: Active downloads with real-time progress, source info, estimated time
- **History**: Completed actions (downloads, imports, upgrades, deletions) with timestamps
- **Blocklist**: Releases that failed and should be skipped in future searches

**Scanarr equivalent**: Replace the current admin-only downloads page with a first-class Activity page visible in the main nav:
- Active download queue with progress bars and source info
- Download history with filtering
- Failed downloads with retry/blocklist options

#### 2c. External Notifications (from Sonarr/Radarr)
Sonarr supports 20+ notification channels including Discord, email, Slack, Telegram, Pushover, webhooks, and more. Events that trigger notifications:
- New chapter available
- Chapter downloaded
- Download failed
- Series added/removed
- Health check failure

**Scanarr equivalent**: Start with:
1. **Webhooks** (universal, enables any integration)
2. **Discord** (most popular in the manga community)
3. **Email** (essential fallback)

#### 2d. System Status & Health (from Sonarr)
Sonarr's System page includes:
- **Health checks**: Verifies indexers are reachable, disk space is adequate, download clients are connected
- **Status**: App version, OS info, uptime
- **Tasks**: Scheduled tasks with last run time and next run
- **Logs**: Searchable application logs
- **Updates**: Available version info

**Scanarr equivalent**: System page showing:
- Source health (is MangaDex responding? Is AsuraScans rate-limited?)
- Job status (when did CheckNewChaptersJob last run? Is it stuck?)
- Disk usage for downloads
- App version and uptime

#### 2e. Import Lists (from Sonarr/Radarr)
Users can import series from external lists:
- Trakt lists, IMDb watchlists, TMDb lists
- Automatically add and monitor imported series

**Scanarr equivalent**: Import from:
- AniList reading list
- MyAnimeList list
- MangaUpdates reading list
- CSV/JSON import

#### 2f. Root Folders / Download Organization (from Sonarr)
Sonarr uses "root folders" — base directories where media is stored, with configurable naming schemes for organization:
- `/manga/` as root folder
- Series get their own subfolder: `/manga/One Piece/`
- Chapters named by pattern: `One Piece - Chapter 001.cbz`

**Scanarr equivalent**: Configurable download paths with naming templates for organized storage.

#### 2g. Mass Editor (from Sonarr/Radarr)
Bulk operations on series:
- Change monitoring status for multiple series
- Change quality profile for multiple series
- Change root folder for multiple series
- Delete multiple series at once

**Scanarr equivalent**: Select multiple series in library and bulk-change follow status, download policy, or delete.

### From Manga Apps (High Priority)

#### 2h. OPDS Feed (from Komga/Kavita)
OPDS is the "RSS for ebooks/comics." It allows any OPDS-compatible reader to browse and read from Scanarr's library. This is critical because:
- Users can use Mihon/Tachiyomi to read from Scanarr as a source
- Any OPDS reader (Panels, Chunky, etc.) can connect
- It's how self-hosted manga servers integrate with the broader ecosystem

#### 2i. External Tracking Sync (from Mihon/Kavita)
Sync reading progress with:
- **AniList** (most popular in manga community)
- **MyAnimeList**
- **Kitsu**
- **MangaUpdates**

When a user finishes a chapter, automatically update their tracking profile.

#### 2j. Collections & Reading Lists (from Komga/Kavita)
- **Collections**: Group series thematically ("Isekai favorites", "Currently reading", "Top 10")
- **Reading Lists**: Ordered lists of specific chapters for reading in sequence (e.g., a crossover event reading order)

#### 2k. Enhanced Metadata (from Komga/Kavita + Mihon)
Current Scanarr metadata comes only from scraped sources. Should enrich with:
- Genre tags (from AniList/MAL)
- Demographic info (Shonen, Seinen, etc.)
- Author/artist info (enriched from MAL/AniList)
- Related series links
- Publication status and year
- Average rating from external sources

#### 2l. Advanced Reading Features (from Komga/Kavita)
Komga's reader supports:
- Single page, double page, webtoon (continuous vertical), continuous modes
- Fit-to-width, fit-to-height, custom zoom
- Keyboard shortcuts and click zones
- Cross-device progress sync

### From *arr Apps (Medium Priority)

#### 2m. Public REST API (from Sonarr/Radarr/Komga)
A well-documented REST API is essential for:
- Third-party mobile apps (like LunaSea for Sonarr)
- Automation scripts
- Integration with other *arr apps
- Widget/dashboard support (Homarr, Organizr)

Sonarr uses OpenAPI documentation, API key authentication, and versioned endpoints (`/api/v1/`).

#### 2n. Tags System (from Sonarr/Radarr)
Tags are a flexible labeling system used to:
- Group series for bulk operations
- Apply specific settings to tagged series
- Filter views by tag

#### 2o. Discovery & Recommendations (from Radarr/Overseerr)
Radarr shows recommendations based on your library. Overseerr provides a discovery interface where users can browse trending content.

**Scanarr equivalent**:
- "Discover" page with trending/popular manga from sources
- "Similar series" recommendations on series detail pages
- "Because you follow X, you might like Y"

---

## 3. Architecture Patterns Worth Following

### 3a. Sonarr's "Wanted" Architecture
Sonarr categorizes episodes into three states that drive the download automation:

```
MONITORED SERIES
├── Available (downloaded, meets quality cutoff)  → No action needed
├── Missing (monitored but not downloaded)        → Search & download
└── Cutoff Unmet (downloaded but below cutoff)    → Search for upgrade
```

The "Wanted" page surfaces Missing and Cutoff Unmet items. Users can:
1. Search individual items
2. Search all missing in one click
3. Unmonitor items they don't want
4. Filter by series, status, etc.

**For Scanarr**: Chapters could have states:
- `available` — Downloaded from a preferred source
- `missing` — Monitored but not downloaded
- `upgrade_available` — Downloaded but a better source version exists
- `unavailable` — Not available from any configured source

### 3b. Prowlarr's Centralized Indexer Management
Prowlarr is the *arr ecosystem's answer to managing sources across apps:
- Define indexers once in Prowlarr
- Syncs to Sonarr, Radarr, Lidarr automatically
- Health monitoring per indexer
- Per-indexer proxy support (including FlareSolverr for Cloudflare)
- Rate limiting per indexer

**For Scanarr**: The existing adapter pattern is solid, but should add:
- Source health monitoring with automatic fallback
- Per-source rate limiting configuration
- Source priority ordering (prefer MangaDex, fall back to AsuraScans)
- Source-specific configuration UI (API keys, proxy settings)

### 3c. Radarr's Quality Profiles + Custom Formats
Radarr's quality system is two-layered:

1. **Quality Profiles**: Define acceptable quality tiers with a cutoff
   - e.g., "High Quality" profile: allow 720p, 1080p, 4K — cutoff at 1080p
2. **Custom Formats**: Scoring system for release attributes
   - e.g., +10 for releases from specific groups, -50 for machine-translated

**For Scanarr (manga equivalent)**:
- **Source Priority Profiles**: Rank sources by preference
  - e.g., "High Quality" profile: MangaDex > WeebCentral > AsuraScans
- **Custom Preferences**: Score releases by attributes
  - +10 for official translations
  - +5 for high-resolution scans
  - -20 for machine-translated
  - Prefer English > Spanish > Portuguese

### 3d. Komga/Kavita's Reading Server Architecture
These apps separate concerns:
- **File storage**: Organized on disk with metadata sidecars
- **Metadata enrichment**: Via ComicInfo.xml, EPUB metadata, or external API
- **Reading delivery**: Web reader + OPDS feeds + device sync
- **Progress tracking**: Server-side, per-user, cross-device

**For Scanarr**: The unique value prop is that Scanarr both *acquires* and *serves* manga, unlike Komga/Kavita which only serve local files. The architecture should cleanly separate:
1. **Acquisition layer**: Adapters, downloads, quality selection
2. **Library layer**: Organization, metadata, collections
3. **Reading layer**: Web reader, OPDS, progress sync
4. **Tracking layer**: External service sync (AniList, MAL)

### 3e. Sonarr's Event-Driven Notification Architecture
Sonarr uses an event system where actions emit events, and notification handlers subscribe:

```
Events:
├── SeriesAdd / SeriesDelete
├── EpisodeFileDownload / EpisodeFileDelete
├── EpisodeFileUpgrade
├── HealthCheckFailed
└── ApplicationUpdate

Handlers (Connections):
├── Discord, Slack, Telegram, Email, ...
├── Plex, Emby, Kodi (library updates)
├── Custom Webhook
└── Custom Script
```

**For Scanarr**: Implement an event bus:
```
Events:
├── series.followed / series.unfollowed
├── chapter.available / chapter.downloaded / chapter.download_failed
├── chapter.read
├── source.health_changed
└── system.update_available

Handlers:
├── InAppNotification (existing)
├── WebhookNotification (priority #1)
├── DiscordNotification (priority #2)
├── EmailNotification (priority #3)
└── TrackingServiceSync (AniList, MAL)
```

### 3f. Overseerr's Request System
Overseerr adds a social layer:
- Users can *request* media they want
- Admins approve/deny requests
- Approved requests automatically trigger Sonarr/Radarr to search

**For Scanarr (future)**: If multi-user is added:
- Users request series to be added
- Admin approves, series gets imported and monitored
- Request quotas per user

---

## 4. UX Patterns to Emulate

### 4a. Sonarr's Navigation Structure

```
Sidebar:
├── Series (library overview with filters, sort, views)
├── Calendar (upcoming episodes in month/week/day views)
├── Activity
│   ├── Queue (active downloads with progress)
│   └── History (completed actions log)
├── Wanted
│   ├── Missing (monitored, not downloaded)
│   └── Cutoff Unmet (below quality preference)
├── Settings
│   ├── Media Management
│   ├── Profiles (Quality + Language + Delay)
│   ├── Quality (source definitions)
│   ├── Custom Formats
│   ├── Indexers
│   ├── Download Clients
│   ├── Import Lists
│   ├── Connect (notifications)
│   ├── Metadata
│   ├── Tags
│   ├── General
│   └── UI
├── System
│   ├── Status (version, health checks)
│   ├── Tasks (scheduled jobs)
│   ├── Backup
│   ├── Updates
│   └── Events/Logs
└── (User menu)
```

**Scanarr recommended nav restructure**:
```
Sidebar:
├── Browse (sources, trending)
│   ├── Home / Sources
│   └── Search
├── Library (your followed series)
├── Calendar
├── Activity
│   ├── Queue
│   └── History
├── Wanted
│   ├── Missing
│   └── Upgrades Available
├── Settings
│   ├── Sources (adapter config)
│   ├── Downloads (paths, naming)
│   ├── Notifications
│   ├── Tracking (AniList, MAL)
│   └── General
├── System
│   ├── Status & Health
│   ├── Jobs
│   └── Logs
└── (User menu)
```

### 4b. Sonarr's Series Detail Page
Shows:
- Series poster + banner
- Status (continuing/ended), network, genres, year
- Quality profile assignment
- Root folder assignment
- Monitoring toggle (per-season granularity)
- Season list with episode details
- Episode list with download status per episode
- Manual search per episode
- Series-level actions (refresh, search all, edit)

**Scanarr equivalent already has much of this.** Key additions:
- Source priority display (which source is being used)
- Per-chapter source info (where it was downloaded from)
- Monitoring granularity (individual chapter level)
- Activity history for this series

### 4c. Radarr's Discovery/Add Flow
When adding a movie in Radarr:
1. Search by title → Results from TMDb
2. Select the correct match → Shows metadata preview
3. Configure: root folder, quality profile, monitoring, tags
4. Option: "Search for movie" immediately or just monitor

**Scanarr equivalent**: When importing a series from a source:
1. Search or browse source → Results with cover art and metadata
2. Select series → Preview page with chapter list (already exists!)
3. Configure: follow type (notify/auto-download), download existing chapters
4. Import and optionally start downloading

### 4d. Overseerr's Request/Discovery UX
Beautiful, Netflix-like discovery interface:
- Hero banner with trending content
- Rows of recommendations
- Clean card-based grid layout
- Request button prominently featured
- Status indicators on cards (available, requested, processing)

**Scanarr opportunity**: A "Discover" page that shows:
- Trending manga across sources
- Popular new releases
- Based on your library recommendations
- Quick-add button on each card

### 4e. Komga/Kavita's Reading UX
Komga's web reader:
- Full-screen immersive reading
- Reading mode selector (single, double, webtoon, continuous)
- Keyboard shortcuts (arrow keys, spacebar)
- Touch zones for mobile (tap left/right/center)
- Thumbnail scrubber for quick navigation
- Reading progress auto-saved
- "Continue reading" on homepage

**Scanarr**: The existing reader should be enhanced with:
- Mode switching (single page / double page / webtoon scroll)
- Keyboard shortcuts
- Auto-continue to next chapter
- "Continue Reading" prominent on homepage
- Full-screen mode

---

## 5. What Makes *arr Apps Feel Professional

### 5a. Consistent, Information-Dense UI
- Every piece of information has a purposeful place
- Color-coded status indicators everywhere (green = good, red = error, yellow = warning, blue = info)
- Tooltips and hover states provide additional context
- Tables with sortable columns and filters

### 5b. Real-Time Feedback
- SignalR (WebSocket) for live updates — downloads progress in real-time
- No page refresh needed to see new data
- Toast notifications for completed actions
- Progress bars that actually move

### 5c. Comprehensive Settings with Sensible Defaults
- Every configurable option is accessible but organized into logical categories
- Settings are explained with descriptions
- "Test" buttons for connections (test notification, test indexer)
- Validation before saving

### 5d. Error Recovery & Transparency
- Failed downloads show exactly why they failed
- Retry buttons everywhere
- Blocklist system to skip known-bad releases
- Health checks that proactively warn about issues
- Logs are searchable and filterable

### 5e. Keyboard Shortcuts & Power User Features
- `/` to focus search
- Keyboard navigation in lists
- Mass selection with shift+click
- Bulk actions on selections

### 5f. Polish Details
- Smooth transitions and animations
- Loading states (skeleton screens, spinners)
- Empty states with helpful messages
- Consistent iconography
- Dark/light mode
- Responsive layout that works on tablet
- Version info in footer/system page

### 5g. System Tray / Background Operation
- Runs as a service/daemon
- Web UI is always accessible
- Scheduled tasks run on their own
- No manual intervention needed day-to-day

---

## 6. Manga-Specific Table Stakes

These are features that manga readers **expect** from a manga management app. Without them, Scanarr won't be taken seriously by the manga self-hosting community.

### 6a. OPDS Support (Critical)
- This is how manga servers integrate with reading apps
- Without OPDS, users can't use their preferred reading app
- Both Komga and Kavita have it, it's expected
- Mihon (most popular manga reader) can connect via OPDS

### 6b. Tracking Sync (Critical)
- AniList is the dominant tracking platform for manga readers
- MAL is the runner-up
- Users expect reading progress to sync automatically
- Kavita has this built in, Komga achieves it via Komf + MAL-Sync
- This is THE feature that makes manga readers switch to self-hosted solutions

### 6c. Reading Modes (Important)
- **Webtoon mode** (continuous vertical scroll) is essential — Korean manhwa is huge and it's all webtoon format
- **Double page spread** for traditional manga
- **Right-to-left reading** for Japanese manga
- **Left-to-right** for manhwa/Western comics

### 6d. Metadata from Manga Databases (Important)
- AniList and MyAnimeList have the richest manga metadata
- Genres, demographics, relations, recommendations, scores
- Cover art, author/artist info, publication info
- Character lists, related anime
- This makes the library feel complete and browsable

### 6e. CBZ Export (Important)
- Kavita and Komga work with CBZ/CBR files
- Users want to export downloaded chapters as CBZ for portability
- This enables transferring manga to other readers/devices
- Scanarr should store downloads in CBZ format or offer conversion

### 6f. Multi-Language Support (Important)
- Manga readers often read in multiple languages
- MangaDex has translations in 20+ languages
- Users should be able to set preferred languages
- Chapter list should show language when multiple translations exist

### 6g. Chapter De-Duplication (Nice to Have)
- When following a series from multiple sources, same chapters may appear
- Smart de-duplication based on chapter number + language
- Prefer higher-quality or preferred-source version

---

## 7. Recommended Feature Roadmap

### Phase 1: Core Loop Enhancement (Next 2-4 weeks)
Focus: Make the existing download-and-read loop feel more complete and professional.

1. **Activity Page** (replace admin downloads with first-class activity)
   - Queue with real-time progress
   - History of completed downloads
   - Failed downloads with retry
   - Move from admin-only to main navigation

2. **Wanted Page**
   - Missing: monitored chapters not yet downloaded
   - Search All Missing button
   - Filter by series

3. **Source Health Monitoring**
   - Track source response times and error rates
   - Display status on sources page
   - Alert when a source goes down

4. **Enhanced Reader**
   - Webtoon (continuous scroll) mode
   - Double-page spread mode
   - Right-to-left reading support
   - Keyboard shortcuts
   - "Continue Reading" on homepage

### Phase 2: Ecosystem Integration (4-8 weeks)
Focus: Connect Scanarr to the broader manga ecosystem.

5. **OPDS Feed**
   - Expose library via OPDS v1.2 and v2.0
   - Allow Mihon and other OPDS readers to connect
   - Per-user authentication for OPDS

6. **External Tracking Sync**
   - AniList OAuth integration
   - Auto-sync reading progress when chapter completed
   - Import reading list to bootstrap follows

7. **Webhook Notifications**
   - Configurable webhook endpoint
   - Events: chapter available, download complete, download failed
   - JSON payload with event details

8. **Discord Notifications**
   - Rich embeds with cover art
   - Configurable events per channel
   - Summary vs individual chapter notifications

### Phase 3: Quality & Preferences (8-12 weeks)
Focus: Sophisticated download behavior matching *arr quality profiles.

9. **Source Priority Profiles**
   - Rank sources by preference per series or globally
   - Auto-select best available source
   - Upgrade to preferred source when available

10. **Download Preferences**
    - Preferred language
    - Preferred scanlation groups
    - Minimum quality thresholds
    - Naming templates for saved files

11. **Metadata Enrichment**
    - AniList/MAL metadata fetching
    - Genre, demographic, score, relations
    - Enhanced series detail page

12. **CBZ Export / Storage**
    - Store downloads in CBZ format
    - Export individual chapters or full series
    - Configurable download paths with naming templates

### Phase 4: Library & Organization (12-16 weeks)
Focus: Power-user features for large libraries.

13. **Collections & Reading Lists**
    - User-created collections
    - Ordered reading lists
    - Smart collections based on filters

14. **Mass Editor**
    - Bulk follow/unfollow
    - Bulk change download policy
    - Bulk download/delete
    - Tag management

15. **Tags System**
    - User-defined tags on series
    - Filter by tag throughout the app
    - Bulk tag operations

16. **Public REST API**
    - API key authentication
    - OpenAPI documentation
    - Endpoints for series, chapters, downloads, library
    - Enable third-party app development

### Phase 5: Social & Discovery (16-20 weeks)
Focus: Discovery and multi-user features.

17. **Discover Page**
    - Trending manga from sources
    - Recommendations based on library
    - Popular across the community

18. **Import Lists**
    - Import from AniList reading list
    - Import from MAL
    - CSV import

19. **Multi-User Support**
    - User accounts with permissions
    - Per-user library/follows
    - Per-user reading progress
    - Admin vs reader roles

20. **System Page**
    - Full health dashboard
    - Scheduled tasks with run history
    - Application logs viewer
    - Backup/restore

---

## App-by-App Summary

### Sonarr — What to Learn
- **Navigation structure** is the gold standard for media management apps
- **Wanted/Missing** concept is brilliant for driving automated downloads
- **Activity queue + history** makes downloads transparent
- **Health checks** build trust that the system is working
- **Notification framework** with 20+ services and event-based triggers
- **Calendar** works exactly like Scanarr's but with more polish
- **Settings organization** is logical and well-documented

### Radarr — What to Learn
- **Custom Formats** scoring system for ranking releases is sophisticated
- **Discovery page** with TMDb recommendations is a great add
- **Import lists** for bulk series management
- **Collection monitoring** auto-follows related entries
- **Movie details page** with rich metadata and multiple action buttons

### Prowlarr — What to Learn
- **Centralized source management** with health monitoring
- **Per-source rate limiting** and proxy configuration
- **FlareSolverr integration** for Cloudflare-protected sites
- **Source testing** to verify connectivity
- **YAML-based source definitions** (Cardigann) for easy extension development

### Overseerr — What to Learn
- **Beautiful discovery UX** with Netflix-like browsing
- **Request workflow** for multi-user environments
- **Availability status** synced across services
- **User quotas** for controlled access

### Komga — What to Learn
- **OPDS implementation** (v1.2 + v2.0)
- **Multi-user with per-library ACL** and age restrictions
- **Comprehensive REST API** with OpenAPI docs
- **Kobo and KOReader sync** for device integration
- **Collections and reading lists** for organization
- **Duplicate detection** via content hashing
- **Full-text search** via Lucene indexing

### Kavita — What to Learn
- **Reading experience** is best-in-class (especially for manga/webtoons)
- **Smart filters** for dynamic library views
- **AniList/MAL sync** built right in
- **Send to Kindle** feature
- **Annotations and highlights** for engaged reading
- **Re-read tracking** and reading sessions
- **Dashboard customization** with user-controlled layouts

### Mihon/Tachiyomi — What to Learn
- **Extension architecture** is the gold standard for manga source management
- **Tracking integration** (MAL, AniList, Kitsu) is expected by users
- **Library categories** for organization
- **Automatic update checking** with background refresh
- **Backup/restore** for portability
- **Multiple reading modes** (webtoon, left-to-right, right-to-left)

### Mylar3 — What to Learn
- **Watchlist-based monitoring** with automatic download
- **Pull-list tracking** for weekly releases
- **Story arc management** is a unique and valuable concept for manga arcs
- **Auto-tagging** of downloaded files with metadata
- **Failed download handling** with automatic retry

---

## Sources

### *arr Ecosystem
- [Sonarr GitHub](https://github.com/Sonarr/Sonarr)
- [Sonarr DeepWiki](https://deepwiki.com/Sonarr/Sonarr)
- [Sonarr Guide - RapidSeedbox](https://www.rapidseedbox.com/blog/ultimate-guide-to-sonarr)
- [Sonarr Wanted - Servarr Wiki](https://wiki.servarr.com/sonarr/wanted)
- [Sonarr Activity - Servarr Wiki](https://wiki.servarr.com/sonarr/activity)
- [Sonarr System - Servarr Wiki](https://wiki.servarr.com/sonarr/system)
- [Sonarr Settings - Servarr Wiki](https://wiki.servarr.com/sonarr/settings)
- [Radarr Quality Management - DeepWiki](https://deepwiki.com/radarr/radarr/3.3-quality-management)
- [Radarr REST API - DeepWiki](https://deepwiki.com/radarr/radarr/4.1-rest-api)
- [Radarr Setup Guide - RapidSeedbox](https://www.rapidseedbox.com/blog/guide-to-radarr)
- [TRaSH Guides - Quality Profiles](https://trash-guides.info/Radarr/radarr-setup-quality-profiles/)
- [TRaSH Guides - Sonarr Naming](https://trash-guides.info/Sonarr/Sonarr-recommended-naming-scheme/)
- [Prowlarr GitHub](https://github.com/Prowlarr/Prowlarr)
- [Prowlarr DeepWiki](https://deepwiki.com/Prowlarr/Prowlarr/1-overview)
- [Prowlarr Guide - RapidSeedbox](https://www.rapidseedbox.com/blog/prowlarr-guide)
- [Overseerr GitHub](https://github.com/sct/overseerr)
- [Overseerr Guide - RapidSeedbox](https://www.rapidseedbox.com/blog/overseerr-guide)
- [Lidarr](https://lidarr.audio/)

### Manga/Comic Apps
- [Komga GitHub](https://github.com/gotson/komga)
- [Komga Features - DeepWiki](https://deepwiki.com/gotson/komga/1.1-features-and-capabilities)
- [Kavita](https://www.kavitareader.com/)
- [Kavita GitHub](https://github.com/Kareadita/Kavita)
- [Kavita vs Komga - BookRunch](https://www.bookrunch.org/comparison/kavita_vs_komga/)
- [Kavita Reading Lists Wiki](https://wiki.kavitareader.com/guides/features/readinglists/)
- [Mihon](https://mihon.app/)
- [Mihon Tracking Docs](https://mihon.app/docs/guides/tracking)
- [Mylar3 GitHub](https://github.com/mylar3/mylar3)
- [Komf - Metadata Fetcher](https://github.com/Snd-R/komf)
- [Suwayomi-Server - DeepWiki](https://deepwiki.com/Suwayomi/Suwayomi-Server/1-overview)
- [Self-hosted media server comparison - marcin-lis.pl](https://marcin-lis.pl/self-hosted-media-server-for-comics-mangas-and-magazines)
