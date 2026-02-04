require "test_helper"

class AsuraScansAdapterTest < ActiveSupport::TestCase
  def setup
    @adapter = AsuraScans::Adapter.new(config: {}, http: nil)
  end

  # Test the CHAPTER_NUMBER_PATTERN constant directly
  test "CHAPTER_NUMBER_PATTERN matches integer chapter numbers" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN
    assert_match(/#{pattern}/, "123")
    assert_equal "123", "123"[/#{pattern}/, 1]
  end

  test "CHAPTER_NUMBER_PATTERN matches decimal chapter numbers" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN
    assert_match(/#{pattern}/, "123.5")
    assert_equal "123.5", "123.5"[/#{pattern}/, 1]
  end

  test "CHAPTER_NUMBER_PATTERN matches various decimal formats" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN

    # Single decimal digit
    assert_equal "1.5", "1.5"[/#{pattern}/, 1]

    # Multiple decimal digits
    assert_equal "123.456", "123.456"[/#{pattern}/, 1]

    # Zero decimal
    assert_equal "0.5", "0.5"[/#{pattern}/, 1]
  end

  # Test URL-based chapter number extraction
  test "extracts integer chapter number from URL" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN
    url = "/series/some-manga/chapter/123"

    chapter_num = url[/\/chapter\/#{pattern}/, 1]
    assert_equal "123", chapter_num
  end

  test "extracts decimal chapter number from URL" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN
    url = "/series/some-manga/chapter/123.5"

    chapter_num = url[/\/chapter\/#{pattern}/, 1]
    assert_equal "123.5", chapter_num
  end

  test "extracts decimal chapter number with multiple decimal places from URL" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN
    url = "/series/some-manga/chapter/45.75"

    chapter_num = url[/\/chapter\/#{pattern}/, 1]
    assert_equal "45.75", chapter_num
  end

  # Test the extract_chapter_number helper method
  test "extract_chapter_number returns integer from text" do
    result = @adapter.send(:extract_chapter_number, "Chapter 42")
    assert_equal "42", result
  end

  test "extract_chapter_number returns decimal from text" do
    result = @adapter.send(:extract_chapter_number, "Chapter 42.5")
    assert_equal "42.5", result
  end

  test "extract_chapter_number handles various formats" do
    # With hyphen
    assert_equal "10", @adapter.send(:extract_chapter_number, "Chapter-10")
    assert_equal "10.5", @adapter.send(:extract_chapter_number, "Chapter-10.5")

    # With space
    assert_equal "10", @adapter.send(:extract_chapter_number, "Chapter 10")
    assert_equal "10.5", @adapter.send(:extract_chapter_number, "Chapter 10.5")

    # No separator
    assert_equal "10", @adapter.send(:extract_chapter_number, "Chapter10")
    assert_equal "10.5", @adapter.send(:extract_chapter_number, "Chapter10.5")

    # Case insensitive
    assert_equal "10", @adapter.send(:extract_chapter_number, "CHAPTER 10")
    assert_equal "10.5", @adapter.send(:extract_chapter_number, "chapter 10.5")
  end

  test "extract_chapter_number returns nil for non-matching text" do
    assert_nil @adapter.send(:extract_chapter_number, "No chapter here")
    assert_nil @adapter.send(:extract_chapter_number, nil)
    assert_nil @adapter.send(:extract_chapter_number, "")
  end

  # Integration test: verify URL extraction takes precedence and works correctly
  test "URL extraction and text extraction are consistent for decimals" do
    pattern = AsuraScans::Adapter::CHAPTER_NUMBER_PATTERN

    # Simulate the actual extraction logic from the chapters method
    test_cases = [
      { url: "/chapter/123", text: "Chapter 123", expected: "123" },
      { url: "/chapter/123.5", text: "Chapter 123.5", expected: "123.5" },
      { url: "/chapter/0.5", text: "Chapter 0.5", expected: "0.5" },
      { url: "/chapter/99.99", text: "Chapter 99.99", expected: "99.99" }
    ]

    test_cases.each do |tc|
      # URL extraction (primary)
      url_result = tc[:url][/\/chapter\/#{pattern}/, 1]

      # Text extraction (fallback)
      text_result = @adapter.send(:extract_chapter_number, tc[:text])

      assert_equal tc[:expected], url_result, "URL extraction failed for #{tc[:url]}"
      assert_equal tc[:expected], text_result, "Text extraction failed for #{tc[:text]}"
      assert_equal url_result, text_result, "URL and text extraction gave different results"
    end
  end
end
