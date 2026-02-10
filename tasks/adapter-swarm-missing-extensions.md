# Adapter Swarm Backlog (extensions-source + extensions)

Last audited: 2026-02-10

This backlog tracks **missing adapters** by reconciling:
- `keiyoushi/extensions-source` (Kotlin extension implementation directories)
- `keiyoushi/extensions` index (`index.min.json`, live source IDs and NSFW metadata)
- our local mapping in `config/tachiyomi_source_map.yml`

## Coverage Snapshot

- Registered Scanarr adapters: `25`
- Active missing adapter targets (`future_sources`): `21`
- Retired/unavailable IDs (`retired_sources`): `3`

## Active Missing Adapter Targets

| Key | Tachiyomi Source ID | extensions pkg | extensions-source dir | NSFW |
|-----|----------------------|----------------|------------------------|------|
| `manga_plus` | `1998944621602463790` | `eu.kanade.tachiyomi.extension.all.mangaplus` | `src/all/mangaplus` | no |
| `manga_katana` | `3170561626848540385` | `eu.kanade.tachiyomi.extension.en.mangakatana` | `src/en/mangakatana` | no |
| `mangabat` | `4215511432986138970` | `eu.kanade.tachiyomi.extension.en.mangabat` | `src/en/mangabat` | yes |
| `manga_fox` | `6484561431658238800` | `eu.kanade.tachiyomi.extension.en.mangafox` | `src/en/mangafox` | yes |
| `manga_reader` | `789561949979941461` | `eu.kanade.tachiyomi.extension.all.mangareaderto` | `src/en/mangareadercc` | yes |
| `hive_scans` | `6311653253665366075` | `eu.kanade.tachiyomi.extension.en.infernalvoidscans` | `src/en/hiveworks` | no |
| `manga_plus_creators` | `4994699950662723787` | `eu.kanade.tachiyomi.extension.all.mangapluscreators` | `src/all/mangapluscreators` | no |
| `death_toll_scans` | `4722346859737894698` | `eu.kanade.tachiyomi.extension.en.deathtollscans` | `src/en/deathtollscans` | no |
| `raven_scans` | `5160001879976399540` | `eu.kanade.tachiyomi.extension.en.ravenscans` | `src/en/ravenscans` | yes |
| `manga_hub` | `4758858684982406533` | `eu.kanade.tachiyomi.extension.en.mangahubio` | `src/en/mangahubio` | yes |
| `dynasty_scans` | `669095474988166464` | `eu.kanade.tachiyomi.extension.en.dynasty` | `src/en/dynasty` | yes |
| `webtoons` | `2522335540328470744` | `eu.kanade.tachiyomi.extension.all.webtoons` | `src/all/webtoons` | no |
| `all_manga` | `4709139914729853090` | `eu.kanade.tachiyomi.extension.en.allanime` | `src/en/allanime` | no |
| `coffee_manga` | `7570643086791062929` | `eu.kanade.tachiyomi.extension.en.coffeemanga` | `src/en/coffeemanga` | yes |
| `mangamo` | `6458420328066857684` | `eu.kanade.tachiyomi.extension.en.mangamo` | `src/en/mangamo` | no |
| `k_manga` | `8143442163119480220` | `eu.kanade.tachiyomi.extension.en.kmanga` | `src/en/kmanga` | no |
| `azuki` | `5983175010393979119` | `eu.kanade.tachiyomi.extension.en.azuki` | `src/en/azuki` | yes |
| `manga_up` | `7689478295161479290` | `eu.kanade.tachiyomi.extension.all.mangaup` | `src/all/mangaup` | no |
| `cubari` | `6338219619148105941` | `eu.kanade.tachiyomi.extension.all.cubari` | `src/all/cubari` | no |
| `global_comix` | `1702911211040495914` | `eu.kanade.tachiyomi.extension.all.globalcomix` | `src/all/globalcomix` | yes |
| `hiperdex` | `3064755045370217842` | `eu.kanade.tachiyomi.extension.en.hiperdex` | `src/en/hiperdex` | yes |

## Retired / Deprioritized IDs

These IDs are still recognized by `TachiyomiSourceMapper#known?` for import diagnostics, but are not active swarm targets:

| Key | Tachiyomi Source ID | Reason |
|-----|----------------------|--------|
| `manga_park` | `2292947733994124621` | Not present in current `keiyoushi/extensions` index |
| `manga_kakalots` | `9193816653713258037` | Not present in current `keiyoushi/extensions` index |
| `infernal_void_scans` | `6422096666751316291` | Legacy ID replaced by active `hive_scans` mapping |

## Suggested Swarm Order

1. **High-demand from backups first**: `manga_katana`, `mangabat`, `manga_plus`, `manga_fox`, `manga_reader`
2. **Platform/API sources**: `webtoons`, `manga_up`, `mangamo`, `k_manga`, `azuki`, `cubari`
3. **Long tail / scans**: `manga_hub`, `all_manga`, `global_comix`, `hiperdex`, `dynasty_scans`, `hive_scans`

## Implementation Rules for New Adapters

- Every new adapter must include `test/scrapers/<key>_adapter_test.rb`
- Add key to `Scrapers::AdapterRegistry::ADAPTERS`
- Add source config entry in `config/sources.yml`
- Add seed entry in `db/seeds.rb`
- Add Tachiyomi ID mapping in `config/tachiyomi_source_map.yml` (`sources` + `export_ids`)
