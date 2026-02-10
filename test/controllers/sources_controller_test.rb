require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  class FakeAdapter
    attr_reader :last_browse_filters, :last_search_filters

    class FakeHttpClient
      Response = Struct.new(:status, :body, :headers, :url, keyword_init: true)

      def get(url)
        Response.new(
          status: 200,
          body: "fake-image-data",
          headers: { "content-type" => "image/jpeg" },
          url: url
        )
      end
    end

    def supports_search?
      true
    end

    def supports_browse?
      true
    end

    def supports_server_side_filters?
      true
    end

    def search_filter_options
      {
        genres: [ [ "Action", "action" ], [ "Romance", "romance" ] ],
        statuses: [ [ "Ongoing", "ongoing" ], [ "Completed", "completed" ] ]
      }
    end

    def browse_filter_options
      search_filter_options
    end

    def browse_page_size
      20
    end

    def browse_sort_options
      %w[latest popular alphabetical]
    end

    def browse(sort:, page:, limit:, filters: {})
      @last_browse_filters = filters
      [
        ResultTypes::BrowseResult.new(
          id: "browse-#{sort}-#{page}-#{limit}",
          title: "Browse Series",
          url: "https://weebcentral.com/series/BROWSE",
          cover_url: "https://img.example.com/browse-cover.jpg"
        )
      ]
    end

    def search(_query, filters: {})
      @last_search_filters = filters
      [
        ResultTypes::SearchResult.new(
          id: "series-123",
          title: "One Piece",
          url: "https://weebcentral.com/series/OP",
          cover_url: "https://img.example.com/cover.jpg",
          language: nil
        )
      ]
    end

    def series(_url)
      ResultTypes::Series.new(id: "series-123", title: "One Piece", url: "https://weebcentral.com/series/OP")
    end

    def chapters(_series_url)
      [
        ResultTypes::Chapter.new(id: "ch-1", title: "Chapter 1", number: "1", url: "https://weebcentral.com/chapters/01CHAPTER"),
        ResultTypes::Chapter.new(id: "ch-2", title: "Chapter 2", number: "2", url: "https://weebcentral.com/chapters/02CHAPTER"),
        ResultTypes::Chapter.new(id: "ch-3", title: "Chapter 3", number: "3", url: "https://weebcentral.com/chapters/03CHAPTER")
      ]
    end

    def pages(chapter_url)
      chapter_id = chapter_url.split("/").last
      [
        ResultTypes::Page.new(index: 1, url: "https://img.example.com/#{chapter_id}-1.jpg", mime_type: "image/jpeg"),
        ResultTypes::Page.new(index: 2, url: "https://img.example.com/#{chapter_id}-2.jpg", mime_type: "image/jpeg")
      ]
    end

    def http
      @http ||= FakeHttpClient.new
    end
  end

  def test_index_returns_success
    get "/"

    assert_response :success
    assert_includes @response.body, "Weeb Central"
    assert_includes @response.body, "/sources/weeb-central"
    assert_includes @response.body, "application-" # CSS asset
  end

  def test_index_hides_mature_sources_by_default
    get "/"

    assert_response :success
    assert_not_includes @response.body, "Manhwa18"
    assert_includes @response.body, "Show 18+"
  end

  def test_index_can_include_mature_sources
    get "/", params: { include_mature: "1" }

    assert_response :success
    assert_includes @response.body, "Manhwa18"
    assert_includes @response.body, "18+"
    assert_includes @response.body, "Hide 18+"
  end

  def test_index_navigation_buttons_escape_turbo_frame
    get "/"

    assert_response :success
    assert_select %(turbo-frame#sources-content a[data-turbo-frame="_top"]), minimum: 3
  end

  def test_sources_turbo_frame_links_always_declare_navigation_target
    get "/"

    assert_response :success
    assert_select "turbo-frame#sources-content a[href]:not([href^='#']):not([data-turbo-frame])", 0
  end

  def test_search_shows_results
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/search", params: { q: "one piece" }

      assert_response :success
      assert_includes @response.body, "One Piece"
      assert_includes @response.body, "https://img.example.com/cover.jpg"
    end
  end

  def test_browse_sort_control_auto_submits_without_apply_button
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/browse", params: { sort: "latest" }

      assert_response :success
      assert_select "turbo-frame#browse-content form select[name='sort'][data-action='change->auto-submit#submit']"
      assert_select "turbo-frame#browse-content button", text: "Apply", count: 0
    end
  end

  def test_search_renders_advanced_filter_controls_when_source_supports_them
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/search"

      assert_response :success
      assert_includes @response.body, "Advanced filters"
      assert_includes @response.body, 'name="genres[]"'
      assert_includes @response.body, 'name="statuses[]"'
    end
  end

  def test_search_passes_selected_filters_to_adapter
    adapter = FakeAdapter.new

    with_adapter(adapter) do
      get "/sources/weeb-central/search", params: {
        q: "one piece",
        genres: [ "action" ],
        statuses: [ "ongoing" ]
      }

      assert_response :success
      assert_equal({ genres: [ "action" ], statuses: [ "ongoing" ] }, adapter.last_search_filters)
    end
  end

  def test_browse_passes_selected_filters_to_adapter_and_preserves_pagination_params
    adapter = FakeAdapter.new

    with_adapter(adapter) do
      get "/sources/weeb-central/browse", params: {
        sort: "latest",
        genres: [ "action" ],
        statuses: [ "ongoing" ]
      }

      assert_response :success
      assert_equal({ genres: [ "action" ], statuses: [ "ongoing" ] }, adapter.last_browse_filters)
      assert_includes @response.body, "genres%5B%5D=action"
      assert_includes @response.body, "statuses%5B%5D=ongoing"
    end
  end

  def test_import_creates_series
    user_series_follows(:one).update!(download_policy: :auto_download)

    with_adapter(FakeAdapter.new) do
      assert_enqueued_with(job: DownloadAllJob) do
        post "/sources/weeb-central/import", params: { series_url: "https://weebcentral.com/series/OP" }
      end
      series = Series.find_by(canonical_title: "One Piece")

      assert_redirected_to library_series_path(series_slug: series.to_param)
    end
  end

  def test_import_respects_notify_only_policy_without_queuing_downloads
    user_series_follows(:one).update!(download_policy: :notify_only)

    with_adapter(FakeAdapter.new) do
      assert_no_enqueued_jobs(only: DownloadAllJob) do
        post "/sources/weeb-central/import", params: { series_url: "https://weebcentral.com/series/OP" }
      end
    end
  end

  def test_preview_shows_read_links_for_chapters
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/preview", params: { series_url: "https://weebcentral.com/series/OP" }

      assert_response :success
      assert_select "a[href*='/sources/weeb-central/preview/read'][href*='chapter_url=']", minimum: 1
      assert_select "a", text: "Read", minimum: 1
    end
  end

  def test_preview_read_renders_source_pages_and_navigation
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/preview/read",
          params: {
            series_url: "https://weebcentral.com/series/OP",
            chapter_url: "https://weebcentral.com/chapters/02CHAPTER"
          }

      assert_response :success
      assert_select "main[data-controller='reader']"
      assert_select "img[src*='/sources/weeb-central/preview/image?token=']", count: 2
      assert_select "a", text: "Previous Chapter", count: 1
      assert_select "a", text: "Next Chapter", count: 1
      assert_select "h2", text: "Chapter 2"
      assert_includes @response.body, "reader#lightboxPointerDown"
      assert_includes @response.body, "reader#lightboxPointerMove"
      assert_includes @response.body, "reader#lightboxPointerUp"
      assert_includes @response.body, "lightbox-nav-arrow absolute left-6"
      assert_includes @response.body, "lightbox-nav-arrow absolute right-6"
    end
  end

  def test_preview_image_proxies_adapter_response
    token = Rails.application.message_verifier(:source_preview_image).generate(
      { source_slug: "weeb-central", page_url: "https://img.example.com/02CHAPTER-1.jpg" },
      purpose: "source_preview_image",
      expires_in: 6.hours
    )

    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/preview/image", params: { token: token }

      assert_response :success
      assert_equal "image/jpeg", @response.media_type
      assert_equal "fake-image-data", @response.body
    end
  end

  def test_preview_image_rejects_invalid_token
    with_adapter(FakeAdapter.new) do
      get "/sources/weeb-central/preview/image", params: { token: "invalid" }

      assert_response :forbidden
    end
  end

  private

  def with_adapter(adapter)
    # Stub Scrapers::AdapterRegistry.for to return fake adapter
    original_for = Scrapers::AdapterRegistry.method(:for)
    Scrapers::AdapterRegistry.define_singleton_method(:for) { |_source| adapter }
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_for)
  end
end
