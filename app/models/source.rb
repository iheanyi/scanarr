class Source < ApplicationRecord
  has_many :series_sources, dependent: :destroy
  has_many :series, through: :series_sources
  has_many :chapters, dependent: :nullify
  has_many :releases, dependent: :nullify

  validates :key, presence: true, uniqueness: true
end
