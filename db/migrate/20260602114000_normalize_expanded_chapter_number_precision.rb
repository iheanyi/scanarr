class NormalizeExpandedChapterNumberPrecision < ActiveRecord::Migration[8.1]
  class MigrationChapter < ApplicationRecord
    self.table_name = "chapters"
  end

  def up
    updated = 0
    skipped = 0

    say_with_time "Normalizing expanded chapter number precision" do
      MigrationChapter
        .where("chapter_number ~ ?", "^[0-9]+(\\.[0-9]{4,})$")
        .find_each do |chapter|
          canonical_number = canonical_chapter_number(chapter.chapter_number, chapter.title)
          next if canonical_number.blank? || canonical_number == chapter.chapter_number

          if conflicts_with_existing_chapter?(chapter, canonical_number)
            skipped += 1
            next
          end

          chapter.update_columns(
            chapter_number: canonical_number,
            chapter_number_value: BigDecimal(canonical_number).round(3),
            updated_at: Time.current
          )
          updated += 1
        end
    end

    say "Normalized #{updated} chapter numbers; skipped #{skipped} conflicting rows"
  end

  def down
    # Irreversible cleanup: the expanded float strings were invalid display keys.
  end

  private

  def canonical_chapter_number(raw_number, title)
    title_number = extract_numeric_value(title)
    return title_number if title_number.present? && same_chapter_number?(raw_number, title_number)

    trim_decimal(BigDecimal(raw_number).round(3).to_s("F"))
  rescue ArgumentError
    nil
  end

  def extract_numeric_value(text)
    value = text.to_s
    value[/\b(?:chapter|ch\.?)\s*[-:#]?\s*(\d+(\.\d+)?)/i, 1] || value[/\d+(\.\d+)?/]
  end

  def same_chapter_number?(left, right)
    BigDecimal(left).round(3) == BigDecimal(right).round(3)
  rescue ArgumentError
    false
  end

  def trim_decimal(number)
    number.sub(/\.?0+\z/, "")
  end

  def conflicts_with_existing_chapter?(chapter, canonical_number)
    MigrationChapter
      .where(
        series_id: chapter.series_id,
        chapter_number: canonical_number,
        language: chapter.language,
        group: chapter.group
      )
      .where.not(id: chapter.id)
      .exists?
  end
end
