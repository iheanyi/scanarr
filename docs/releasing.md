# Release Management

Scanarr uses SemVer-ish `0.x` releases while APIs, filesystem layout, and storage behavior can still change.

## Versioning

- Start public releases at `v0.1.0`.
- Use patch releases for fixes that should be safe for existing self-hosters.
- Use minor releases for user-visible features, storage behavior changes, dependency upgrades with meaningful runtime risk, or migration-heavy changes.
- Document breaking or manual upgrade steps clearly in the GitHub release notes while Scanarr is still pre-`1.0`.

## Release Flow

1. Make sure `main` is green in CI.
2. Update docs for new settings, migrations, or operational changes.
3. Create an annotated tag:

```bash
git tag -a v0.1.0 -m "Scanarr v0.1.0"
git push origin v0.1.0
```

The release workflow creates a GitHub Release from the tag and generates notes from merged pull requests and commits.

## Docker Images

The supported self-hosting path currently builds a local image from the checked-out repository:

```bash
docker compose build
docker compose up -d
```

Compose tags that local image as `${SCANARR_IMAGE:-scanarr}:${SCANARR_VERSION:-local}`. For a release checkout, self-hosters can set:

```env
SCANARR_VERSION=v0.1.0
```

Publishing registry images is intentionally deferred until there is a clear maintainer workflow for signing, scanning, and update cadence. If registry publishing is added later, release tags should publish:

- `ghcr.io/iheanyi/scanarr:v0.1.0`
- `ghcr.io/iheanyi/scanarr:v0.1`
- `ghcr.io/iheanyi/scanarr:latest`
- `ghcr.io/iheanyi/scanarr:sha-<short-sha>`

`main` can publish `edge` once the registry path exists.

