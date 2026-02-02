class BackfillChapterNumberValueFromTitles < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE chapters
      SET chapter_number_value = CASE
        WHEN chapter_number ~ '\\d' THEN substring(chapter_number FROM '(\\d+(\\.\\d+)?)')::decimal
        WHEN title ~ '\\d' THEN substring(title FROM '(\\d+(\\.\\d+)?)')::decimal
        ELSE NULL
      END
    SQL
  end

  def down
    execute <<~SQL
      UPDATE chapters
      SET chapter_number_value = CASE
        WHEN chapter_number ~ '^[0-9]+(\\.[0-9]+)?$' THEN chapter_number::decimal
        ELSE NULL
      END
    SQL
  end
end
