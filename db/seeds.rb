# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Seed manga sources
[
  { key: "mangadex", name: "MangaDex", base_url: "https://api.mangadex.org", source_type: "api", default_priority: 10, enabled: true },
  { key: "weeb_central", name: "Weeb Central", base_url: "https://weebcentral.com", source_type: "html", default_priority: 20, enabled: true },
  { key: "manga_see", name: "MangaSee", base_url: "https://mangasee123.com", source_type: "html", default_priority: 30, enabled: true },
  { key: "asura_scans", name: "Asura Scans", base_url: "https://asuracomic.net", source_type: "html", default_priority: 40, enabled: true },
  { key: "manga_pill", name: "MangaPill", base_url: "https://mangapill.com", source_type: "html", default_priority: 50, enabled: true },
  { key: "comick", name: "Comick", base_url: "https://comick.live", source_type: "api", default_priority: 15, enabled: true },
  { key: "tcb_scans", name: "TCB Scans", base_url: "https://tcbonepiecechapters.com", source_type: "html", default_priority: 55, enabled: true },
  { key: "manga_kakalot", name: "MangaKakalot", base_url: "https://www.mangakakalot.gg", source_type: "html", default_priority: 60, enabled: true },
  { key: "flame_comics", name: "Flame Comics", base_url: "https://flamecomics.xyz", source_type: "api", default_priority: 65, enabled: true },
  { key: "batoto", name: "BatoTo", base_url: "https://bato.to", source_type: "html", default_priority: 70, enabled: true },
  { key: "manga_here", name: "MangaHere", base_url: "https://www.mangahere.cc", source_type: "html", default_priority: 75, enabled: true },
  { key: "manga_clash", name: "MangaClash", base_url: "https://toonclash.com", source_type: "html", default_priority: 80, enabled: true },
  { key: "manga_buddy", name: "MangaBuddy", base_url: "https://mangabuddy.com", source_type: "html", default_priority: 85, enabled: true },
  { key: "zero_scans", name: "Zero Scans", base_url: "https://zscans.com", source_type: "api", default_priority: 90, enabled: true },
  { key: "manhua_plus", name: "ManhuaPlus", base_url: "https://manhuaplus.com", source_type: "html", default_priority: 95, enabled: true },
  { key: "isekai_scan", name: "IsekaiScan", base_url: "https://isekaiscan.top", source_type: "html", default_priority: 100, enabled: true },
  { key: "toonily", name: "Toonily", base_url: "https://toonily.me", source_type: "html", default_priority: 105, enabled: true },
  { key: "drake_scans", name: "Drake Scans", base_url: "https://drakecomic.org", source_type: "html", default_priority: 110, enabled: true },
  { key: "like_manga", name: "LikeManga", base_url: "https://likemanga.ink", source_type: "html", default_priority: 115, enabled: true },
  { key: "manga_freak", name: "MangaFreak", base_url: "https://ww2.mangafreak.me", source_type: "html", default_priority: 120, enabled: true },
  { key: "manga_read", name: "MangaRead", base_url: "https://www.mangaread.org", source_type: "html", default_priority: 125, enabled: true },
  { key: "manga_geko", name: "MangaGeko", base_url: "https://www.mgeko.cc", source_type: "html", default_priority: 130, enabled: true },
  { key: "manhwa18", name: "Manhwa18", base_url: "https://manhwa18.net", source_type: "html", default_priority: 135, enabled: true },
  { key: "manga_nato", name: "MangaNato", base_url: "https://natomanga.com", source_type: "html", default_priority: 140, enabled: true },
  { key: "manga_fire", name: "MangaFire", base_url: "https://mangafire.to", source_type: "html", default_priority: 145, enabled: true }
].each do |attrs|
  Source.find_or_create_by!(key: attrs[:key]) do |source|
    source.name = attrs[:name]
    source.base_url = attrs[:base_url]
    source.source_type = attrs[:source_type]
    source.default_priority = attrs[:default_priority]
    source.enabled = attrs[:enabled]
  end
end

puts "Seeded #{Source.count} sources"
