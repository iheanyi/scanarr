class CreateBackupRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :backup_records do |t|
      t.string :filename, null: false
      t.string :path
      t.bigint :size
      t.string :checksum
      t.string :backup_type, null: false  # scheduled, manual, pre_restore, pre_import
      t.string :status, null: false, default: "pending" # pending, complete, failed
      t.text :error_message
      t.timestamps
    end

    add_index :backup_records, :created_at
    add_index :backup_records, :backup_type
    add_index :backup_records, :status
  end
end
