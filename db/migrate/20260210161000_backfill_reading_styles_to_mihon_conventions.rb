class BackfillReadingStylesToMihonConventions < ActiveRecord::Migration[8.1]
  class Series < ApplicationRecord
    self.table_name = "series"
  end

  class User < ApplicationRecord
    self.table_name = "users"
  end

  def up
    backfill_series_reading_styles
    backfill_user_default_reading_styles
  end

  def down
    # Irreversible: legacy values collapse into canonical values.
  end

  private

  def backfill_series_reading_styles
    say_with_time("Backfilling series reading_style values") do
      updated = 0
      updated += Series.where(reading_style: %w[long_strip continuous_vertical]).update_all(reading_style: "webtoon")
      updated += Series.where(reading_style: %w[webcomic vertical_paged]).update_all(reading_style: "vertical")
      updated
    end
  end

  def backfill_user_default_reading_styles
    say_with_time("Backfilling user default_reading_style preferences") do
      updated = 0

      User.find_each do |user|
        prefs = user.preferences.is_a?(Hash) ? user.preferences.deep_dup : {}
        raw_style = prefs["default_reading_style"] || prefs[:default_reading_style]
        next if raw_style.blank?

        normalized_style = ReadingStyles.normalize(raw_style)
        next if normalized_style == raw_style

        prefs["default_reading_style"] = normalized_style
        user.update_columns(preferences: prefs, updated_at: Time.current)
        updated += 1
      end

      updated
    end
  end
end
