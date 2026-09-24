# Task fm-20260923-15 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Captain (verbatim): "I found the source of problem of tone settings. The tone toggle in settings
transcription is hidden basically from the UI, because the UI cards are not displaying properly. They
are all meshed together into one unreadable mess. Basically, I can't select proper card settings."

The features exist in code but are unreachable in practice because the Settings sheet's cards overlap or
crush together. Fix the layout so every card is legible, separated and selectable.

## Firstmate spec

**Layout only.** Do not change preferences, defaults, gate logic, prompts or feature behaviour — two other
crews are editing this file's content. Keep the diff to spacing, sizing, scrolling and card chrome.

1. **Reproduce before fixing**: render the Settings sheet offscreen with SwiftUI `ImageRenderer` (no window,
   no TCC permission needed) — or each tab body if the sheet resists — at no fewer than three sizes:
   the current sheet size, ~520×560, ~520×900. Keep the before PNGs and name their path.
2. **Name the mechanism** with evidence: the fixed `.frame(width:height:)` on the TabView squeezing
   content, cards with no minimum heights inside a ScrollView, unwrappable text in fixed-width controls,
   the permission notices added today, content growing past the sheet.
3. **Fix**: cards legible, separated and clickable at every tested size, controls reachable by scrolling,
   no frame overlap, minimum window size sane. Keep the existing card chrome; do not redesign.
4. **Prove it**: after PNGs at the same three sizes, and a programmatic no-overlap assertion as a test if
   you can express it; otherwise state the images are the evidence.

## Verification

- `Scripts/dev-run.sh build` green; unit suite green (`NoMicrophoneGuardTests` is no longer a known flake:
  its one red case was deterministic, and fm-20260923-22 fixed it).
- The app bundle stays **identity-signed and single-binary** after build and after a test run
  (`codesign -d -r-` shows the identity requirement, not a cdhash).

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-15` ONLY, branch
`fm/fm-20260923-15`. Initialize submodules with
`git -c protocol.file.allow=always submodule update --init --recursive`. Never edit the primary checkout's
sources, the captain's preferences, or any other worktree. Do not leave an app instance running.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; before/after renders at three sizes kept and named; the mechanism identified; nothing
outside the Settings layout changed; honest report of anything you could not render.
