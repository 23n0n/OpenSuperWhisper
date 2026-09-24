# Task fm-20260923-09 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

*From `status.log`:* the captain reported Accessibility granted but not detected by the app; the root
cause turned out to be an invalid bundle signature plus a cdhash-based ad-hoc designation. The ask: make
the local build loop TCC-stable so a permission grant survives a rebuild.

## Firstmate spec

_RECONSTRUCTED 2026-09-24: this brief was dispatched with its two spec sections left as
unfilled template placeholders, and the dispatch prompt is not in the fleet records. The scope
below is reconstructed from `data/fm-20260923-09/status.log` and `state/tasks.json`; the outcome is in the
same file. Treat it as a record of what was asked, not as the brief the crew received._

* Deliverable (as achieved, `81d892b`): a self-signed `OpenSuperWhisper Local Dev` identity in its own
  keychain, `Scripts/dev-sign.sh` producing an identity-based Designated Requirement that survives
  rebuilds, `dev-run.sh` without the debug-dylib stub, and a Readme section.

## Worktree isolation assertion

Work in the isolated worktree only (path recorded at dispatch). Never touch the primary checkout
at /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo.

## Delegation guard

You are a crew member. Do not spawn subagents. Ask via your final report when you need more depth.

## Definition of done (mode=local-only)

