require "test_helper"

class SourcesControllerTest < ActionDispatch::IntegrationTest
  class FakeAdapter
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

    def search(_query)
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
