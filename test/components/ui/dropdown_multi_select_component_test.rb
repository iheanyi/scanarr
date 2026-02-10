require "test_helper"

class UI::DropdownMultiSelectComponentTest < ComponentTestCase
  def test_renders_dropdown_style_trigger
    rendered = render_inline(
      UI::DropdownMultiSelectComponent.new(
        name: "sources",
        options: [
          [ "MangaDex", "1" ],
          [ "WeebCentral", "2" ]
        ],
        selected: [ "1" ]
      )
    )

    html = rendered.to_html

    assert_includes html, "data-multi-select-target=\"trigger\""
    assert_includes html, "inline-flex w-full min-w-0 items-center justify-between gap-2 rounded-md border border-border bg-surface-2 px-3 py-1.5 text-xs font-semibold"
    assert_includes html, "sm:min-w-44 sm:w-auto"
    assert_includes html, "aria-haspopup=\"listbox\""
  end
end
