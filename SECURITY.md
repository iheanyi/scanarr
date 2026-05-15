# Security Policy

## Supported Versions

Security fixes are expected to target the default branch unless a maintained release branch is created.

## Reporting a Vulnerability

Please do not open public issues for vulnerabilities.

Use GitHub private vulnerability reporting if it is enabled for the repository. If it is not enabled, contact the maintainer privately and include:

- Affected version or commit
- Reproduction steps
- Expected impact
- Any logs or screenshots that do not expose secrets

## Self-Hosted Deployments

- Set a stable `SECRET_KEY_BASE`.
- Change the default `SCANARR_DATABASE_PASSWORD` before exposing the app.
- Keep `.env`, `config/master.key`, backups, and storage volumes private.
- If using S3-compatible storage, keep bucket credentials private and back up the bucket separately from the database.
- Put public deployments behind HTTPS.
- Leave `SCANARR_DISABLE_AUTH=false` unless Scanarr is reachable only through a trusted private network.
