class Page < ApplicationRecord
  belongs_to :file_asset

  has_one_attached :image

  validates :position, presence: true, uniqueness: { scope: :file_asset_id }
end
