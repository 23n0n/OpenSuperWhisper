# Task fm-20260923-21 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Derived from the fleet's own defect record: crew worktrees share the `ru.starmel.OpenSuperWhisper.dev`
preference domain, so parallel test processes race - `TransformBackendTests.testStoredSwitchChoosesTheBackend`
flaked once with "Czesc" != "from the endpoint". Tests must not fight over the user's preferences.

## Firstmate spec

_RECONSTRUCTED 2026-09-24: this brief was dispatched with its two spec sections left as
unfilled template placeholders, and the dispatch prompt is not in the fleet records. The scope
below is reconstructed from `data/fm-20260923-21/status.log` and `state/tasks.json`; the outcome is in the
same file. Treat it as a record of what was asked, not as the brief the crew received._

* Deliverable (as achieved, `95c7e2c`, executed by the fm-20260923-12 crew): per-process scratch
  preference store behind the `AppPreferences.defaults` seam.

## Worktree isolation assertion

Work in the isolated worktree only (path recorded at dispatch). Never touch the primary checkout
at /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo.

## Delegation guard

You are a crew member. Do not spawn subagents. Ask via your final report when you need more depth.

## Definition of done (mode=local-only)

