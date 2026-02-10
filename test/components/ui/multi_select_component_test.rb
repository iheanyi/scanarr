require "test_helper"

class UI::MultiSelectComponentTest < ComponentTestCase
  def test_renders_combobox_structure
    rendered = render_inline(
      UI::MultiSelectComponent.new(
        name: "sources",
        label: "Sources",
        options: [
          [ "MangaDex", "1" ],
          [ "WeebCentral", "2" ]
        ],
        selected: [ "1" ]
      )
    )

    assert_includes rendered.to_html, "Sources"
    assert_includes rendered.to_html, "data-multi-select-target=\"trigger\""
    assert_includes rendered.to_html, "data-multi-select-target=\"panel\""
    assert_includes rendered.to_html, "data-multi-select-target=\"filter\""
    assert_includes rendered.to_html, "MangaDex"
  end

  def test_uses_no_sources_label_when_none_selected
    rendered = render_inline(
      UI::MultiSelectComponent.new(
        name: "sources",
        options: [
          [ "MangaDex", "1" ],
          [ "WeebCentral", "2" ]
        ],
        selected: [],
        all_label: "All sources"
      )
    )

    html = rendered.to_html

    assert_includes html, ">No sources<"
    assert_includes html, "data-multi-select-none-label-value=\"No sources\""
  end

  def test_uses_all_sources_label_when_all_selected
    rendered = render_inline(
      UI::MultiSelectComponent.new(
        name: "sources",
        options: [
          [ "MangaDex", "1" ],
          [ "WeebCentral", "2" ]
        ],
        selected: [ "1", "2" ],
        all_label: "All sources"
      )
    )

    html = rendered.to_html

    assert_includes html, ">All sources<"
    assert_includes html, "hidden text-[10px] font-medium text-muted-2"
  end
end
