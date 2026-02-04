require "test_helper"

class UI::BadgeComponentTest < ComponentTestCase
  def test_renders_label
    rendered = render_inline UI::BadgeComponent.new(label: "Default")

    assert_includes rendered.to_html, "<span"
    assert_includes rendered.to_html, "Default"
  end

  def test_applies_variant_classes
    rendered = render_inline UI::BadgeComponent.new(label: "Warning", variant: :warning)

    assert_includes rendered.to_html, "bg-amber-500/15"
  end
end
