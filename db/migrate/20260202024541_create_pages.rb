class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.references :file_asset, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :source_url

      t.timestamps
    end

    add_index :pages, [ :file_asset_id, :position ], unique: true
  end
end
