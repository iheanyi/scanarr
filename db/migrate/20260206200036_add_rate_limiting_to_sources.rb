class AddRateLimitingToSources < ActiveRecord::Migration[8.1]
  def change
    add_column :sources, :rate_limited_until, :datetime
  end
end
