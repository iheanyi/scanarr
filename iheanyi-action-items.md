# Action Items for Iheanyi

## Full Tachiyomi Import — Dry Run Results (2026-02-08)

### Backup File
`app.mihon_2026-02-08_22-27.tachibk` (6.3 MB)

### Import Preview
| Metric | Count |
|--------|-------|
| Total manga in backup | 1,973 |
| Mapped (will import) | 1,245 (63%) |
| Unmapped (will skip) | 728 (37%) |
| Total chapters | 186,783 |
| Read chapters | 69,271 |
| History entries | 34,753 |
| Tracking entries (MAL/AniList) | 88 |

### Import Result
Full import completed in ~30 seconds, **0 errors**. All 1,245 mapped manga deduped against existing data — your library was already synced from prior imports. The import correctly:
- Deduped series by title (tier 3)
- Skipped existing chapters
- Processed 728 unmapped manga without error

### Mapped Sources (13 sources, 1,245 manga)
- MangaDex, Weeb Central, MangaLife, MangaSee, Bato.to (x2 variants)
- Mangahere, Mangakakalot, Manganato, Flame Comics, MangaFire
- Toonily, Asura Scans

### Unmapped Sources (18 sources, 728 manga)
These sources need adapters to import their manga:

| Source | Manga Count | Priority |
|--------|------------|----------|
| MangaKatana | 329 | HIGH |
| Unknown (6259531251211001503) | 85 | MEDIUM |
| MangaPark | 81 | HIGH |
| Mangabat | 64 | MEDIUM |
| Unknown (3513686203838259177) | 61 | MEDIUM |
| MANGA Plus by SHUEISHA | 37 | MEDIUM |
| Infernal Void Scans | 20 | LOW |
| HentaiRead | 13 | SKIP (NSFW) |
| MangaFox | 12 | LOW |
| MANGA Plus Creators by SHUEISHA | 9 | LOW |
| MangaReader | 5 | LOW |
| Unknown (6350607071566689772) | 3 | LOW |
| Mangakakalots (unoriginal) | 2 | LOW |
| Death Toll Scans | 2 | LOW |
| Unknown (5177220001642863679) | 2 | LOW |
| Hive Scans | 1 | LOW |
| Raven Scans | 1 | LOW |
| Unknown (5509224355268673176) | 1 | LOW |

### Next Steps for You
1. **Try the web import flow** — Go to `/export` in Scanarr, upload your .tachibk file, preview it, and confirm the import. It now runs as a background job with Turbo Stream status updates.
2. **Re-export from Mihon** — Your first export was 0 bytes. Try exporting again from Mihon and make sure the file is > 0 bytes before pulling it.
3. **Test the preview page** — The preview shows all sources with mapped/unmapped badges and gives you a strategy choice before importing.
4. **Test source priority** — Go to Settings, drag-and-drop source ordering should work.
5. **Test source migration** — Go to `/source_migrations` for the health dashboard.

### What Was Built This Session
- Protobuf schema + parser for Mihon/Tachiyomi backups
- Bidirectional source ID mapping (38 Tachiyomi IDs ↔ 25 Scanarr keys)
- Full round-trip import/export (.tachibk files)
- Background job for web imports with Turbo Stream progress
- CLI rake tasks with preview/confirmation for import, export, and inspect
- Source migration wizard + health dashboard
- Source priority drag-and-drop in Settings
- Automatic stale source skipping in chapter check jobs
- `publishing_finished` and `licensed` status values
- 34 new tests, all passing

### Known Issues
- The 5 "unknown" source IDs have no name in the backup metadata. URL patterns suggest they're aggregator sites but need manual identification.
- Existing series already had all their chapters, so the import didn't create new data. To fully test the import with NEW data, you'd need manga from a source that isn't already in your Scanarr library.
