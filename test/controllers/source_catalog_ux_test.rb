require "test_helper"

class SourceCatalogUxTest < ActionDispatch::IntegrationTest
  def test_catalog_only_offers_supported_discovery_actions
    search_only = Source.create!(key: "tcb_scans", name: "TCB Scans", enabled: true)
    unsupported = sources(:two)
    unsupported.update!(enabled: true)

    get sources_path

    assert_response :success
    assert_select "article[aria-label=?]", search_only.display_name do
      assert_select "a[href=?]", source_search_path(source_slug: search_only.slug), text: "Search"
      assert_select "a[href=?]", source_browse_path(source_slug: search_only.slug), count: 0
      assert_select "a[href=?]", source_series_index_path(source_slug: search_only.slug), count: 0
    end
    assert_select "article[aria-label=?]", unsupported.display_name do
      assert_select "a[href=?]", source_search_path(source_slug: unsupported.slug), count: 0
      assert_select "a[href=?]", source_browse_path(source_slug: unsupported.slug), count: 0
      assert_select "p", text: /Browsing and search are not supported/
    end
  end

  def test_unavailable_source_keeps_library_access_and_manual_retry
    source = sources(:one)
    source.update!(health_status: "broken")

    get sources_path

    assert_response :success
    assert_select "article[aria-label=?]", source.display_name do
      assert_select "span", text: "Currently unavailable"
      assert_select "p", text: /downloaded chapters remain in your library/
      assert_select "a[href=?]", source_series_index_path(source_slug: source.slug), text: /In library/
      assert_select "a[href=?]", source_browse_path(source_slug: source.slug), text: "Browse"
    end
    assert_predicate source.reload, :enabled?
  end
end
