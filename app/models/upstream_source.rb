# Mirror of one source entry from the keiyoushi (Mihon/Tachiyomi community)
# extensions index. Read-only catalog data: rows are written exclusively by
# Sources::UpstreamCatalogService and never drive scraping by themselves.
class UpstreamSource < ApplicationRecord
  validates :mihon_id, presence: true, uniqueness: true
  validates :name, :lang, :last_seen_at, presence: true

  scope :english, -> { where(lang: %w[en all]) }
end
