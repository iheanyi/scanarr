class AddLocalizedTitleToSeries < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :localized_title, :string
    add_column :series, :alt_titles, :json, default: []
  end
end
