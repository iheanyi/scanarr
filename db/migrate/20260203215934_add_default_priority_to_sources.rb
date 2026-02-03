# frozen_string_literal: true

class AddDefaultPriorityToSources < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:sources, :default_priority)
      add_column :sources, :default_priority, :integer, default: 50
    end
  end
end
