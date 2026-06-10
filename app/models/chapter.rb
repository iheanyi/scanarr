class Chapter < ApplicationRecord
  include HasPublicId

  belongs_to :series, counter_cache: true
  belongs_to :volume, optional: true
  belongs_to :source, optional: true
  has_many :releases, dependent: :destroy
  has_many :chapter_progresses, dependent: :destroy
  has_many :offline_manifest_entries, class_name: "UserOfflineManifestEntry", dependent: :destroy
  has_many :new_chapter_notifications, dependent: :destroy

  validates :chapter_number, presence: true
  before_validation :normalize_chapter_number
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

  def normalize_chapter_number
    raw_number = chapter_number.to_s.strip
    return if raw_number.blank?

    self.chapter_number = normalized_numeric_chapter_number(raw_number) || raw_number
  end

  def set_chapter_number_value
    numeric = extract_numeric_value(chapter_number) || extract_numeric_value(title)
    self.chapter_number_value = numeric ? BigDecimal(numeric) : nil
  end

  def extract_numeric_value(text)
    value = text.to_s
    value[/\b(?:chapter|ch\.?)\s*[-:#]?\s*(\d+(\.\d+)?)/i, 1] || value[/\d+(\.\d+)?/]
  end

  def normalized_numeric_chapter_number(raw_number)
    return unless raw_number.match?(/\A\d+(\.\d+)?\z/)

    decimals = raw_number.split(".", 2).last if raw_number.include?(".")
    return raw_number unless decimals&.length.to_i > 3

    title_number = extract_numeric_value(title)
    return title_number if title_number.present? && same_chapter_number?(raw_number, title_number)

    trim_decimal(BigDecimal(raw_number).round(3).to_s("F"))
  rescue ArgumentError
    nil
  end

  def same_chapter_number?(left, right)
    BigDecimal(left).round(3) == BigDecimal(right).round(3)
  rescue ArgumentError
    false
  end

  def trim_decimal(number)
    number.sub(/\.?0+\z/, "")
  end
end
