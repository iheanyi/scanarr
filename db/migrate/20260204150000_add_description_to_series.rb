# frozen_string_literal: true

class AddDescriptionToSeries < ActiveRecord::Migration[8.1]
  def change
    add_column :series, :description, :text
  end
end
