# Task fm-20260923-22 — OpenSuperWhisper — ship — mode=local-only

## Why

`NoMicrophoneGuardTests.testIndicatorViewModel_startRecording_withNoMicrophone_showsNoMicrophoneState`
fails **deterministically** (0.004 s) at the delivery tip and at `550d9d1` — this is not a flake, whatever
the earlier notes say. Every crew brief and the Readme have been calling it "the known
`NoMicrophoneGuardTests` flake"; that description is wrong and must go. A red test on the delivery branch
is either a real defect in the app or a broken test, and both are fixable.

Observed: the test's precondition (`service.getActiveMicrophone()` is nil with `selectedMicrophone` and
`currentMicrophone` both nil) passes; the assertion that fails is that `IndicatorViewModel` reported
`.noMicrophone` after `startRecording()` — the state is something else. Its sibling
`testContentViewModel_startRecording_withNoMicrophone_doesNotStartRecording` passes, so the two recording
entry points behave differently.

## Firstmate spec

1. Diagnose before changing anything: run the test isolated, and read `IndicatorViewModel.startRecording`
   and `ContentViewModel.startRecording` side by side. Establish whether the indicator path
   - never consults the microphone, or
   - consults it asynchronously (state settles after the synchronous assertion), or
   - consults it through a different source that the test's injection does not reach.
   Cite file:line for the actual control flow.
2. Fix **the side that is wrong**, with evidence for that choice:
   - If the app can fake a recording state with no microphone, fix the app — the guarantee the test pins is
     user-visible and correct: no microphone must never look like "recording".
   - If the app is right and the test is asserting asynchronously-produced state synchronously, fix the test
     to wait for the settle (deterministically, no sleep-and-hope) and keep the assertion.
   Do not delete the assertion, and do not weaken it into a tautology.
3. Purge the false "known flake" label where it appears: `Readme.md`, `Scripts/dev-run.sh` comments, task
   briefs under `firstmate-home/data/`, and any test documentation. The suite must stop advertising a real
   red test as acceptable.
4. Keep the diff to the indicator/content recording path, its tests, and those documentation lines.

## Verification

- The previously failing test passes, reproducibly: run it at least five times in a row, and the whole
  `OpenSuperWhisperTests` target once, showing the counts.
- Every other test that was green stays green; state any test you could not run.
- The bundle ends **identity-signed and single-binary**: finish with `Scripts/dev-run.sh test` (it re-signs
  even when the suite fails) and show `codesign -d -r-` output — a bare `cdhash` is a failure.
- Note for context: the multilingual fixture at `.build/test-models/ggml-tiny.bin` is intentionally absent
  right now (an investigation owns that model's long-form behaviour), so some language/long-form cases skip.
  That is expected; do not "fix" it by adding the fixture.

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-22` ONLY, branch
`fm/fm-20260923-22`, from the current delivery tip. Initialize submodules with
`git -c protocol.file.allow=always submodule update --init --recursive`. Never edit the primary checkout's
sources, the captain's preferences, or any other worktree. Do not leave an app instance running.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; the diagnosis with file:line; the corrected side fixed; the false flake label purged; the
five-run evidence and the suite counts; honest notes on anything unverified.
