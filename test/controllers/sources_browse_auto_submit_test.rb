require "test_helper"

class SourcesBrowseAutoSubmitTest < ActionDispatch::IntegrationTest
  class BrowseOnlyAdapter
    def supports_browse?
      true
    end

    def browse_page_size
      20
    end

    def browse_sort_options
      %w[latest popular alphabetical]
    end

    def browse(sort:, page:, limit:)
      [
        ResultTypes::BrowseResult.new(
          id: "browse-#{sort}-#{page}-#{limit}",
          title: "Browse Series",
          url: "https://weebcentral.com/series/BROWSE",
          cover_url: "https://img.example.com/browse-cover.jpg"
        )
      ]
    end
  end

  def test_browse_sort_control_auto_submits_without_apply_button
    with_adapter(BrowseOnlyAdapter.new) do
      get "/sources/weeb-central/browse", params: { sort: "latest" }

      assert_response :success
      assert_select "turbo-frame#browse-content form select[name='sort'][data-action='change->auto-submit#submit']"
      assert_select "turbo-frame#browse-content button", text: "Apply", count: 0
    end
  end

  private

  def with_adapter(adapter)
    original_for = Scrapers::AdapterRegistry.method(:for)
    Scrapers::AdapterRegistry.define_singleton_method(:for) { |_source| adapter }
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
  end
end
