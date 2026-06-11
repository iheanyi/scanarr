require "test_helper"

module Sources
  class TitleMatcherTest < ActiveSupport::TestCase
    test "exact normalized match scores 1.0" do
      assert_in_delta(1.0, TitleMatcher.score("Berserk", "BERSERK!"))
    end

    test "containment scores 0.8" do
      assert_in_delta(0.8, TitleMatcher.score("Berserk", "Berserk of Gluttony"))
    end

    test "word overlap is capped below containment" do
      near_duplicate = TitleMatcher.score(
        "the rising of the shield hero one two three four five",
        "the rising of the shield hero one two three four six"
      )

      assert_operator near_duplicate, :<=, TitleMatcher::WORD_OVERLAP_CAP
    end

    test "reordered words cannot impersonate an exact match" do
      assert_operator TitleMatcher.score("fullmetal alchemist brotherhood", "brotherhood fullmetal alchemist"),
                      :<, TitleMatcher::AUTO_LINK_CONFIDENCE
    end

    test "only an exact match clears the auto-link bar" do
      result = Struct.new(:title, :url).new("Berserk of Gluttony", "https://x/1")

      match, _confidence = TitleMatcher.best_match("Berserk", [ result ], min_confidence: TitleMatcher::AUTO_LINK_CONFIDENCE)

      assert_nil match
    end
  end
end
