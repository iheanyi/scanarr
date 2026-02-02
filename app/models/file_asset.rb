class FileAsset < ApplicationRecord
  include PublicIdGenerator

  belongs_to :release
  has_many :pages, dependent: :destroy
  has_one_attached :archive

  def to_param
    public_id
  end
end
