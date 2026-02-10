# Development Workflow

## Local test user policy

To keep local profiling/testing repeatable, use a dedicated development user instead of mutating arbitrary records.

### Default development seed user

`db/seeds.rb` creates an idempotent dev-only user when:

- `Rails.env.development?`
- `SCANARR_SEED_DEV_USER=1` (default)

Defaults:

- `username`: `perfuser`
- `email`: `perfuser@local.scanarr`
- `password`: `password123`

Override via environment variables before running seeds:

```bash
SCANARR_DEV_USERNAME=myuser \
SCANARR_DEV_EMAIL=myuser@local.scanarr \
SCANARR_DEV_PASSWORD='my-password' \
bin/rails db:seed
```

Disable dev user seeding:

```bash
SCANARR_SEED_DEV_USER=0 bin/rails db:seed
```

### One-off console upsert (no schema/app changes)

When you need a test account quickly, use this idempotent command:

```bash
bin/rails runner "u=User.find_or_initialize_by(username: 'perfuser'); u.email='perfuser@local.scanarr'; u.password='password123' if u.new_record? || u.password_digest.blank?; u.role=:admin if u.respond_to?(:role); u.save!"
```

This avoids ad-hoc data churn and keeps local test access predictable.
