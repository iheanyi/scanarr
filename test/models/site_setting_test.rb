require "test_helper"

class SiteSettingTest < ActiveSupport::TestCase
  def test_instance_returns_existing_record
    setting = site_settings(:default)

    assert_equal setting, SiteSetting.instance
  end

  def test_instance_creates_record_if_none_exists
    SiteSetting.delete_all

    assert_difference "SiteSetting.count", 1 do
      SiteSetting.instance
    end
  end

  def test_registration_enabled_defaults_to_true
    SiteSetting.delete_all

    assert_predicate SiteSetting, :registration_enabled?
  end

  def test_registration_enabled_can_be_toggled_off
    setting = SiteSetting.instance
    setting.update!(registration_enabled: false)

    assert_not SiteSetting.registration_enabled?
  end
end
