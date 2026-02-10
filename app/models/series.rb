class Series < ApplicationRecord
  include HasPublicId

  before_validation :generate_slug, on: :create
  before_validation :update_slug_if_title_changed, on: :update
  after_create :auto_link_library_series

  belongs_to :library_series, optional: true
  has_many :volumes, dependent: :destroy
  has_many :chapters, dependent: :destroy
  has_many :series_sources, dependent: :destroy
  has_many :sources, through: :series_sources
  has_one_attached :cover

  validates :canonical_title, presence: true

  def display_author
    return nil if author_name.blank? && artist_name.blank?

    # If same person or only one is set, show just that name
    if author_name.blank?
      artist_name
    elsif artist_name.blank? || author_name == artist_name
      author_name
    else
      # Different author and artist - show both
      "#{author_name} (Art: #{artist_name})"
    end
  end

  # Returns the cover image URL - prefers local attachment, falls back to remote URL
  def cover_image_url
    return cover_url unless cover.attached?

    url_helpers = Rails.application.routes.url_helpers

    if url_helpers.respond_to?(:rails_blob_path)
      url_helpers.rails_blob_path(cover, only_path: true)
    elsif url_helpers.respond_to?(:rails_storage_proxy_path)
      url_helpers.rails_storage_proxy_path(cover, only_path: true)
    else
      cover_url
    end
  end

  # Returns download progress stats for this series
  # NOTE: For best performance, ensure chapters are preloaded with:
  #   series.chapters.includes(releases: :file_asset)
  def download_progress
    @download_progress ||= begin
      stats = { total: 0, downloaded: 0, downloading: 0, queued: 0, failed: 0 }

      # Use preloaded data if available, otherwise query efficiently
      chaps = chapters.loaded? ? chapters : chapters.includes(releases: :file_asset)

      chaps.each do |chapter|
        stats[:total] += 1
        # Use preloaded releases if available
        file_asset = chapter.releases.first&.file_asset
        next unless file_asset

        case file_asset.download_status
        when "complete"
          stats[:downloaded] += 1
        when "downloading"
          stats[:downloading] += 1
        when "queued", "pending"
          stats[:queued] += 1
        when "failed", "cancelled"
          stats[:failed] += 1
        end
      end

      stats
    end
  end

  # Returns the primary source for this series (first added)
  # Uses preloaded data when available to avoid N+1 queries
  def primary_source
    @primary_source ||= if sources.loaded?
      sources.min_by(&:id)
    else
      sources.order(:id).first
    end
  end

  # Returns the series source for the primary source
  # Uses preloaded data when available to avoid N+1 queries
  def primary_series_source
    @primary_series_source ||= if series_sources.loaded?
      series_sources.min_by(&:id)
    else
      series_sources.order(:id).first
    end
  end

  # Calculates and updates the quality score for this series
  # Based on: chapter count, chapter completeness, and source reliability
  def calculate_quality_score
    chapter_score = chapters.count * 10
    gap_penalty = calculate_chapter_gaps * -5
    reliability = primary_source&.reliability_score.to_f * 20

    new_score = [ chapter_score + gap_penalty + reliability, 0 ].max
    update!(quality_score: new_score.round(2))
    new_score
  end

  # Ensures this series is linked to a LibrarySeries, creating one if needed
  def ensure_library_series!
    return library_series if library_series.present?

    # Try to find existing LibrarySeries by title
    ls = LibrarySeries.find_or_create_by!(canonical_title: canonical_title) do |record|
      record.cover_url = cover_url
      record.status = status_to_enum
    end

    update!(library_series: ls)
    ls
  end

  # Override to_param for pretty URLs: /public_id-slug
  def to_param
    "#{public_id}-#{slug}"
  end

  # Class method to find by public_id from URL param (ignores slug portion).
  # Falls back to slug lookup so bare slugs like "lookism" also work.
  def self.find_by_param!(param)
    public_id = param.to_s.split("-").first
    find_by_public_id(public_id) || find_by!(slug: param.to_s)
  end

  private

  def generate_slug
    return if slug.present?

    base_slug = canonical_title.to_s.parameterize.presence || "untitled"
    candidate = base_slug

    # Find a unique slug by appending a number if needed
    counter = 1
    while self.class.exists?(slug: candidate)
      counter += 1
      candidate = "#{base_slug}-#{counter}"
    end

    self.slug = candidate
  end

  def update_slug_if_title_changed
    return unless canonical_title_changed? && canonical_title.present?

    base_slug = canonical_title.parameterize
    candidate = base_slug

    # Find a unique slug by appending a number if needed (excluding self)
    counter = 1
    while self.class.where.not(id: id).exists?(slug: candidate)
      counter += 1
      candidate = "#{base_slug}-#{counter}"
    end

    self.slug = candidate
  end

  # Count gaps in chapter numbering (e.g., missing chapters between 1 and 10)
  def calculate_chapter_gaps
    numbers = chapters.pluck(:chapter_number_value).compact.sort
    return 0 if numbers.length < 2

    gaps = 0
    numbers.each_cons(2) do |a, b|
      # Count significant gaps (more than 1.5 chapters apart)
      gap = b - a
      gaps += 1 if gap > 1.5
    end
    gaps
  end

  # Convert string status to LibrarySeries enum value
  def status_to_enum
    case status&.downcase
    when "ongoing", "publishing"
      :ongoing
    when "completed", "finished"
      :completed
    when "publishing_finished", "pub_finished"
      :publishing_finished
    when "licensed"
      :licensed
    when "hiatus"
      :hiatus
    when "cancelled", "canceled"
      :cancelled
    else
      :ongoing
    end
  end

  # Auto-link to LibrarySeries on creation
  def auto_link_library_series
    return if library_series_id.present?

    ensure_library_series!
  rescue StandardError => e
    Rails.logger.warn "Failed to auto-link LibrarySeries for #{canonical_title}: #{e.message}"
  end
end
