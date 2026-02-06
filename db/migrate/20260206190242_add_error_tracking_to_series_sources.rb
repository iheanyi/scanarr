class AddErrorTrackingToSeriesSources < ActiveRecord::Migration[8.1]
  def change
    add_column :series_sources, :last_check_error, :text
    add_column :series_sources, :last_check_error_at, :datetime
    add_column :series_sources, :consecutive_failures, :integer, default: 0, null: false
  end
end
