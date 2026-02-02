class Chapter < ApplicationRecord
  include PublicIdGenerator

  belongs_to :series
  belongs_to :volume, optional: true
  belongs_to :source, optional: true
  has_many :releases, dependent: :destroy

  validates :chapter_number, presence: true
  before_validation :set_chapter_number_value

  def to_param
    public_id
  end

  private

  def set_chapter_number_value
    value = chapter_number.to_s.strip
    self.chapter_number_value = if value.match?(/\A\d+(\.\d+)?\z/)
                                  BigDecimal(value)
    else
                                  nil
    end
  end
end
