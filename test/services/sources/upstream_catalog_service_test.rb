require "test_helper"

module Sources
  class UpstreamCatalogServiceTest < ActiveSupport::TestCase
    PAYLOAD = [
      {
        "name" => "Tachiyomi: MangaDex",
        "pkg" => "eu.kanade.tachiyomi.extension.all.mangadex",
        "lang" => "all",
        "code" => 210,
        "nsfw" => 0,
        "sources" => [
          { "name" => "MangaDex", "lang" => "en", "id" => "2499283573021220255", "baseUrl" => "https://mangadex.org" }
        ]
      },
      {
        "name" => "Tachiyomi: NSFW Thing",
        "pkg" => "eu.kanade.tachiyomi.extension.en.nsfwthing",
        "lang" => "en",
        "code" => 3,
        "nsfw" => 1,
        "sources" => [
          { "name" => "NSFW Thing", "lang" => "en", "id" => "11111", "baseUrl" => "https://nsfw.example" },
          { "name" => "Bad URL", "lang" => "en", "id" => "22222", "baseUrl" => "javascript:alert(1)" },
          { "name" => "Bad ID", "lang" => "en", "id" => "not-digits", "baseUrl" => "https://ok.example" },
          { "name" => "", "lang" => "en", "id" => "33333", "baseUrl" => "https://ok.example" }
        ]
      },
      "not even a hash"
    ].freeze

    test "upserts valid sources and skips invalid ones without raising" do
      result = UpstreamCatalogService.new(payload: PAYLOAD).call

      assert_equal 3, result.upserted
      assert_equal 3, result.skipped

      mangadex = UpstreamSource.find_by!(mihon_id: "2499283573021220255")

      assert_equal "MangaDex", mangadex.name
      assert_equal "https://mangadex.org", mangadex.base_url
      assert_equal 210, mangadex.extension_version_code
      refute mangadex.nsfw

      assert UpstreamSource.find_by!(mihon_id: "11111").nsfw
      assert_nil UpstreamSource.find_by!(mihon_id: "22222").base_url
      assert_nil UpstreamSource.find_by(mihon_id: "not-digits")
    end

    test "is idempotent and updates changed fields in place" do
      UpstreamCatalogService.new(payload: PAYLOAD).call

      moved = PAYLOAD[0].deep_dup
      moved["sources"][0]["baseUrl"] = "https://mangadex.moved"
      UpstreamCatalogService.new(payload: [ moved ]).call

      assert_equal 1, UpstreamSource.where(mihon_id: "2499283573021220255").count
      assert_equal "https://mangadex.moved", UpstreamSource.find_by!(mihon_id: "2499283573021220255").base_url
    end

    test "sources missing from a later fetch keep their rows" do
      UpstreamCatalogService.new(payload: PAYLOAD).call
      UpstreamCatalogService.new(payload: [ PAYLOAD[0] ]).call

      assert UpstreamSource.exists?(mihon_id: "11111")
    end

    test "rejects baseUrls pointing at internal or reserved hosts" do
      internal_urls = [
        "http://localhost:3000",
        "http://127.0.0.1",
        "http://10.0.0.5",
        "http://192.168.1.1",
        "http://169.254.169.254/latest/meta-data",
        "http://[::1]",
        "http://[fd00::1]",
        "http://nas.internal",
        "http://0.0.0.0"
      ]
      payload = [ {
        "name" => "Ext", "pkg" => "x.y.z", "lang" => "en", "code" => 1, "nsfw" => 0,
        "sources" => internal_urls.each_with_index.map do |url, i|
          { "name" => "Internal #{i}", "lang" => "en", "id" => (50_000 + i).to_s, "baseUrl" => url }
        end
      } ]

      UpstreamCatalogService.new(payload: payload).call

      internal_urls.each_index do |i|
        assert_nil UpstreamSource.find_by!(mihon_id: (50_000 + i).to_s).base_url
      end
    end

    test "never touches Source records" do
      assert_no_changes -> { Source.order(:id).pluck(:updated_at, :enabled) } do
        UpstreamCatalogService.new(payload: PAYLOAD).call
      end
    end
  end
end
