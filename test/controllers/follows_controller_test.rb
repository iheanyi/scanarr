require "test_helper"

class FollowsControllerTest < ActionDispatch::IntegrationTest
  def test_create_defaults_to_auto_download_policy
    unique_id = SecureRandom.hex(4)
    source = sources(:one)
    series = Series.create!(
      canonical_title: "Default Follow Policy",
      public_id: "seriespubfollow#{unique_id}",
      slug: "default-follow-policy-#{unique_id}"
    )
    library_series = LibrarySeries.create!(
      canonical_title: series.canonical_title,
      public_id: "libseriesfollow#{unique_id}",
      slug: "default-follow-policy-#{unique_id}"
    )
    series.update!(library_series: library_series)
    SeriesSource.create!(series: series, source: source, source_series_id: "DEFAULT_FOLLOW_001")

    assert_difference("UserSeriesFollow.count", 1) do
      post follows_path, params: { library_series_id: library_series.id }
    end

    follow = UserSeriesFollow.order(created_at: :desc).first

    assert_equal "auto_download", follow.download_policy
  end

  def test_create_missing_library_series_turbo_request_redirects_with_flash
    post follows_path,
         params: { library_series_id: "missing-library-series-id" },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to library_path
    assert_equal "Series follow target not found", flash[:alert]
  end

  def test_update_missing_follow_turbo_request_redirects_with_flash
    patch follow_path("missing-follow-id"),
          params: { user_series_follow: { download_policy: "auto_download" } },
          headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to library_path
    assert_equal "Follow not found", flash[:alert]
  end

  def test_destroy_missing_follow_turbo_request_redirects_with_flash
    delete follow_path("missing-follow-id"),
           headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    assert_redirected_to library_path
    assert_equal "Follow not found", flash[:alert]
  end
end
