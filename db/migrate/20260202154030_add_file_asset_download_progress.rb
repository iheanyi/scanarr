class AddFileAssetDownloadProgress < ActiveRecord::Migration[8.1]
  def change
    add_column :file_assets, :download_status, :string, default: "pending", null: false
    add_column :file_assets, :pages_expected, :integer
    add_column :file_assets, :pages_downloaded, :integer, default: 0, null: false
    add_column :file_assets, :download_error, :text
    add_index :file_assets, :download_status
  end
end
