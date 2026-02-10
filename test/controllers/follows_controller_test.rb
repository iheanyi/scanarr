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
end
