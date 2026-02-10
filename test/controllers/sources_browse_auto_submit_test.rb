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

  def test_browse_form_targets_turbo_frame_for_async_sort
    with_adapter(BrowseOnlyAdapter.new) do
      get "/sources/weeb-central/browse", params: { sort: "latest" }

      assert_response :success
      form = css_select("turbo-frame#browse-content form").first
      assert form, "browse form must exist inside turbo-frame"
      assert_equal "browse-content", form["data-turbo-frame"], "form must target browse-content frame for async replace"
      assert_equal "advance", form["data-turbo-action"], "form should advance history on submit"
      assert_equal "get", form["method"]&.downcase, "form must be GET so sort param is in URL"
    end
  end

  def test_browse_form_includes_page_param_so_url_stays_synced_on_sort_switch
    with_adapter(BrowseOnlyAdapter.new) do
      get "/sources/weeb-central/browse", params: { sort: "latest", page: "2" }

      assert_response :success
      page_input = css_select("turbo-frame#browse-content form input[name='page'][type='hidden']").first
      assert page_input, "form must include hidden page param"
      assert_equal "1", page_input["value"], "sort form must reset to page 1 so URL has sort and page in sync"
    end
  end

  def test_browse_responds_to_sort_param_for_async_update
    with_adapter(BrowseOnlyAdapter.new) do
      get "/sources/weeb-central/browse", params: { sort: "popular" }

      assert_response :success
      assert_select "turbo-frame#browse-content" do
        assert_select "h2", "Popular Series", "heading must reflect sort param so frame replace shows new sort"
      end
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
