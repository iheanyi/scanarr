# frozen_string_literal: true

# Add proper slug column to sources instead of computing it from key every time.
# Slug is the URL-friendly version (dashes), key is the internal identifier (underscores).
#
class AddSlugToSources < ActiveRecord::Migration[8.1]
  def up
    add_column :sources, :slug, :string

    # Populate slug from existing key values (underscores -> dashes)
    execute <<~SQL
      UPDATE sources SET slug = REPLACE(key, '_', '-')
    SQL

    change_column_null :sources, :slug, false
    add_index :sources, :slug, unique: true
  end

  def down
    remove_index :sources, :slug
    remove_column :sources, :slug
  end
end
