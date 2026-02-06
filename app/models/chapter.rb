class Chapter < ApplicationRecord
  include HasPublicId

  belongs_to :series, counter_cache: true
  belongs_to :volume, optional: true
  belongs_to :source, optional: true
  has_many :releases, dependent: :destroy
  has_many :chapter_progresses, dependent: :destroy
  has_many :new_chapter_notifications, dependent: :destroy

  validates :chapter_number, presence: true
  before_validation :set_chapter_number_value

  # Returns true if the title is meaningful (not just "Chapter X")
  def meaningful_title?
    return false if title.blank?

    # Title is not meaningful if it just matches "Chapter X" pattern
    !title.strip.match?(/\Achapter\s*#{Regexp.escape(chapter_number.to_s)}\z/i)
  end

  # Returns the title only if it's meaningful, otherwise nil
  def display_title
    meaningful_title? ? title : nil
  end

  private

  def set_chapter_number_value
    numeric = extract_numeric_value(chapter_number) || extract_numeric_value(title)
    self.chapter_number_value = numeric ? BigDecimal(numeric) : nil
  end

  def extract_numeric_value(text)
    text.to_s[/\d+(\.\d+)?/]
  end
end
