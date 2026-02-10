require "test_helper"

class UI::FilterableMultiSelectComponentTest < ComponentTestCase
  def test_renders_filterable_structure_with_chip_targets
    rendered = render_inline(
      UI::FilterableMultiSelectComponent.new(
        name: "sources",
        label: "Sources",
        options: [
          [ "MangaDex", "1" ],
          [ "WeebCentral", "2" ]
        ],
        selected: [ "1" ]
      )
    )

    assert_includes rendered.to_html, "data-multi-select-target=\"chips\""
    assert_includes rendered.to_html, "data-multi-select-target=\"empty\""
    assert_includes rendered.to_html, "data-multi-select-none-label-value=\"None selected\""
  end
end
