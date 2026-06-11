require "test_helper"

class WeebCentralLiveTest < ActiveSupport::TestCase
  def test_live_flow_records_with_vcr
    VCR.use_cassette("weeb_central_live", record: :new_episodes) do
      adapter = Scrapers::AdapterRegistry.adapter_for_key("weeb_central")

      results = adapter.search("one piece")

      assert_predicate results, :any?, "expected search results"

      series = adapter.series(results.first.url)

      assert_predicate series.title, :present?, "expected series title"

      chapters = adapter.chapters(series.url)

      assert_predicate chapters, :any?, "expected chapters"

      pages = adapter.pages(chapters.first.url)

      assert_predicate pages, :any?, "expected pages"
    end
  end
end
