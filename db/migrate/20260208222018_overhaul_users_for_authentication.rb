class OverhaulUsersForAuthentication < ActiveRecord::Migration[8.1]
  def change
    # Add new authentication columns
    add_column :users, :password_digest, :string
    add_column :users, :username, :string
    add_column :users, :api_key, :string
    add_column :users, :role, :integer, default: 0, null: false

    add_index :users, :username, unique: true
    add_index :users, :api_key, unique: true

    # Drop unused Devise columns and indexes
    remove_index :users, :reset_password_token
    remove_index :users, :confirmation_token

    remove_column :users, :encrypted_password, :string
    remove_column :users, :reset_password_token, :string
    remove_column :users, :reset_password_sent_at, :datetime
    remove_column :users, :remember_created_at, :datetime
    remove_column :users, :confirmation_token, :string
    remove_column :users, :confirmed_at, :datetime
    remove_column :users, :confirmation_sent_at, :datetime
    remove_column :users, :unconfirmed_email, :string
  end
end
