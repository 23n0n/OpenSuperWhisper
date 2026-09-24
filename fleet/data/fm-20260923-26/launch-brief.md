# Task fm-20260923-26 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Derived from the delivery requirement the captain set — dictation must arrive in the focused app by
simulated keystrokes, clipboard untouched — and from the fleet's own coverage accounting at the halt:
*"the delivery path (synthetic keystrokes) deserves a layout-independent test using the active input
source, since 50 of the 54 skips are layout-gated."*

The gap: the path the captain actually uses every day is the least tested part of the suite. At the last
recorded full run (delivery tip, 2026-09-23) the skips were:

| suite | skips | reason |
|---|---|---|
| `ClipboardUtilPasteIntegrationTests` | 35 | needs an installed input-source layout |
| `ClipboardUtilKeyboardLayoutTests` | 9 | same |
| `KeyboardLayoutProviderTests` | 6 | same |
| `PCMRecordingTests` | 1 | needs `OSW_TEST_MICROPHONE=1` + mic authorization |
| `WhisperTurboRegressionTests` | 2 | needs `OSW_TEST_TURBO_MODEL` |

50 of 54 skips are therefore the same environmental accident — the machine does not have the specific
keyboard layouts the tests hard-code. Delivery coverage collapses on any normal machine, which is exactly
where the app ships.

## Firstmate spec

1. **Read what the skipped tests actually prove** (`OpenSuperWhisperTests/OpenSuperWhisperTests.swift`,
   `KeyboardSimulatorTests.swift`, and the `Utils/KeyboardSimulator.swift` +
   `Utils/KeyboardLayoutProvider.swift` they exercise). State per test what would break in delivery if the
   test never ran.
2. **Add a layout-independent delivery test** that types through the **active** input source rather than a
   hard-coded one: resolve the current source at run time, drive the real keystroke path, and assert the
   delivered text. It must be deterministic, offline, and safe to run in CI.
3. **Prefer proving delivery end to end over unit-shape assertions.** A test that asserts a call was made,
   or that a string was returned, does not cover the path the captain depends on. If a true end-to-end
   assertion needs a receiver, create the smallest one that can host real key events and say what it does
   not cover.
4. **Do not delete or weaken the existing layout-gated tests.** They are legitimate coverage for the layouts
   they name; make them skip with a stated reason if their reason is currently implicit, and cross-reference
   the new test as the one that always runs.
5. **Do not** change delivery behaviour to make it testable unless the change is itself a defect fix; if you
   find a real defect on the path, report it with the evidence and fix it only if the fix is contained.

## Verification

- The new test fails when the delivery path is deliberately broken (name the mutation you used to prove it)
  and passes on the unmodified branch. Quote the command and the output.
- The new test runs on a machine without any of the hard-coded layouts — state how you established that
  (e.g. it passes with the layouts the old tests skip on).
- Full suite green; the skip count is reported before and after, with every remaining skip's reason.
- The app bundle stays identity-signed and single-binary.

## Worktree isolation assertion

Create the worktree at dispatch:

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-26 -b fm/fm-20260923-26 <delivery tip>
```

then `git -c protocol.file.allow=always submodule update --init --recursive` inside it. Work in that
worktree ONLY; never edit the primary checkout's sources, the captain's preferences, or another crew's
worktree. The worktree build carries bundle id `ru.starmel.OpenSuperWhisper.dev`.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; a delivery test that runs without the hard-coded layouts and fails when the path is broken;
the remaining skips each carrying an explicit reason; an honest statement of what the new test does not
cover.
