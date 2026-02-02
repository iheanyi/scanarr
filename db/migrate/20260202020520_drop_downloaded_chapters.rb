class DropDownloadedChapters < ActiveRecord::Migration[8.1]
  def change
    drop_table :downloaded_chapters, if_exists: true
  end
end
