class Chapter < ApplicationRecord
  include HasPublicId

  belongs_to :series
  belongs_to :volume, optional: true
  belongs_to :source, optional: true
  has_many :releases, dependent: :destroy
  has_many :chapter_progresses, dependent: :destroy

  validates :chapter_number, presence: true
  before_validation :set_chapter_number_value

  private

  def set_chapter_number_value
    numeric = extract_numeric_value(chapter_number) || extract_numeric_value(title)
    self.chapter_number_value = numeric ? BigDecimal(numeric) : nil
  end

  def extract_numeric_value(text)
    text.to_s[/\d+(\.\d+)?/]
  end
end
