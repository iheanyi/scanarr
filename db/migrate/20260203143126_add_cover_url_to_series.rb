class AddCoverUrlToSeries < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :cover_url, :string
  end
end
