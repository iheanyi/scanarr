class AddAdapterVersioningAndHealthToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :adapter_version, :integer, default: 0, null: false
    add_column :sources, :adapter_version_synced_at, :datetime
    add_column :sources, :health_status, :string, default: "healthy", null: false
    add_column :sources, :health_changed_at, :datetime
    add_index :sources, :health_status

    remove_column :sources, :api_version, :string
  end
end
