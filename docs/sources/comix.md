# Comix provider integration

Status: **selected for the curated provider set; runtime support is not implemented**. Comix is separate from Comick. It must not appear as a working, enabled Scanarr source until the acceptance checks below pass.

## Upstream reference

Reviewed on September 5, 2026 against the latest commit affecting the upstream Comix directory, `1ad4b87281681a5f669a6422efd735615d1b831a`:

- [Source configuration](https://github.com/keiyoushi/extensions-source/blob/1ad4b87281681a5f669a6422efd735615d1b831a/src/en/comix/build.gradle.kts): Comix, version code 38, English, mixed content, with `https://comix.to` and `https://comix.ws` mirrors.
- [Adapter](https://github.com/keiyoushi/extensions-source/blob/1ad4b87281681a5f669a6422efd735615d1b831a/src/en/comix/src/eu/kanade/tachiyomi/extension/en/comix/Comix.kt): browse and details can consume embedded `script#initial-data` queries, but chapter enumeration and page retrieval also use a browser runtime and signed API requests.
- [Response types](https://github.com/keiyoushi/extensions-source/blob/1ad4b87281681a5f669a6422efd735615d1b831a/src/en/comix/src/eu/kanade/tachiyomi/extension/en/comix/Dto.kt): manga IDs, chapter pagination, page base URLs, and per-page scrambling flags.
- [Cipher](https://github.com/keiyoushi/extensions-source/blob/1ad4b87281681a5f669a6422efd735615d1b831a/src/en/comix/src/eu/kanade/tachiyomi/extension/en/comix/Cipher.kt) and [image descrambler](https://github.com/keiyoushi/extensions-source/blob/1ad4b87281681a5f669a6422efd735615d1b831a/src/en/comix/src/eu/kanade/tachiyomi/extension/en/comix/Descrambler.kt) are dependencies of the adapter, not optional metadata helpers.

No Comix entry was present in the fetched Keiyoushi `index.min.json` during this investigation. Do not invent a Mihon source ID or assume catalog refresh alone delivers this implementation. Monitor the source directory and its dependencies as well as distribution metadata.

## Observed access challenge

A public request to `https://comix.to/browse` redirected with HTTP 302 to `/@waf/challenge?return=%2Fbrowse`. The final response was **HTTP 200 HTML** with `<title>Security check</title>`, an image rotation CAPTCHA, and a verification request targeting `/@waf/verify`.

This was an actual access challenge, not an empty manga catalog. Detection should use the final challenge URL or a narrow combination of its title and verification markers; status 200 alone cannot establish success. The presence of Cloudflare scripts in an ordinary page is not sufficient evidence of a challenge.

The challenge was not solved or bypassed. No successful live search, chapter enumeration, or image download was established from this environment.

## Required implementation work

1. Evaluate an isolated browser or compatible extension runtime for the source's normal JavaScript execution and an operator-driven challenge flow. Keep its provider session on the server that makes subsequent requests. A CAPTCHA solved in the operator's unrelated browser session does not establish that the worker can access the source.
2. Support the upstream browser bootstrap and signed API workflow, including paginated chapters. Server-rendered initial data alone is insufficient evidence of complete support.
3. Implement and verify the required image transformations. The upstream adapter handles legacy byte transformations and newer grid scrambling, with different request-header requirements. Downloading undecoded bytes or scrambled images must never mark a chapter complete.
4. Bound browser sessions, request concurrency, runtime memory, retries, and timeouts. Stop retrying an interactive challenge automatically and expose an actionable source status.
5. Register a real adapter and canonical manifest entry only after it works. Add upstream revision tracking, adapter version bumps, deterministic regression fixtures, and a release path for both web and workers.

## Acceptance checks before enabling

- Live search and browse return real title results; an unsuccessful challenge produces a clear access error rather than an empty success.
- Title details and complete, bounded chapter pagination work with stable source identities.
- Reading and downloading produce correctly ordered, decoded images across both upstream image formats, including the fourth legacy page and a page marked for grid scrambling.
- A downloaded chapter remains readable without provider access.
- Session expiry, challenge recurrence, worker restart, and a different server network address produce truthful recovery behavior.
- Web and worker processes can share the intended source session without exposing its cookies or signing material to logs or other users.
- Fixture tests cover the challenge response, malformed payloads, pagination termination, and image transformations; live checks remain separate from ordinary CI.

Until these checks pass, Comix remains a planned integration rather than an advertised working provider.
