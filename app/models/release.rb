class Release < ApplicationRecord
  include PublicIdGenerator

  belongs_to :chapter
  belongs_to :source, optional: true
  has_one :file_asset, dependent: :destroy

  def to_param
    public_id
  end
end
