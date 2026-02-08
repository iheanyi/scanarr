class Page < ApplicationRecord
  belongs_to :file_asset

  has_one_attached :image

  validates :position, presence: true, uniqueness: { scope: :file_asset_id }

  DISPLAY_VARIANT_OPTIONS = {
    resize_to_limit: [ 1400, nil ],
    format: :webp,
    saver: { quality: 82 }
  }.freeze

  # Returns an optimized variant for display in the reader.
  # Resizes to max 1400px wide and converts to WebP for dramatically smaller file sizes.
  # A typical manga page goes from ~3-8MB PNG to ~100-300KB WebP.
  # Animated GIFs are returned as-is to preserve animation.
  # Falls back to the original image if variant processing is unavailable.
  def display_image
    return image unless image.attached?
    return image if image.blob.content_type == "image/gif"
    return image unless self.class.variant_processing_available?

    image.variant(DISPLAY_VARIANT_OPTIONS)
  end

  # Pre-processes the display variant so it's ready before a user opens the chapter.
  # Called from DownloadChapterJob after each page is attached.
  def preprocess_display_variant!
    return unless image.attached?
    return if image.blob.content_type == "image/gif"
    return unless self.class.variant_processing_available?

    image.variant(DISPLAY_VARIANT_OPTIONS).processed
  end

  def self.variant_processing_available?
    return @variant_processing_available if defined?(@variant_processing_available)

    @variant_processing_available = begin
      require "vips"
      true
    rescue LoadError
      Rails.logger.info "Page: libvips not available, serving original images. Install with: brew install vips"
      false
    end
  end
end
