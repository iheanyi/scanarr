require "test_helper"

class UI::SeriesCoverComponentTest < ComponentTestCase
  def test_renders_remote_fallback_url_for_failed_primary_image
    rendered = render_inline(
      UI::SeriesCoverComponent.new(
        url: "/rails/active_storage/blobs/cover",
        fallback_url: "https://example.test/cover.jpg",
        alt: "Cover"
      )
    )

    image = rendered.css("img").first

    assert_equal "https://example.test/cover.jpg", image["data-fallback-url"]
    assert_includes image["onerror"], "dataset.fallbackUrl"
  end
end
