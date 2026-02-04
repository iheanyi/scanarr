require "test_helper"

class UI::ToggleSwitchComponentTest < ComponentTestCase
  class DummyFollow
    include ActiveModel::Model
    attr_accessor :download_policy
  end

  def test_renders_label_and_auto_submit_data
    follow = DummyFollow.new(download_policy: "auto_download")
    view_context = ApplicationController.new.view_context
    form = ActionView::Helpers::FormBuilder.new(:follow, follow, view_context, {})

    rendered = render_inline(
      UI::ToggleSwitchComponent.new(
        form: form,
        method: :download_policy,
        label: "Auto-download",
        description: "Download new chapters automatically.",
        on_value: "auto_download",
        off_value: "notify_only",
        auto_submit: true
      )
    )

    assert_includes rendered.to_html, "Auto-download"
    assert_includes rendered.to_html, "data-action=\"change->auto-submit#submit\""
  end
end
