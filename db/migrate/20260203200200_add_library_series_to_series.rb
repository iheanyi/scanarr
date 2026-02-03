class AddLibrarySeriesToSeries < ActiveRecord::Migration[8.1]
  def change
    add_reference :series, :library_series, null: true, foreign_key: true
    add_column :series, :quality_score, :decimal, precision: 8, scale: 2
  end
end
