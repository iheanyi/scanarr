class DropSolidCacheEntries < ActiveRecord::Migration[8.1]
  def change
    drop_table :solid_cache_entries, if_exists: true
  end
end
