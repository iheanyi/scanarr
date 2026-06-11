require "test_helper"

class Admin::SourceCatalogControllerTest < ActionDispatch::IntegrationTest
  def setup
    UpstreamSource.create!(
      mihon_id: "2499283573021220255", name: "MangaDex", lang: "en",
      base_url: "https://mangadex.org", extension_version_code: 210, last_seen_at: Time.current
    )
    UpstreamSource.create!(
      mihon_id: "999999", name: "Some Unimplemented Source", lang: "en",
      base_url: "https://unimplemented.example", last_seen_at: Time.current
    )
    UpstreamSource.create!(
      mihon_id: "888888", name: "Source Francophone", lang: "fr",
      base_url: "https://fr.example", last_seen_at: Time.current
    )
  end

  def test_index_marks_implemented_and_unimplemented_sources
    get admin_source_catalog_path

    assert_response :success
    assert_match "MangaDex", @response.body
    assert_match "Implemented", @response.body
    assert_match "Some Unimplemented Source", @response.body
    assert_match "No adapter", @response.body
  end

  def test_index_hides_other_languages_by_default
    get admin_source_catalog_path

    assert_no_match "Source Francophone", @response.body

    get admin_source_catalog_path(lang: "all")

    assert_match "Source Francophone", @response.body
  end

  def test_index_filters_by_name
    get admin_source_catalog_path(q: "mangadex")

    assert_match "MangaDex", @response.body
    assert_no_match "Some Unimplemented Source", @response.body
  end

  def test_refresh_enqueues_the_catalog_job
    assert_enqueued_with(job: RefreshUpstreamCatalogJob) do
      post admin_source_catalog_refresh_path, headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
    end

    assert_response :success
  end
end
