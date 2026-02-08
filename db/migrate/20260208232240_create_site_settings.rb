class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      t.boolean :registration_enabled, default: true, null: false

      t.timestamps
    end
  end
end
