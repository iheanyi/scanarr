# Domain Docs

How the engineering skills should consume this repo's domain documentation when
exploring the codebase.

## Layout

Scanarr is a single-context Rails monolith.

Expected locations:

- `CONTEXT.md` at the repo root for domain vocabulary, if present
- `docs/adr/` for architectural decision records, if present
- `docs/decisions.md` for the current lightweight decisions log

If these files or directories do not exist, proceed silently. Do not flag their
absence or create them upfront. Producer skills can create richer context docs
later when terms or decisions are resolved.

## Before exploring, read these

- Read `CONTEXT.md` when present.
- Read relevant ADRs under `docs/adr/` when present.
- Check `docs/decisions.md` for lightweight accepted decisions.
- For implementation conventions, read `CLAUDE.md`.

## Use the glossary's vocabulary

When output names a domain concept in an issue title, refactor proposal,
hypothesis, or test name, use the term as defined in `CONTEXT.md`.

If the concept is missing from the glossary, either avoid inventing new language
or note the gap for a future domain-docs pass.

## Flag decision conflicts

If output contradicts an existing ADR or a decision in `docs/decisions.md`,
surface it explicitly rather than silently overriding it.
