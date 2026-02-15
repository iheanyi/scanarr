require "test_helper"

class Admin::ScrapersControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get admin_scrapers_path

    assert_response :success
  end

  def test_index_filters_by_status
    get admin_scrapers_path(status: "success")

    assert_response :success
    # Status badge renders within a span; "failed" appears in the filter dropdown
    # but should not appear as a status badge in the table body
    assert_match /bg-success-soft text-success/, @response.body
    assert_no_match /bg-danger-soft text-danger/, @response.body
  end

  def test_run_smoke_returns_turbo_toast_on_success
    source = sources(:one)

    with_stubbed_smoke_run({ search_count: 1, chapter_count: 1, page_count: 1 }) do
      post admin_scraper_smoke_path(source_id: source.id), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "Smoke test passed for #{source.name}"
    assert_equal "success", ScraperRun.order(created_at: :desc).first.status
  end

  def test_run_smoke_returns_turbo_toast_on_failure
    source = sources(:one)

    with_stubbed_smoke_error(StandardError.new("boom")) do
      post admin_scraper_smoke_path(source_id: source.id), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", @response.media_type
    assert_includes @response.body, "toast-container"
    assert_includes @response.body, "Smoke test failed for #{source.name}: boom"
    assert_equal "failed", ScraperRun.order(created_at: :desc).first.status
  end

  private

  def with_stubbed_smoke_run(result)
    original = Admin::ScrapersController.instance_method(:run_smoke_for)
    Admin::ScrapersController.define_method(:run_smoke_for) { |_source| result }
    yield
  ensure
    Admin::ScrapersController.define_method(:run_smoke_for, original)
  end

  def with_stubbed_smoke_error(error)
    original = Admin::ScrapersController.instance_method(:run_smoke_for)
    Admin::ScrapersController.define_method(:run_smoke_for) { |_source| raise error }
    yield
  ensure
    Admin::ScrapersController.define_method(:run_smoke_for, original)
  end
end
