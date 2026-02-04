require "test_helper"

class UI::MultiSelectComponentTest < ComponentTestCase
  def test_renders_combobox_structure
    rendered = render_inline(
      UI::MultiSelectComponent.new(
        name: "sources",
        label: "Sources",
        options: [
          ["MangaDex", "1"],
          ["WeebCentral", "2"]
        ],
        selected: ["1"]
      )
    )

    assert_includes rendered.to_html, "Sources"
    assert_includes rendered.to_html, "data-multi-select-target=\"trigger\""
    assert_includes rendered.to_html, "data-multi-select-target=\"panel\""
    assert_includes rendered.to_html, "data-multi-select-target=\"filter\""
    assert_includes rendered.to_html, "MangaDex"
  end
end
