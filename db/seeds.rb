# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Seed manga sources
[
  { key: "mangadex", name: "MangaDex", base_url: "https://api.mangadex.org", source_type: "api", default_priority: 10, enabled: true },
  { key: "weeb_central", name: "Weeb Central", base_url: "https://weebcentral.com", source_type: "html", default_priority: 20, enabled: true },
  { key: "manga_see", name: "MangaSee", base_url: "https://mangasee123.com", source_type: "html", default_priority: 30, enabled: true },
  { key: "asura_scans", name: "Asura Scans", base_url: "https://asuracomic.net", source_type: "html", default_priority: 40, enabled: true },
  { key: "manga_pill", name: "MangaPill", base_url: "https://mangapill.com", source_type: "html", default_priority: 50, enabled: true }
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
