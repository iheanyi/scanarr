class Volume < ApplicationRecord
  belongs_to :series
  has_many :chapters, dependent: :nullify
end
