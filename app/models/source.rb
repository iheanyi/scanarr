class Source < ApplicationRecord
  has_many :series_sources, dependent: :destroy
  has_many :series, through: :series_sources
  has_many :chapters, dependent: :nullify
  has_many :releases, dependent: :nullify

  validates :key, presence: true, uniqueness: true

  # Returns a URL-friendly slug derived from the key
  def slug
    key.to_s.tr("_", "-")
  end
end
