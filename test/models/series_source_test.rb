require "test_helper"

class SeriesSourceTest < ActiveSupport::TestCase
  def test_allows_library_base_path
    series_source = series_sources(:one)
    series_source.update!(library_base_path: "weeb_central/one-piece-eiichiro-oda")

    assert_equal "weeb_central/one-piece-eiichiro-oda", series_source.library_base_path
  end
end
