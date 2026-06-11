class ClearSeedOwnedMatureCapabilityFlags < ActiveRecord::Migration[8.1]
  # Pre-manifest seeds wrote capabilities: { mature_content: true } into
  # source rows. The capabilities column is operator-owned now, so on
  # upgraded installs those seed-era values would masquerade as operator
  # overrides and pin a future manifest correction forever. A stored true
  # that matches the manifest's declaration is redundant (the runtime
  # fallback supplies it), so drop exactly that; explicit operator values
  # that differ from the manifest are untouched.
  SEEDED_MATURE_KEYS = %w[toonily manhwa18].freeze

  def up
    execute <<~SQL.squish
      UPDATE sources
      SET capabilities = capabilities - 'mature_content'
      WHERE key IN (#{SEEDED_MATURE_KEYS.map { |k| quote(k) }.join(', ')})
        AND capabilities IS NOT NULL
        AND capabilities->>'mature_content' = 'true'
    SQL

    execute <<~SQL.squish
      UPDATE sources
      SET capabilities = NULL
      WHERE capabilities = '{}'::jsonb
    SQL
  end

  def down
    # Removing redundant data; nothing to restore.
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
