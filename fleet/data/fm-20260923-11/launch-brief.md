# Task fm-20260923-11 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

The captain's rule that only finished, verified work ships. Task: prove the delivery branch end to end
after the merge rather than trusting the crews' own reports.

## Firstmate spec

_RECONSTRUCTED 2026-09-24: this brief was dispatched with its two spec sections left as
unfilled template placeholders, and the dispatch prompt is not in the fleet records. The scope
below is reconstructed from `data/fm-20260923-11/status.log` and `state/tasks.json`; the outcome is in the
same file. Treat it as a record of what was asked, not as the brief the crew received._

* Deliverable: a from-scratch native build, a signed app, all suites and harnesses, a pre-seeded model
  accepted offline, the Release package payload, and the uninstall proven in a scratch root.

## Worktree isolation assertion

Work in the isolated worktree only (path recorded at dispatch). Never touch the primary checkout
at /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo.

## Delegation guard

You are a crew member. Do not spawn subagents. Ask via your final report when you need more depth.

## Definition of done (mode=local-only)

