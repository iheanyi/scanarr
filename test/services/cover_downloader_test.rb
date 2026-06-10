require "test_helper"

class CoverDownloaderTest < ActiveSupport::TestCase
  setup do
    @series = series(:one)
    @series.cover.purge if @series.cover.attached?
    @cover_url = "https://uploads.mangadex.org/covers/test/cover.jpg"
    @jpeg_body = File.read(file_fixture("cover.jpg"), mode: "rb")
  end

  test "downloads and attaches cover from URL" do
    stub_request(:get, @cover_url)
      .to_return(status: 200, body: @jpeg_body, headers: { "content-type" => "image/jpeg" })

    CoverDownloader.download(@series, @cover_url, source: sources(:one))

    assert_predicate @series.cover, :attached?
    assert_equal "cover.jpg", @series.cover.filename.to_s
    assert_equal "library/weeb-central/one-piece--#{@series.public_id}/covers/cover.jpg", @series.cover.blob.key
  end

  test "follows HTTP redirects" do
    redirect_url = "https://cdn.mangadex.org/covers/test/cover.jpg"

    stub_request(:get, @cover_url)
      .to_return(status: 302, headers: { "location" => redirect_url })
    stub_request(:get, redirect_url)
      .to_return(status: 200, body: @jpeg_body, headers: { "content-type" => "image/jpeg" })

    CoverDownloader.download(@series, @cover_url)

    assert_predicate @series.cover, :attached?
  end

  test "stops after max redirects" do
    stub_request(:get, @cover_url)
      .to_return(status: 302, headers: { "location" => @cover_url })

    CoverDownloader.download(@series, @cover_url)

    assert_not @series.cover.attached?
  end

  test "retries with insecure SSL on certificate error" do
    stub_request(:get, @cover_url)
      .to_raise(OpenSSL::SSL::SSLError.new("certificate verify failed"))
      .then
      .to_return(status: 200, body: @jpeg_body, headers: { "content-type" => "image/jpeg" })

    CoverDownloader.download(@series, @cover_url)

    assert_predicate @series.cover, :attached?
  end

  test "does nothing for blank URL" do
    CoverDownloader.download(@series, nil)
    CoverDownloader.download(@series, "")

    assert_not @series.cover.attached?
  end

  test "handles HTTP errors gracefully" do
    stub_request(:get, @cover_url)
      .to_return(status: 404)

    CoverDownloader.download(@series, @cover_url)

    assert_not @series.cover.attached?
  end

  test "detects content type for PNG" do
    png_body = File.read(file_fixture("cover.jpg"), mode: "rb") # reuse fixture for body
    stub_request(:get, @cover_url)
      .to_return(status: 200, body: png_body, headers: { "content-type" => "image/png" })

    CoverDownloader.download(@series, @cover_url)

    assert_predicate @series.cover, :attached?
    assert_equal "cover.png", @series.cover.filename.to_s
  end
end
