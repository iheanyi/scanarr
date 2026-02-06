class AddCheckIntervalToUserSeriesFollows < ActiveRecord::Migration[8.1]
  def change
    add_column :user_series_follows, :check_interval_minutes, :integer
  end
end
