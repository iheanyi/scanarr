# Source replacement UX audit — September 5, 2026

## Product contract

A manga stays in the library when its acquisition provider changes. Saved files, canonical chapter IDs, reading progress, and follow settings remain intact. Changing a provider is a preference change and a chapter-discovery operation; it must not silently replace downloaded pages or claim that different editions have identical chapter numbering.

## Findings and implemented changes

- **Single inferred match hid ambiguity.** The default screen progressively checks all eligible providers and retains every distinct plausible match returned by each adapter. Provider filtering is optional. Covers, titles, and available author metadata help users distinguish editions. Each action submits that candidate's own URL. Users can keep the current source when none fits. Distinct exact-title ties are also rejected by unattended auto-linking.
- **Provider-wide discovery delayed the first screen.** Initial navigation makes no provider requests. A page-local queue checks at most three providers concurrently, renders each result as it arrives, and offers individual retries. Discovery does not fetch chapter lists. A 15-second browser deadline and eight-second adapter search timeout keep stalled providers from holding queue slots indefinitely. Navigation aborts active requests and discards stale responses; completed results survive reconnection. Each provider request stays in the Rails executor. Multi-provider service callers retain an overall deadline.
- **Migration terminology obscured the action.** Entry points now say Replace source. The page explains what stays saved, exposes match uncertainty, and removes the redundant confirmation dialog after explicit match review.
- **Bulk matching could search indefinitely and pick an edition without review.** Bulk replacement uses existing mappings only. Unmatched titles link to individual reconciliation. The operation produces a results page instead of a transient toast, and explicit empty selections affect nothing.
- **Follow preference updates were not reliably idempotent.** The replacement now moves to the front even if it was already later in the list. Repeating a switch makes no preference write. Same-source switches are rejected and state is scoped to the current user's follows.
- **Unfollowed series could gain shared provider links before eligibility was checked.** Per-series writes now check ownership of the follow and the origin mapping first.
- **Switching did not refresh the new provider immediately.** Successful changes enqueue a provider-specific chapter check and show a pending first-check message. Download policy remains unchanged.
- **The old provider could still win automatic downloads after switching.** Automatic acquisition now respects the first eligible provider preference, skips disabled providers, and also fills previously discovered releases without files. Failed downloads remain explicit retries.
- **New adapters could receive old-provider chapter URLs.** Acquisition jobs now keep provider, URL, source identifier, and release ID together. Existing canonical chapters gain provider-specific releases while retaining files and progress.
- **Source-scoped library and reader paths could hide saved chapters after switching.** The library retains chapters across providers. Canonical reader links prefer actual saved files, then the user's preferred available release. Navigation uses stable chapter public IDs. Download All and selected downloads use the replacement's own releases and preserve existing downloads.

## Verification

The earlier single-provider check returned five MangaDex candidates for the existing followed [Oshi No Ko] series, including similarly named spinoffs. Desktop and 390px mobile views were inspected; the mobile document had no horizontal overflow. No real series replacement was submitted and workers remained disabled for UI inspection. Integration tests select the second candidate and verify its exact source ID is linked; service and acquisition tests cover stored-file/progress preservation and provider URL consistency.

Initial replacement pass validation: full Ruby suite passed with **1,434 tests and 4,861 assertions**, zero failures/errors/skips. Fourteen changed Ruby files and seven ERB templates passed lint; final acquisition corrections also passed their scoped lint. Log: `tmp/source-replacement-final-full.log`.

Screenshots: `tmp/source-replacement-desktop.png`, `tmp/source-replacement-mobile.png`, `tmp/source-replacement-mobile-matches.png`.

## All-provider follow-up

The user requested cross-provider discovery as the default instead of selecting a provider first. The page now schedules all eligible providers, retains every plausible match in adapter results, groups results by provider, and filters already-loaded groups without refetching. It does not promise exhaustive pagination of each provider catalog. No chapter requests are made while comparing candidates. Useful matches appear in the main result area; empty and failed checks live in an expandable provider-check section with individual retries.

Live follow-up: the page scheduled 24 providers, observed at most three active requests, and received its initial HTML response in about 316 ms locally. Twenty providers completed without reported errors and four reported errors. This is a local UI observation, not a production load benchmark.

All-provider Ruby validation: 1,437 tests, 4,882 assertions, zero failures/errors/skips (`tmp/all-provider-full-tests.log`).

## Remaining limits

- Matching is title-based reconciliation, not chapter-by-chapter edition alignment. Different numbering/page layouts still require user judgment; existing progress records are preserved rather than rewritten onto speculative equivalences.
- Search results do not prove that chapter images are accessible. Unknown chapter counts are explicit, and zero-chapter candidates cannot be selected in the UI.
- A running Sidekiq worker is needed for the post-switch chapter check. Durable per-operation job progress and global acquisition ownership remain broader follow-up work from the codebase audit.
- Source links and stored chapters are shared library metadata; source preferences and reading progress are per user. Full multi-user notification fan-out remains separate work.

Final UI follow-up checks: 14 controller tests and 68 JavaScript tests passed; production asset build passed. Updated screenshots: `tmp/all-provider-desktop.png` and `tmp/all-provider-mobile.png`.
