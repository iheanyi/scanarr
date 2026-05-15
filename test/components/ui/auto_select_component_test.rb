require "test_helper"

class UI::AutoSelectComponentTest < ComponentTestCase
  class DummySeries
    include ActiveModel::Model
    attr_accessor :reading_style
  end

  def test_renders_auto_submit_select
    series = DummySeries.new(reading_style: "left_to_right")
    view_context = ApplicationController.new.view_context
    form = ActionView::Helpers::FormBuilder.new(:series, series, view_context, {})

    rendered = render_inline(
      UI::AutoSelectComponent.new(
        form: form,
        method: :reading_style,
        options: [
          [ "Left to Right", "left_to_right" ],
          [ "Right to Left", "right_to_left" ]
        ],
        selected: series.reading_style
      )
    )

    assert_includes rendered.to_html, "data-controller=\"auto-submit\""
    assert_includes rendered.to_html, "data-action=\"change->auto-submit#submit\""
  end

  def test_passes_leading_icon_to_select_component
    series = DummySeries.new(reading_style: "left_to_right")
    view_context = ApplicationController.new.view_context
    form = ActionView::Helpers::FormBuilder.new(:series, series, view_context, {})

    rendered = render_inline(
      UI::AutoSelectComponent.new(
        form: form,
        method: :reading_style,
        options: [
          [ "Left to Right", "left_to_right" ],
          [ "Right to Left", "right_to_left" ]
        ],
        selected: series.reading_style,
        size: :sm,
        leading_icon: "book-open"
      )
    )

    assert_includes rendered.to_html, "pl-9"
    assert_includes rendered.to_html, "ml-2.5"
  end
end
