# frozen_string_literal: true

# Disable HTTP Basic Auth in development
# In production, you'd want to enable this or use a different auth mechanism
MissionControl::Jobs.http_basic_auth_enabled = false
