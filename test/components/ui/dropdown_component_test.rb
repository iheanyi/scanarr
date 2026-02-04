require "test_helper"

class UI::DropdownComponentTest < ComponentTestCase
  def test_renders_items
    rendered = render_inline(
      UI::DropdownComponent.new(
        label: "Download policy",
        items: [
          { label: "Notify only", value: "notify_only" },
          { label: "Auto download", value: "auto_download", selected: true }
        ]
      )
    )

    assert_includes rendered.to_html, "Download policy"
    assert_includes rendered.to_html, "Notify only"
    assert_includes rendered.to_html, "Auto download"
  end
end
