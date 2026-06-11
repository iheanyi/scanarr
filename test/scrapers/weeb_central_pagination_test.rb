require "test_helper"

class WeebCentralPaginationTest < ActiveSupport::TestCase
  def test_chapters_fetches_full_naruto_list
    VCR.use_cassette("weeb_central_naruto_chapters", record: :new_episodes) do
      adapter = Scrapers::AdapterRegistry.adapter_for_key("weeb_central")

      results = adapter.search("naruto")
      series = results.find { |r| r.title.to_s.strip.casecmp("naruto").zero? } ||
               results.find { |r| r.title.to_s.downcase.include?("naruto") && !r.title.to_s.downcase.include?("boruto") } ||
               results.first

      chapters = adapter.chapters(series.url)

      assert_operator chapters.size, :>, 100, "expected 100+ chapters, got #{chapters.size}"
    end
  end
end
