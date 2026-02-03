class Series < ApplicationRecord
  extend FriendlyId
  include PublicIdGenerator

  friendly_id :canonical_title, use: :slugged

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
    if cover.attached?
      Rails.application.routes.url_helpers.rails_blob_path(cover, only_path: true)
    else
      cover_url
    end
  end
end
