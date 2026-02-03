require "test_helper"

class HasPublicIdTest < ActiveSupport::TestCase
  # Use Chapter as the test model since it includes HasPublicId
  def setup
    @series = Series.create!(canonical_title: "Test Series")
  end

  def teardown
    @series.destroy
  end

  test "generates public_id on create" do
    chapter = Chapter.create!(series: @series, chapter_number: "1")

    assert chapter.public_id.present?
  end

  test "public_id has correct length" do
    chapter = Chapter.create!(series: @series, chapter_number: "1")

    assert_equal HasPublicId::PUBLIC_ID_LENGTH, chapter.public_id.length
  end

  test "public_id uses only allowed alphabet characters" do
    chapter = Chapter.create!(series: @series, chapter_number: "1")

    allowed_chars = HasPublicId::PUBLIC_ID_ALPHABET.chars
    chapter.public_id.chars.each do |char|
      assert_includes allowed_chars, char, "Character '#{char}' not in allowed alphabet"
    end
  end

  test "public_id is unique" do
    chapter1 = Chapter.create!(series: @series, chapter_number: "1")
    chapter2 = Chapter.create!(series: @series, chapter_number: "2")

    refute_equal chapter1.public_id, chapter2.public_id
  end

  test "validates public_id uniqueness" do
    chapter1 = Chapter.create!(series: @series, chapter_number: "1")
    chapter2 = Chapter.new(series: @series, chapter_number: "2", public_id: chapter1.public_id)

    assert_not chapter2.valid?
    assert_includes chapter2.errors[:public_id], "has already been taken"
  end

  test "does not overwrite manually set public_id" do
    custom_id = "customid1234"
    chapter = Chapter.create!(series: @series, chapter_number: "1", public_id: custom_id)

    assert_equal custom_id, chapter.public_id
  end

  test "to_param returns public_id" do
    chapter = Chapter.create!(series: @series, chapter_number: "1")

    assert_equal chapter.public_id, chapter.to_param
  end

  test "find_by_public_id! returns record when found" do
    chapter = Chapter.create!(series: @series, chapter_number: "1")
    found = Chapter.find_by_public_id!(chapter.public_id)

    assert_equal chapter, found
  end

  test "find_by_public_id! raises RecordNotFound when not found" do
    assert_raises ActiveRecord::RecordNotFound do
      Chapter.find_by_public_id!("nonexistent1")
    end
  end

  test "find_by_public_id returns record when found" do
    chapter = Chapter.create!(series: @series, chapter_number: "1")
    found = Chapter.find_by_public_id(chapter.public_id)

    assert_equal chapter, found
  end

  test "find_by_public_id returns nil when not found" do
    result = Chapter.find_by_public_id("nonexistent1")

    assert_nil result
  end

  test "generate_public_id class method returns valid id" do
    id = Chapter.generate_public_id

    assert_equal HasPublicId::PUBLIC_ID_LENGTH, id.length
    allowed_chars = HasPublicId::PUBLIC_ID_ALPHABET.chars
    id.chars.each do |char|
      assert_includes allowed_chars, char
    end
  end
end
