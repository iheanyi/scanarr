# frozen_string_literal: true

class BackfillLibrarySeries < ActiveRecord::Migration[8.0]
  def up
    return if LibrarySeries.any?

    Series.select(:canonical_title).distinct.each do |series|
      title = series.canonical_title
      next if title.blank?

      library_series = LibrarySeries.create!(
        canonical_title: title,
        status: :ongoing
      )

      Series.where(canonical_title: title).update_all(library_series_id: library_series.id)
    end
  end

  def down
    Series.update_all(library_series_id: nil)
    LibrarySeries.delete_all
  end
end
