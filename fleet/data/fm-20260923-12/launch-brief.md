# Task fm-20260923-12 — OpenSuperWhisper — ship — mode=local-only (DELIVERED, then extended)

## Captain's intent

Captain (verbatim): "The open whisper that it provided me stuck on the accessibility..."

The app refused to work until Accessibility was granted, and the grant would not stick. Make it never
gate, and find out with evidence why an identity-signed app cannot hold the grant on this macOS build.

## Firstmate spec (as delivered)

1. Never gate: the main window always renders; a missing grant is an inline notice stack (Accessibility:
   "Keystrokes are off — grant Accessibility" with a button into Privacy_Accessibility, plus a microphone
   notice) that clears itself from a live re-check; onboarding gains "Skip for now".
2. Determine the mechanism for the lost grant from tccd's own logs; do not guess.
3. Harden the build: `Scripts/dev-run.sh` must remove and fail loudly on a stale split debug layout, and
   `run.sh` must go through the identity-signing path.

## Follow-up added after merge (this is the live work)

Running the unit suite re-signs the app **ad-hoc** in the same derived data, reintroducing the exact
condition that loses the TCC grant. The next launch then reports
`designated => cdhash H"38cfa51d…"` instead of the identity requirement.

- Add a `Scripts/dev-run.sh test` path that runs the suite and **re-signs** the bundle with the identity
  so the app on disk is always launchable and grant-bearing.
- Add a post-build/post-test assertion that the bundle's designated requirement is the identity one and
  fail loudly if it is ad-hoc.
- Evidence: run build → test → check and show `codesign -d -r-` proving the identity requirement survived.
- Optional: let the test path pick up a multilingual model automatically when one exists
  (`~/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin`),
  without making the plain suite depend on the captain's files; otherwise leave the skip and say so.

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-12` ONLY, branch
`fm/fm-20260923-12` (already merged once as `4d1e281`; new commits will be merged again).

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; the test path re-signs and asserts; the codesign evidence in the report; honest note of
anything unverified.
