require "test_helper"

class OfflineManifestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    users(:admin).update!(local_downloads_enabled: "true")
  end

  def test_index_returns_current_users_manifest_entries
    entry = UserOfflineManifestEntry.create!(
      user: users(:admin),
      chapter: chapters(:one),
      status: "pinned",
      last_synced_at: Time.current
    )

    get offline_manifest_path, headers: { "ACCEPT" => "application/json" }

    assert_response :success
    payload = JSON.parse(@response.body)

    assert_equal 1, payload["entries"].size
    assert_equal entry.chapter.public_id, payload["entries"][0]["chapter_public_id"]
    assert_equal "pinned", payload["entries"][0]["status"]
  end

  def test_sync_updates_manifest_status
    entry = UserOfflineManifestEntry.create!(
      user: users(:admin),
      chapter: chapters(:one),
      status: "pinned"
    )

    patch sync_offline_manifest_path,
          params: {
            entries: [
              {
                chapter_public_id: chapters(:one).public_id,
                status: "complete",
                last_synced_at: Time.current.iso8601
              }
            ]
          },
          as: :json

    assert_response :success
    assert_equal "complete", entry.reload.status
    assert_predicate entry.completed_at, :present?
  end

  def test_manifest_endpoints_require_local_downloads_toggle
    users(:admin).update!(local_downloads_enabled: "false")

    get offline_manifest_path, headers: { "ACCEPT" => "application/json" }

    assert_response :forbidden
    payload = JSON.parse(@response.body)

    assert_includes payload["error"], "disabled"
  end
end
