# Configurable Remote Storage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make downloaded chapter pages, generated CBZ archives, and covers use configurable Rails Active Storage backends so self-hosted users can choose local/NAS disk or S3-compatible object storage.

**Architecture:** Scanarr already stores downloaded media through Active Storage (`Page#image`, `FileAsset#archive`, `Series#cover`) and already defines `local` plus `s3` services in `config/storage.yml`. The implementation should keep that Rails-native boundary, make all deployment targets honor `ACTIVE_STORAGE_SERVICE`, and document the supported knobs instead of adding a custom storage adapter.

**Tech Stack:** Rails 8.1 Active Storage, S3-compatible Active Storage service, Kamal ERB deploy config, Docker Compose env config, Minitest.

---

## Scope

This plan covers deployment-time storage configuration. It does not add in-app credential editing, per-library storage roots, or online migration of existing blobs. Those are separate features because Active Storage service selection is process-level and credentials belong in deployment secrets, not user preference rows.

## File Structure

- Modify `config/environments/development.rb`: select Active Storage service from `ACTIVE_STORAGE_SERVICE`, defaulting to `local`.
- Modify `config/deploy.yml`: render Kamal container env from deployment environment variables and include S3 secrets only when `ACTIVE_STORAGE_SERVICE=s3`.
- Modify `README.md`: explain local/NAS and S3-compatible media storage at the top-level quick start.
- Modify `docs/self-hosting.md`: add Kamal S3 environment example.
- Create `test/configuration/storage_configuration_test.rb`: guard the Kamal and development configuration behavior.

## Task 1: Guard Storage Configuration

**Files:**
- Create: `test/configuration/storage_configuration_test.rb`

- [ ] **Step 1: Add a failing Minitest config guard**

```ruby
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
```

- [ ] **Step 2: Verify the test fails before implementation**

Run:

```bash
bin/rails test test/configuration/storage_configuration_test.rb
```

Expected before implementation:

```text
Expected: "s3"
  Actual: "local"
```

## Task 2: Make Environment Configurable

**Files:**
- Modify: `config/environments/development.rb`
- Modify: `config/deploy.yml`

- [ ] **Step 1: Update development Active Storage service selection**

Replace the hard-coded local service with:

```ruby
# Store uploaded files through Active Storage. Use ACTIVE_STORAGE_SERVICE=s3
# with S3_* env vars for AWS S3, Cloudflare R2, MinIO, or another S3-compatible service.
config.active_storage.service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local").to_sym
```

- [ ] **Step 2: Add deploy-time storage variables to Kamal config**

At the top of `config/deploy.yml`, keep the existing storage path and add service selection:

```yaml
<% scanarr_storage_path = ENV.fetch("SCANARR_STORAGE_PATH", "scanarr_storage_data") %>
<% active_storage_service = ENV.fetch("ACTIVE_STORAGE_SERVICE", "local") %>
```

In `env.secret`, add S3 secrets only for S3 renders:

```yaml
<% if active_storage_service == "s3" %>
    - S3_ACCESS_KEY_ID
    - S3_SECRET_ACCESS_KEY
<% end %>
```

In `env.clear`, render the storage settings from environment:

```yaml
    ACTIVE_STORAGE_SERVICE: <%= active_storage_service %>
    SCANARR_STORAGE_ROOT: /rails/storage
    SCANARR_BACKUP_ROOT: /rails/storage/backups
    ACTIVE_STORAGE_LOCAL_ROOT: /rails/storage
    S3_ENDPOINT: <%= ENV.fetch("S3_ENDPOINT", "") %>
    S3_BUCKET: <%= ENV.fetch("S3_BUCKET", "") %>
    S3_REGION: <%= ENV.fetch("S3_REGION", "auto") %>
    S3_FORCE_PATH_STYLE: <%= ENV.fetch("S3_FORCE_PATH_STYLE", "true") %>
```

- [ ] **Step 3: Verify the config guard passes**

Run:

```bash
bin/rails test test/configuration/storage_configuration_test.rb
```

Expected:

```text
2 runs, 11 assertions, 0 failures, 0 errors, 0 skips
```

## Task 3: Document User-Facing Setup

**Files:**
- Modify: `README.md`
- Modify: `docs/self-hosting.md`

- [ ] **Step 1: Update README storage wording**

Use this wording in the opening summary:

```markdown
downloads chapters into configurable local or S3-compatible storage
```

Use this wording in Quick Start:

```markdown
Media storage uses the named Docker volume `scanarr_storage_data` by default. To store pages, covers, and backups on a server path or NAS mount, set `SCANARR_STORAGE_PATH=/srv/scanarr/storage` before starting Compose. To avoid storing downloaded media on the app server, set `ACTIVE_STORAGE_SERVICE=s3` and provide the `S3_*` settings for AWS S3, Cloudflare R2, MinIO, or another S3-compatible object store.
```

- [ ] **Step 2: Add Kamal S3 example**

Add this after the Kamal block-storage example:

```bash
export ACTIVE_STORAGE_SERVICE=s3
export S3_ENDPOINT=https://<account-id>.r2.cloudflarestorage.com
export S3_BUCKET=scanarr
export S3_REGION=auto
export S3_FORCE_PATH_STYLE=true
export S3_ACCESS_KEY_ID=...
export S3_SECRET_ACCESS_KEY=...
```

## Task 4: Verify Storage-Critical Paths

**Files:**
- Test: `test/configuration/storage_configuration_test.rb`
- Test: `test/jobs/download_chapter_job_test.rb`
- Test: `test/services/chapter_packager_test.rb`

- [ ] **Step 1: Run targeted config and storage tests**

Run:

```bash
bin/rails test test/configuration/storage_configuration_test.rb test/jobs/download_chapter_job_test.rb test/services/chapter_packager_test.rb
```

Expected:

```text
0 failures, 0 errors
```

- [ ] **Step 2: Run Ruby style checks on touched Ruby files**

Run:

```bash
bin/rubocop config/environments/development.rb test/configuration/storage_configuration_test.rb
```

Expected:

```text
no offenses detected
```

- [ ] **Step 3: Parse the Kamal template in local and S3 modes**

Run:

```bash
ruby -rerb -ryaml -e 'puts YAML.safe_load(ERB.new(File.read("config/deploy.yml")).result, aliases: true).fetch("env").fetch("clear").fetch("ACTIVE_STORAGE_SERVICE")'
ACTIVE_STORAGE_SERVICE=s3 S3_BUCKET=scanarr ruby -rerb -ryaml -e 'config = YAML.safe_load(ERB.new(File.read("config/deploy.yml")).result, aliases: true); puts config.fetch("env").fetch("clear").fetch("ACTIVE_STORAGE_SERVICE"); puts config.fetch("env").fetch("secret").grep(/S3_/).join(",")'
```

Expected:

```text
local
s3
S3_ACCESS_KEY_ID,S3_SECRET_ACCESS_KEY
```

## Follow-Up Features

These are not required for deployment-time remote storage, but they would make storage operations more self-service:

- Admin storage status page showing selected service, local root or S3 bucket, write/read check result, and approximate local disk usage.
- Startup preflight that fails health checks if `ACTIVE_STORAGE_SERVICE=s3` is missing required S3 env vars.
- Blob migration job for moving existing local Active Storage blobs into a new remote service.
- Policy decision for generated variants: keep derived variants in the same Active Storage service or introduce lifecycle guidance for object stores.

## Self-Review

- Spec coverage: The deployment-time path lets users avoid filling app-server disk by setting `ACTIVE_STORAGE_SERVICE=s3`; existing downloads already use Active Storage attachments.
- Placeholder scan: No task uses TBD, TODO, or unspecified edge handling.
- Type consistency: The service name is consistently `ACTIVE_STORAGE_SERVICE`; S3 variables match `config/storage.yml`.
