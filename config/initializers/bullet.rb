# frozen_string_literal: true

if defined?(Bullet) && (Rails.env.development? || Rails.env.test?)
  Rails.application.configure do
    config.after_initialize do
      Bullet.enable = true
      Bullet.alert = false # Don't show JS alerts
      Bullet.bullet_logger = true
      Bullet.console = true # Log to browser console
      Bullet.rails_logger = true
      Bullet.add_footer = true # Add footer to HTML pages

      # Only raise on actual N+1 queries in tests, not unused eager loading
      # (unused eager loading can be false positives with sparse test fixtures)
      Bullet.raise = Rails.env.test?

      # Detect N+1 queries
      Bullet.n_plus_one_query_enable = true

      # Disable unused eager loading detection in tests (too many false positives)
      Bullet.unused_eager_loading_enable = Rails.env.development?

      # Detect counter cache
      Bullet.counter_cache_enable = false

      # Whitelist ActiveStorage internal queries (variant_records is internal)
      Bullet.add_safelist type: :n_plus_one_query, class_name: "ActiveStorage::Blob", association: :variant_records
    end
  end
end
