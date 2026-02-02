class AddChapterNumberValueToChapters < ActiveRecord::Migration[8.1]
  def up
    add_column :chapters, :chapter_number_value, :decimal, precision: 12, scale: 3

    execute <<~SQL
      UPDATE chapters
      SET chapter_number_value = CASE
        WHEN chapter_number ~ '^[0-9]+(\\.[0-9]+)?$' THEN chapter_number::decimal
        ELSE NULL
      END
    SQL

    add_index :chapters,
              [ :series_id, :source_id, :chapter_number_value ],
              name: "index_chapters_on_series_source_number_value"
  end

  def down
    remove_index :chapters, name: "index_chapters_on_series_source_number_value"
    remove_column :chapters, :chapter_number_value
  end
end
