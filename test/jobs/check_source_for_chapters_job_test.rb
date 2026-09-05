# frozen_string_literal: true

require "test_helper"

class CheckSourceForChaptersJobTest < ActiveJob::TestCase
  setup do
    @series = series(:one)
    @source = sources(:one)
    @series_source = series_sources(:one)
    @follow = user_series_follows(:one)
    @user = users(:admin)
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

  # --- Phase 3: Rate Limit Detection ---

  test "returns early if source was disabled after enqueue" do
    @source.update!(enabled: false)

    with_raising_adapter(RuntimeError.new("Disabled source should not be contacted")) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    assert_nil @series_source.reload.last_checked_at
    assert_equal 0, @series_source.consecutive_failures
  end

  test "returns early if source is rate-limited" do
    @source.update!(rate_limited_until: 5.minutes.from_now)

    with_fake_adapter([]) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @series_source.reload

    # Should not update last_checked_at since we returned early
    assert_nil @series_source.last_checked_at
  end

  test "re-derives health immediately when a check fails" do
    # Three other series already critically failing; this job's failure makes
    # the fourth attempted series, crossing the broken ratio without waiting
    # for the hourly sweep
    3.times do |i|
      library = LibrarySeries.create!(canonical_title: "Failing #{i}", status: "ongoing")
      failing_series = Series.create!(canonical_title: "Failing #{i}", library_series: library)
      SeriesSource.create!(
        series: failing_series, source: @source, source_series_id: "FAIL#{i}",
        last_check_error: "boom", last_check_error_at: Time.current, consecutive_failures: 5
      )
    end

    with_raising_adapter(StandardError.new("site exploded")) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    assert_equal "broken", @source.reload.health_status
  end

  test "records rate limit when adapter raises 429 error" do
    with_raising_adapter(RuntimeError.new("HTTP 429 Too Many Requests")) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @source.reload

    assert_predicate @source, :rate_limited?
  end

  test "records rate limit when adapter raises rate limit error" do
    with_raising_adapter(RuntimeError.new("rate limit exceeded")) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @source.reload

    assert_predicate @source, :rate_limited?
  end

  test "does not record rate limit for non-rate-limit errors" do
    with_raising_adapter(RuntimeError.new("connection timeout")) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @source.reload

    assert_not @source.rate_limited?
  end

  test "clears consecutive failures on successful check" do
    @series_source.update!(
      consecutive_failures: 3,
      last_check_error: "previous error",
      last_check_error_at: 1.hour.ago
    )

    with_fake_adapter([]) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @series_source.reload

    assert_equal 0, @series_source.consecutive_failures
    assert_nil @series_source.last_check_error
    assert_nil @series_source.last_check_error_at
  end

  test "clears rate limit on successful check" do
    @source.update!(rate_limited_until: 1.minute.ago)

    with_fake_adapter([]) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @source.reload

    assert_nil @source.rate_limited_until
  end

  test "records check failure on series_source when adapter raises" do
    with_raising_adapter(RuntimeError.new("some error")) do
      CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
    end

    @series_source.reload

    assert_equal 1, @series_source.consecutive_failures
    assert_equal "some error", @series_source.last_check_error
  end

  # --- Phase 4: Batch Download ---

  test "batch downloads multiple new chapters when auto_download" do
    @follow.update!(download_policy: :auto_download)

    chapter_data = [
      ResultTypes::Chapter.new(
        number: "400",
        title: "Batch Ch 1",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/400",
        published_at: Time.current
      ),
      ResultTypes::Chapter.new(
        number: "401",
        title: "Batch Ch 2",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/401",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      assert_enqueued_jobs 2, only: DownloadChapterJob do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end
  end

  test "does not issue per-chapter EXISTS queries (N+1 prevention)" do
    # Create several existing chapters that the job should skip
    5.times do |i|
      @series.chapters.create!(
        chapter_number: "50#{i}",
        title: "Existing #{i}",
        language: "en",
        source: @source,
        source_url: "https://weebcentral.com/chapters/50#{i}"
      )
    end

    # Adapter returns all existing + 2 new chapters
    chapter_data = (0...5).map do |i|
      ResultTypes::Chapter.new(
        number: "50#{i}",
        title: "Existing #{i}",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/50#{i}",
        published_at: Time.current
      )
    end + [
      ResultTypes::Chapter.new(
        number: "600",
        title: "New One",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/600",
        published_at: Time.current
      ),
      ResultTypes::Chapter.new(
        number: "601",
        title: "New Two",
        language: "en",
        group: nil,
        url: "https://weebcentral.com/chapters/601",
        published_at: Time.current
      )
    ]

    with_fake_adapter(chapter_data) do
      existence_queries = []
      subscriber = ->(_name, _started, _finished, _id, payload) do
        existence_queries << payload[:sql] if payload[:sql].match?(/SELECT 1 AS one FROM "chapters"/) && payload[:sql].include?('"chapter_number"')
      end
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end

      assert_empty existence_queries, "Chapter matching should use the prefetched index"
    end

    assert_equal 2, @series.chapters.where(chapter_number: %w[600 601]).count
  end

  test "replacement creates a release on the existing chapter and downloads with matching provider identifiers" do
    chapter = chapters(:three)
    @follow.update!(download_policy: :auto_download, source_priority: [ sources(:two).key, @source.key ])
    data = ResultTypes::Chapter.new(number: chapter.chapter_number, language: "en", url: "https://weebcentral.com/chapters/replacement", group: "Different group")

    with_fake_adapter([ data, data ]) do
      assert_no_difference [ "Chapter.count", "NewChapterNotification.count" ] do
        assert_enqueued_jobs 1, only: DownloadChapterJob do
          CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
        end
      end
    end

    replacement = chapter.releases.find_by!(source: @source)
    job = enqueued_jobs.find { |entry| entry[:job] == DownloadChapterJob }
    arguments = ActiveJob::Arguments.deserialize(job[:args])

    assert_equal data.url, arguments.first
    assert_equal @source.key, arguments.last[:source_key]
    assert_equal @series_source.source_series_id, arguments.last[:source_series_id]
    assert_equal replacement.id, arguments.last[:release_id]
    assert_equal sources(:two), chapter.reload.source
    assert_equal "failed", file_assets(:three).reload.download_status
  end

  test "replacement availability preserves saved downloads and does not notify twice" do
    source = sources(:two)
    source.update!(enabled: true)
    SeriesSource.create!(series: @series, source: source, source_series_id: "replacement")
    @follow.update!(download_policy: :auto_download)
    chapter = chapters(:one)
    data = ResultTypes::Chapter.new(number: chapter.chapter_number, language: "en", url: "https://example.com/new/chapter-1")

    with_fake_adapter([ data ]) do
      assert_no_difference [ "Chapter.count", "NewChapterNotification.count", "FileAsset.count" ] do
        assert_no_enqueued_jobs only: DownloadChapterJob do
          CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, source.id)
        end
      end
    end

    assert_equal data.url, chapter.releases.find_by!(source: source).source_url
    assert_equal "complete", file_assets(:one).reload.download_status
    assert_equal @source, chapter.reload.source
  end

  test "auto download waits for the preferred linked provider while still recording other releases" do
    preferred = sources(:two)
    preferred.update!(enabled: true)
    SeriesSource.create!(series: @series, source: preferred, source_series_id: "preferred-series")
    @follow.update!(download_policy: :auto_download, source_priority: [ preferred.key, @source.key ])
    data = ResultTypes::Chapter.new(number: "901", language: "en", url: "https://weebcentral.com/chapters/901")

    with_fake_adapter([ data ]) do
      assert_no_enqueued_jobs only: DownloadChapterJob do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end

    chapter = @series.chapters.find_by!(chapter_number: "901")

    assert_equal data.url, chapter.releases.find_by!(source: @source).source_url

    preferred_data = ResultTypes::Chapter.new(number: "901", language: "en", url: "https://example.com/preferred/901")

    with_fake_adapter([ preferred_data ]) do
      assert_enqueued_with(job: DownloadChapterJob, args: ->(args) { args.first == preferred_data.url && args.last[:source_key] == preferred.key }) do
        assert_no_difference "Chapter.count" do
          CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, preferred.id)
        end
      end
    end
  end

  test "auto download falls back when preferred linked provider is unavailable" do
    preferred = sources(:two)
    SeriesSource.create!(series: @series, source: preferred, source_series_id: "preferred-series")
    @follow.update!(download_policy: :auto_download, source_priority: [ preferred.key, @source.key ])
    preferred.update!(health_status: "broken")
    data = ResultTypes::Chapter.new(number: "902", language: "en", url: "https://weebcentral.com/chapters/902")

    with_fake_adapter([ data ]) do
      assert_enqueued_with(job: DownloadChapterJob, args: ->(args) { args.first == data.url && args.last[:source_key] == @source.key }) do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end
  end

  test "auto download picks up an existing preferred release after notify only" do
    @follow.update!(download_policy: :notify_only, source_priority: [ @source.key ])
    data = ResultTypes::Chapter.new(number: "903", language: "en", url: "https://weebcentral.com/chapters/903")

    with_fake_adapter([ data ]) do
      assert_no_enqueued_jobs only: DownloadChapterJob do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end

      chapter = @series.chapters.find_by!(chapter_number: "903")
      release = chapter.releases.find_by!(source: @source)
      @follow.update!(download_policy: :auto_download)

      assert_no_difference [ "Chapter.count", "Release.count", "NewChapterNotification.count" ] do
        assert_enqueued_with(job: DownloadChapterJob, args: ->(args) { args.last[:release_id] == release.id }) do
          CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
        end
      end

      clear_enqueued_jobs
      release.create_file_asset!(format: "pages", download_status: "failed", download_error: "Needs retry")

      assert_no_enqueued_jobs only: DownloadChapterJob do
        CheckSourceForChaptersJob.perform_now(@series.id, @follow.id, @source.id)
      end
    end
  end

  private

  def with_fake_adapter(chapter_data)
    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:chapters) { |_| chapter_data }

    original_method = Scrapers::AdapterRegistry.method(:for)
    Scrapers::AdapterRegistry.define_singleton_method(:for) { |_| fake_adapter }
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_method)
  end

  def with_raising_adapter(error)
    fake_adapter = Object.new
    fake_adapter.define_singleton_method(:chapters) { |_| raise error }

    original_method = Scrapers::AdapterRegistry.method(:for)
    Scrapers::AdapterRegistry.define_singleton_method(:for) { |_| fake_adapter }
    yield
  ensure
    Scrapers::AdapterRegistry.define_singleton_method(:for, original_method)
  end
end
