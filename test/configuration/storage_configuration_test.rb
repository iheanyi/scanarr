require "test_helper"
require "erb"
require "yaml"

class StorageConfigurationTest < ActiveSupport::TestCase
  def test_development_storage_service_uses_active_storage_service_environment
    source = Rails.root.join("config/environments/development.rb").read

    assert_includes source, 'config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym'
  end

  def test_kamal_storage_service_uses_deploy_environment
    deploy_config = render_kamal_config(
      "ACTIVE_STORAGE_SERVICE" => "s3",
      "S3_ENDPOINT" => "https://example.r2.cloudflarestorage.com",
      "S3_BUCKET" => "scanarr",
      "S3_REGION" => "auto",
      "S3_FORCE_PATH_STYLE" => "true"
    )

    clear_env = deploy_config.fetch("env").fetch("clear")
    secret_env = deploy_config.fetch("env").fetch("secret")

    assert_equal "s3", clear_env.fetch("ACTIVE_STORAGE_SERVICE")
    assert_equal "https://example.r2.cloudflarestorage.com", clear_env.fetch("S3_ENDPOINT")
    assert_equal "scanarr", clear_env.fetch("S3_BUCKET")
    assert_equal "auto", clear_env.fetch("S3_REGION")
    assert clear_env.fetch("S3_FORCE_PATH_STYLE")
    assert_includes secret_env, "S3_ACCESS_KEY_ID"
    assert_includes secret_env, "S3_SECRET_ACCESS_KEY"
  end

  private

  def render_kamal_config(env)
    previous = ENV.to_h.slice(*env.keys)
    env.each { |key, value| ENV[key] = value }

    source = Rails.root.join("config/deploy.yml").read
    YAML.safe_load(ERB.new(source).result, aliases: true)
  ensure
    env.each_key do |key|
      if previous.key?(key)
        ENV[key] = previous[key]
      else
        ENV.delete(key)
      end
    end
  end
end
