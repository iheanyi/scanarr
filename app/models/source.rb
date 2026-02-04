class Source < ApplicationRecord
  has_many :series_sources, dependent: :destroy
  has_many :series, through: :series_sources
  has_many :chapters, dependent: :nullify
  has_many :releases, dependent: :nullify
  has_many :scraper_runs, dependent: :destroy

  validates :key, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true

  before_validation :generate_slug_from_key

  # Calculate reliability score based on recent scraper run success rate
  # Returns a decimal between 0.0 and 1.0
  def reliability_score
    recent_runs = scraper_runs.where("created_at > ?", 30.days.ago)
    return 0.5 if recent_runs.empty? # Default to neutral if no history

    successful = recent_runs.where(status: "success").count
    total = recent_runs.count

    (successful.to_f / total).round(2)
  end

  private

  def generate_slug_from_key
    self.slug = key.to_s.tr("_", "-") if key.present? && (slug.blank? || key_changed?)
  end
end
