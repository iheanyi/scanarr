module GenreFiltering
  extend ActiveSupport::Concern

  private

  def normalized_genres
    Array(params[:genres]).filter_map do |genre|
      normalized = genre.to_s.strip.downcase.first(80)
      normalized if normalized.present?
    end.uniq
  end

  def available_genre_options
    ActiveRecord::Base.connection.select_values(<<~SQL)
      SELECT DISTINCT jsonb_array_elements_text(normalized_categories) AS genre
      FROM series
      WHERE jsonb_typeof(normalized_categories) = 'array'
        AND jsonb_array_length(normalized_categories) > 0
      ORDER BY genre ASC
      LIMIT 200
    SQL
  end
end
