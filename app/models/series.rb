class Series < ApplicationRecord
  extend FriendlyId
  include PublicIdGenerator

  friendly_id :canonical_title, use: :slugged

  has_many :volumes, dependent: :destroy
  has_many :chapters, dependent: :destroy
  has_many :series_sources, dependent: :destroy
  has_many :sources, through: :series_sources

  validates :canonical_title, presence: true
end
