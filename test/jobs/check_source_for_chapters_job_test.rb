# frozen_string_literal: true

require "test_helper"

class CheckSourceForChaptersJobTest < ActiveJob::TestCase
  setup do
    @series = series(:one)
    @source = sources(:one)
    @series_source = series_sources(:one)
    @follow = user_series_follows(:one)
    @user = users(:one)
  end

  test "creates new chapters from adapter data" do
    chapter_data = [
      ResultTypes::Chapter.new(
        number: "100",
        title: "New Chapter",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/100",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      assert_difference "Chapter.count", 1 do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end

    new_chapter = @series.chapters.find_by(chapter_number: "100")

    assert_equal "New Chapter", new_chapter.title
    assert_equal "en", new_chapter.language
    assert_equal @source, new_chapter.source
  end

  test "skips existing chapters (no duplicates)" do
    # Create a chapter with language "en" matching what the job dedup check expects
    @series.chapters.create!(
      chapter_number: "99",
      title: "Existing EN Chapter",
      language: "en",
      source: @source,
      source_url: "https://weebcentral.com/chapters/99"
    )

    chapter_data = [
      ResultTypes::Chapter.new(
        number: "99",
        title: "Existing EN Chapter",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/99",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      assert_no_difference "Chapter.count" do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end
  end

  test "creates notifications for new chapters" do
    chapter_data = [
      ResultTypes::Chapter.new(
        number: "200",
        title: "Notification Test",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/200",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      assert_difference "NewChapterNotification.count", 1 do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end

    notification = NewChapterNotification.last

    assert_equal @user, notification.user
    assert_equal "200", notification.chapter.chapter_number
  end

  test "auto-downloads when policy is auto_download" do
    @follow.update!(download_policy: :auto_download)

    chapter_data = [
      ResultTypes::Chapter.new(
        number: "300",
        title: "Auto Download",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/300",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      assert_enqueued_with(job: DownloadChapterJob) do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end
  end

  test "does not auto-download when policy is notify_only" do
    @follow.update!(download_policy: :notify_only)

    chapter_data = [
      ResultTypes::Chapter.new(
        number: "301",
        title: "No Download",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/301",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      assert_no_enqueued_jobs(only: DownloadChapterJob) do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end
  end

  test "updates last_checked_at on series_source" do
    assert_nil @series_source.last_checked_at

    with_fake_adapter([]) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @series_source.reload

    assert_not_nil @series_source.last_checked_at
    assert_in_delta Time.current, @series_source.last_checked_at, 5.seconds
  end

  test "returns early if series not found" do
    assert_nothing_raised do
      CheckSourceForChaptersJob.perform_now(0, @follow.id, @source.id)
    end
  end

  test "returns early if follow not found" do
    assert_nothing_raised do
      CheckSourceForChaptersJob.perform_now(@series.id, 0, @source.id)
    end
  end

  private

  def with_fake_adapter(chapter_data)
    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:chapters) { |_| chapter_data }

    original_method = AdapterRegistry.method(:for)
    AdapterRegistry.define_singleton_method(:for) { |_| fake_adapter }
    yield
  ensure
    AdapterRegistry.define_singleton_method(:for, original_method)
  end
end
