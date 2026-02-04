require "test_helper"

class UI::ToggleButtonComponentTest < ComponentTestCase
  def test_renders_active_label
    rendered = render_inline(
      UI::ToggleButtonComponent.new(
        active: true,
        active_label: "Following",
        inactive_label: "Follow",
        hover_label: "Unfollow",
        form_url: "/follows/1",
        method: :delete
      )
    )

    assert_includes rendered.to_html, "Following"
    assert_includes rendered.to_html, "data-toggle-button-active-value=\"true\""
  end
end
