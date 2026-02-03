require "test_helper"

class LibrarySeriesTest < ActiveSupport::TestCase
  def test_generates_public_id
    library_series = LibrarySeries.create!(canonical_title: "One Piece")
    assert library_series.public_id.present?
    assert_equal 12, library_series.public_id.length
  end

  def test_generates_slug_from_title
    library_series = LibrarySeries.create!(canonical_title: "One Piece Omega")
    assert_equal "one-piece-omega", library_series.slug
  end

  def test_slug_is_unique
    first = LibrarySeries.create!(canonical_title: "Slug Test")
    second = LibrarySeries.create!(canonical_title: "Slug Test")
    assert first.slug.start_with?("slug-test")
    assert second.slug.start_with?("slug-test")
    assert_not_equal first.slug, second.slug
  end

  def test_status_enum
    library_series = LibrarySeries.create!(canonical_title: "One Piece")

    assert library_series.ongoing?

    library_series.update!(status: :completed)
    assert library_series.completed?

    library_series.update!(status: :hiatus)
    assert library_series.hiatus?

    library_series.update!(status: :cancelled)
    assert library_series.cancelled?
  end

  def test_to_param_includes_public_id_and_slug
    library_series = LibrarySeries.create!(canonical_title: "One Piece")
    assert_equal "#{library_series.public_id}-#{library_series.slug}", library_series.to_param
  end

  def test_find_by_param
    library_series = LibrarySeries.create!(canonical_title: "One Piece")
    found = LibrarySeries.find_by_param!(library_series.to_param)
    assert_equal library_series, found
  end

  def test_has_many_series
    library_series = LibrarySeries.create!(canonical_title: "One Piece")
    series = Series.create!(canonical_title: "One Piece Vol 1", library_series: library_series)

    assert_includes library_series.series, series
    assert_equal library_series, series.library_series
  end

  def test_has_many_followers_through_user_series_follows
    library_series = LibrarySeries.create!(canonical_title: "One Piece")
    user = User.create!(
      email: "test@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )

    UserSeriesFollow.create!(user: user, library_series: library_series)

    assert_includes library_series.followers, user
  end
end
