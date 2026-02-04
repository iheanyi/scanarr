require "test_helper"

class UI::SelectComponentTest < ComponentTestCase
  class DummySeries
    include ActiveModel::Model
    attr_accessor :reading_style
  end

  def test_renders_label_and_options
    series = DummySeries.new(reading_style: "left_to_right")
    view_context = ApplicationController.new.view_context
    form = ActionView::Helpers::FormBuilder.new(:series, series, view_context, {})

    rendered = render_inline(
      UI::SelectComponent.new(
        form: form,
        method: :reading_style,
        options: [
          ["Left to Right", "left_to_right"],
          ["Right to Left", "right_to_left"]
        ],
        selected: series.reading_style,
        label: "Reading style"
      )
    )

    assert_includes rendered.to_html, "Reading style"
    assert_includes rendered.to_html, "Left to Right"
    assert_includes rendered.to_html, "selected=\"selected\""
  end
end
