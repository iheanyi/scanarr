require "test_helper"

class UI::ButtonComponentTest < ComponentTestCase
  def test_renders_button_with_label
    rendered = render_inline UI::ButtonComponent.new(label: "Save")

    assert_includes rendered.to_html, "<button"
    assert_includes rendered.to_html, "Save"
  end

  def test_renders_link_when_href
    rendered = render_inline UI::ButtonComponent.new(label: "Docs", href: "/docs")

    assert_includes rendered.to_html, "<a"
    assert_includes rendered.to_html, "href=\"/docs\""
    assert_includes rendered.to_html, "data-turbo-frame=\"_top\""
    assert_includes rendered.to_html, "Docs"
  end

  def test_preserves_explicit_turbo_frame_data
    rendered = render_inline UI::ButtonComponent.new(
      label: "Open",
      href: "/docs",
      data: { turbo_frame: "library-content" }
    )

    assert_includes rendered.to_html, "data-turbo-frame=\"library-content\""
  end

  def test_supports_block_content
    rendered = render_inline(UI::ButtonComponent.new(variant: :secondary)) { "Block Label" }

    assert_includes rendered.to_html, "<button"
    assert_includes rendered.to_html, "Block Label"
  end
end
