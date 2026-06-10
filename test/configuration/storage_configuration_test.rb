require "test_helper"
require "erb"
require "yaml"

class StorageConfigurationTest < ActiveSupport::TestCase
  STORAGE_ENV_KEYS = %w[
    ACTIVE_STORAGE_SERVICE
    ACTIVE_STORAGE_LOCAL_ROOT
    SCANARR_STORAGE_ROOT
    S3_ACCESS_KEY_ID
    S3_SECRET_ACCESS_KEY
    S3_REGION
    S3_BUCKET
    S3_ENDPOINT
    S3_FORCE_PATH_STYLE
  ].freeze

  def test_storage_yaml_defines_local_and_s3_services_from_environment
    with_env(
      "ACTIVE_STORAGE_LOCAL_ROOT" => "/rails/storage",
      "S3_ACCESS_KEY_ID" => "access-key",
      "S3_SECRET_ACCESS_KEY" => "secret-key",
      "S3_REGION" => "auto",
      "S3_BUCKET" => "scanarr",
      "S3_ENDPOINT" => "https://example.r2.cloudflarestorage.com",
      "S3_FORCE_PATH_STYLE" => "true"
    ) do
      config = render_storage_config

      assert_equal "Disk", config.dig("local", "service")
      assert_equal "/rails/storage", config.dig("local", "root")
      assert_equal "S3", config.dig("s3", "service")
      assert_equal "access-key", config.dig("s3", "access_key_id")
      assert_equal "secret-key", config.dig("s3", "secret_access_key")
      assert_equal "auto", config.dig("s3", "region")
      assert_equal "scanarr", config.dig("s3", "bucket")
      assert_equal "https://example.r2.cloudflarestorage.com", config.dig("s3", "endpoint")
      assert config.dig("s3", "force_path_style")
    end
  end

  def test_storage_yaml_omits_blank_s3_endpoint
    with_env("S3_ENDPOINT" => "") do
      config = render_storage_config

      refute config.fetch("s3").key?("endpoint")
    end
  end

  def test_s3_active_storage_service_can_be_instantiated
    with_env(
      "S3_ACCESS_KEY_ID" => "access-key",
      "S3_SECRET_ACCESS_KEY" => "secret-key",
      "S3_REGION" => "auto",
      "S3_BUCKET" => "scanarr",
      "S3_FORCE_PATH_STYLE" => "true"
    ) do
      service = ActiveStorage::Service.configure(:s3, render_storage_config)

      assert_instance_of ActiveStorage::Service::S3Service, service
    end
  end

  def test_kamal_deploy_defaults_to_local_storage_without_s3_secrets
    with_env("ACTIVE_STORAGE_SERVICE" => nil) do
      rendered = render_template("config/deploy.yml")

      assert_includes rendered, "ACTIVE_STORAGE_SERVICE: local"
      assert_includes rendered, "ACTIVE_STORAGE_LOCAL_ROOT: /rails/storage"
      refute_includes rendered, "S3_ACCESS_KEY_ID"
      refute_includes rendered, "S3_SECRET_ACCESS_KEY"
    end
  end

  def test_kamal_deploy_includes_s3_settings_and_secrets_when_enabled
    with_env(
      "ACTIVE_STORAGE_SERVICE" => "s3",
      "S3_ENDPOINT" => "https://example.r2.cloudflarestorage.com",
      "S3_BUCKET" => "scanarr",
      "S3_REGION" => "auto",
      "S3_FORCE_PATH_STYLE" => "true"
    ) do
      rendered = render_template("config/deploy.yml")

      assert_includes rendered, "ACTIVE_STORAGE_SERVICE: s3"
      assert_includes rendered, "- S3_ACCESS_KEY_ID"
      assert_includes rendered, "- S3_SECRET_ACCESS_KEY"
      assert_includes rendered, "S3_ENDPOINT: https://example.r2.cloudflarestorage.com"
      assert_includes rendered, "S3_BUCKET: scanarr"
      assert_includes rendered, "S3_REGION: auto"
      assert_includes rendered, "S3_FORCE_PATH_STYLE: true"
    end
  end

  private

  def render_storage_config
    YAML.safe_load(render_template("config/storage.yml"), aliases: true)
  end

  def render_template(path)
    ERB.new(Rails.root.join(path).read).result
  end

  def with_env(overrides)
    keys = (STORAGE_ENV_KEYS + overrides.keys).uniq
    previous = keys.to_h { |key| [ key, ENV.key?(key) ? ENV[key] : nil ] }

    overrides.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end

    yield
  ensure
    previous.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
