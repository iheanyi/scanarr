class SeriesSource < ApplicationRecord
  belongs_to :series
  belongs_to :source
end
