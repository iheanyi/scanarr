require "test_helper"

class UI::BaseComponentTest < ComponentTestCase
  def test_merge_classes_skips_blank_values
    component = UI::BaseComponent.new

    merged = component.send(:merge_classes, "alpha", nil, "", "beta")

    assert_equal "alpha beta", merged
  end
end
