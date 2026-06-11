# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Seed manga sources from config/sources/manifest.yml
sync = Sources::SyncService.new.call
puts "Synced sources from manifest: #{sync.created.size} created, #{sync.updated.size} updated, #{sync.unchanged.size} unchanged"

if Rails.env.development? && ENV.fetch("SCANARR_SEED_DEV_USER", "1") == "1"
  dev_username = ENV.fetch("SCANARR_DEV_USERNAME", "perfuser")
  dev_email = ENV.fetch("SCANARR_DEV_EMAIL", "perfuser@local.scanarr")
  dev_password = ENV.fetch("SCANARR_DEV_PASSWORD", "password123")

  user = User.find_or_initialize_by(username: dev_username)
  user.email = dev_email
  user.password = dev_password if user.new_record? || user.password_digest.blank?
  user.role = :admin if user.respond_to?(:role)
  user.save!

  puts "Seeded development user: #{dev_username} (override with SCANARR_DEV_* env vars)"
end
