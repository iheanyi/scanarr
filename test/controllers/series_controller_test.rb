require "test_helper"

class SeriesControllerTest < ActionDispatch::IntegrationTest
  def test_index_returns_success
    get "/sources/weeb-central"
    assert_response :success
    assert_includes @response.body, "One Piece"
    assert_includes @response.body, "/sources/weeb-central/one-piece"
  end

  def test_show_returns_success
    get "/sources/weeb-central/one-piece"
    assert_response :success
    assert_includes @response.body, "Chapter 1"
    assert_includes @response.body, "/sources/weeb-central/one-piece/chapters/1"
  end

  def test_show_orders_chapters_numerically
    series = series(:one)
    source = sources(:one)
    Chapter.create!(series: series, source: source, chapter_number: "10", title: "Chapter 10")
    Chapter.create!(series: series, source: source, chapter_number: "10.5", title: "Chapter 10.5")
    Chapter.create!(series: series, source: source, chapter_number: "Extra", title: "Chapter 10 Extra")

    get "/sources/weeb-central/one-piece"
    assert_response :success
    body = @response.body
    assert body.index(">Chapter 1</a>") < body.index(">Chapter 2</a>")
    assert body.index(">Chapter 2</a>") < body.index(">Chapter 10</a>")
    assert body.index(">Chapter 10</a>") < body.index(">Chapter Extra</a>")
    assert body.index(">Chapter Extra</a>") < body.index(">Chapter 10.5</a>")
  end
end
