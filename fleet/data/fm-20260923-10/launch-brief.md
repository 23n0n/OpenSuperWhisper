# Task fm-20260923-10 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

*From `status.log`:* keystroke output works on the first dictation then stops; the captain's own
recordings show every attempt transcribed and saved at 15:08-15:09.

## Firstmate spec

_RECONSTRUCTED 2026-09-24: this brief was dispatched with its two spec sections left as
unfilled template placeholders, and the dispatch prompt is not in the fleet records. The scope
below is reconstructed from `data/fm-20260923-10/status.log` and `state/tasks.json`; the outcome is in the
same file. Treat it as a record of what was asked, not as the brief the crew received._

* Deliverable: decide between lost Accessibility trust (cdhash identity churn, several copies of the same
  bundle) and an app state-machine bug, with the app instrumented to tell the truth, then fix the proven
  mechanism. Side scopes recorded in FLEET-STATE: remove the Input Monitoring requirement, distinct
  bundle id for dev/CI builds, fix the "Apply tone" caption.

## Worktree isolation assertion

Work in the isolated worktree only (path recorded at dispatch). Never touch the primary checkout
at /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo.

## Delegation guard

You are a crew member. Do not spawn subagents. Ask via your final report when you need more depth.

## Definition of done (mode=local-only)

