# frozen_string_literal: true

# Reuse Scanarr's admin authentication for the embedded job dashboard.
# Mission Control controllers inherit from this class, so /admin/jobs is only
# available to signed-in admin users instead of every authenticated account.
MissionControl::Jobs.base_controller_class = "AdminController"
MissionControl::Jobs.http_basic_auth_enabled = false
