class FileAsset < ApplicationRecord
  include PublicIdGenerator

  ORPHANED_BLOBS_ERROR = "Orphaned: blob files missing from storage (detected by cleanup job)".freeze

  belongs_to :release
  has_many :pages, dependent: :destroy
  has_one_attached :archive

  def to_param
    public_id
  end
end
