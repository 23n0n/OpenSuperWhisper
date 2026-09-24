# Task fm-20260923-13 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Captain (verbatim): "There is also no feature to provide transcription into Polish. It also was demanded."

Reading: the transform was hard-wired Polish → English, so there was no way to produce Polish output when
the speech is English. Implement a **target language** control that generalises the transform to either
direction, and measure the English → Polish quality of the shipped 1.5B model before wiring it.

## Firstmate spec

1. Settings → Transcription → Translation & Tone gains a **target language** picker: English (default) /
   Polish. Persisted as a preference with translation of existing values.
2. Behaviour: spoken language equals target → pass the text through untouched, **no model call**.
   Spoken language differs → translate in the demanded direction. Unknown source language → passthrough.
   Tone composition applies to the target language output.
3. **Measure before wiring**: run English → Polish through the staged
   `qwen2.5-1.5b-instruct-q4_k_m` with real sentences, plus Polish → English for contrast, and report
   quoted outputs and latency. If the 1.5B cannot hold Polish, say so with evidence; still ship the
   control, defaulting to what works.
4. Confine the diff to the transform path, preferences, and that one settings card — `fm-20260923-15` is
   fixing that file's layout and `fm-20260923-17` will add cleanup/reference controls to the same card.

## Verification

- `Scripts/dev-run.sh build` green; unit suite green (`NoMicrophoneGuardTests` is no longer a known flake:
  its one red case was deterministic, and fm-20260923-22 fixed it).
- Tests proving the passthrough rule (no call when spoken == target) and the translation direction.
- The app bundle stays **identity-signed and single-binary** after build and after a test run
  (`codesign -d -r-` must show the identity requirement, not a cdhash).

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-13` ONLY, branch
`fm/fm-20260923-13`. Initialize submodules with
`git -c protocol.file.allow=always submodule update --init --recursive`. Never edit the primary
checkout's sources, the captain's preferences, or any other worktree. Do not leave an app instance running.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch, the picker and its behaviour in place, the quality measurement with quoted outputs, an
honest verdict on English → Polish, and a report of anything unverified.
