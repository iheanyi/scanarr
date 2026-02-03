class LibrarySeries < ApplicationRecord
  include HasPublicId

  before_validation :generate_slug, on: :create
  before_validation :update_slug_if_title_changed, on: :update

  has_many :series, dependent: :nullify
  has_many :user_series_follows, dependent: :destroy
  has_many :followers, through: :user_series_follows, source: :user

  validates :canonical_title, presence: true

  enum :status, { ongoing: 0, completed: 1, hiatus: 2, cancelled: 3 }

  # Override to_param for pretty URLs: /public_id-slug
  def to_param
    "#{public_id}-#{slug}"
  end

  # Class method to find by public_id from URL param (ignores slug portion)
  def self.find_by_param!(param)
    public_id = param.to_s.split("-").first
    find_by_public_id!(public_id)
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
end
