class AddChaptersCountToSeries < ActiveRecord::Migration[8.1]
  def up
    add_column :series, :chapters_count, :integer, default: 0, null: false

    # Backfill existing counts
    Series.reset_column_information
    Series.find_each do |s|
      Series.reset_counters(s.id, :chapters)
    end
  end

  def down
    remove_column :series, :chapters_count
  end
end
