# Task fm-20260924-01 — OpenSuperWhisper — scout (measure + record) — no branch

## Captain's intent

_Not raised by the captain: this is the first mate's own finding from the 2026-09-24 reconcile._

_Why it matters: the flagship fix of the branch must stop resting on prose._

## Why this exists

`fm-20260923-23` is the flagship correctness fix on the delivery branch (`5e51124`): whisper.cpp was
advancing the seek a full 30 s per window and discarding untranscribed audio, because
`noTimestamps = !showTimestamps` was true by default. The fix is in the tree (`aaddc83`, with
`LongFormTranscriptionTests.swift` rewritten) and `ce1619e` removed the calibrated-model skip from
`Scripts/dev-run.sh`.

The handoff asserts the result — *recall now 0.9932 EN / 0.9873 RU, and the suite green at 381 tests /
327 passed / 0 failed / 54 skipped* — but **no fleet file contains that evidence**: `fm-20260923-23` has no
`status.log` and no `report.md`, and the last recorded suite run in `FLEET-STATE.md` is the older
379/325/0/54 at `32aacc0`. The flagship fix currently rests on one sentence of prose.

Deliverable: `data/fm-20260924-01/report.md`, plus the corrected numbers written back into
`RESUME.md` and `FLEET-STATE.md`.

## Firstmate spec

1. **Re-establish the fixture.** `LongFormTranscriptionTests` resolves its model from
   `.build/test-models/ggml-tiny.bin` and the probe is a **size check**, so the fixture must be a **hard
   link** to a real model, not a symlink (Foundation stats the link and the size probe fails). The primary
   checkout's `.build/test-models/` is currently empty — recreate it before running anything.
2. **Run the long-form tests against the multilingual model** (`ggml-large-v3-turbo.bin`, the model the
   captain actually uses) and capture the **actual English and Russian transcripts**, not just pass/fail.
   Report the recall numbers for both languages from the run you performed, and say whether they match the
   0.9932 / 0.9873 asserted in the handoff.
3. **Record the full suite as it stands on the delivery tip**: the exact command, the totals
   (total / passed / failed / skipped) and every remaining skip's reason. Reconcile the count with the
   379/325/0/54 recorded at `32aacc0`: state the delta and explain it from the commits between the two runs.
4. **Correct the records** in place: `RESUME.md` section 4 item 6 and `FLEET-STATE.md` get the measured
   numbers with the command that produced them; the `fm-20260923-23` row in `state/tasks.json` loses the
   "EVIDENCE GAP" note if and only if the gap is now closed by your report. Write a `status.log` line for
   this task either way.
5. **Report honestly if you cannot execute.** If the measurement is not reachable — the fixture will not
   resolve, the model is absent, the run refuses to complete — say so as the deliverable's first line
   instead of substituting code inspection for a measurement. Do not run a bare `xcodebuild test`; it leaves
   the bundle ad-hoc signed and breaks the Accessibility grant.

## Dispatch addendum — 2026-09-24 (read before starting)

**You run in a worktree, not in the primary checkout** — this overrides the isolation paragraph above. The
captain's app runs from the primary checkout (`build/Build/Products/Debug/OpenSuperWhisper.app`, bundle id
`ru.starmel.OpenSuperWhisper`); a test run there rebuilds and re-signs that bundle, which breaks its
Accessibility grant if the app is relaunched mid-run. Your worktree is already created and its submodules
are initialised:

    /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260924-01
    branch fm/fm-20260924-01 @ 5e51124 (the delivery tip; do not commit source changes, do not move it)

Worktree builds carry bundle id `ru.starmel.OpenSuperWhisper.dev`, so nothing you do can disturb the
captain's instance. Do not start the app; do not leave one running. The repo moved today, and I repaired
the SwiftPM artifact paths and the git submodule links by hand — if you hit

    error: There is no XCFramework found at '...NemoTextProcessing.xcframework'

or a gitdir/submodule error, stop and report it rather than improvising.

Everything else in the brief stands, in particular: the fixture must be a **hard link** to a real model
(`ln ~/Library/Application\ Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin
.build/test-models/ggml-tiny.bin` — a symlink fails the size probe), run the long-form cases against the
multilingual model and capture the actual English and Russian transcripts, record the suite totals with
their skip reasons, reconcile the delta against the 379/325/0/54 run at `32aacc0`, and report honestly as
your first line if a measurement is not reachable. `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
first, and never a bare `xcodebuild test`.

## Delegation guard

You are a crew member. Do not spawn subagents. No push. No merges.

## Definition of done

`data/fm-20260924-01/report.md` with: the command(s) run, the transcripts or recall numbers obtained, the
suite totals with skip reasons, the delta against the `32aacc0` run explained, and either the corrected
records or an explicit statement of what blocked execution.

## Relaunch addendum 2 — 2026-09-24 (read before starting)

This task is a **deterministic relaunch**. The previous crew was killed mid-flight at 08:32 by a terminal
hangup (SIGHUP): a crew in a sibling task drove the GUI app with `open -n`, `osascript`/System Events
keystrokes and `screencapture`; one keystroke landed on the frontmost window — the agent's own terminal —
and the whole session, all four crews included, died with the tty. Nothing about that was your fault and
nothing you had written is lost: every byte of your work is on disk (state below).

**HEADLESS IS MANDATORY — this overrides anything above that assumes a visible app.**

Forbidden, no exceptions: `open`; `osascript` in any form; System Events / Accessibility automation;
synthetic keystrokes; `screencapture`; launching any OpenSuperWhisper build; `Scripts/dev-run.sh` with **no
mode argument** (it `exec`s the GUI app at the end); touching Terminal or iTerm at all.

Expected: `Scripts/dev-run.sh build|test`, `xcodebuild`, `git`, `python3`, text tools, unit and snapshot
tests. Redirect long output to a file (`> /tmp/<task>-step.log 2>&1`) and tail it. Never leave a process
attached to the foreground of a terminal.

If a check genuinely needs the app on screen, do **not** improvise it: state it in your report as
"needs the captain's screen" and stop that thread. The first mate runs screen-visible checks, not crews.

**State found on disk (verified before relaunch):** nothing was produced. Your worktree
`worktrees/OpenSuperWhisper-fm-fm-20260924-01` is clean at `5e51124`, the fixture **is** already in place
(`.build/test-models/ggml-tiny.bin`, a real 1.6 GB hard link to `ggml-large-v3-turbo.bin`, link count 2),
and your previous build log is at `data/fm-20260924-01/logs/longform-run.log`, which ends at
`** BUILD INTERRUPTED **` because the session died — the build, not your approach, was the problem.

**Remaining scope:** the whole brief. Order that keeps the terminal alive and the run honest:
(1) `rm -rf libllama/build libwhisper/build` then `Scripts/dev-run.sh test` with output to
`data/fm-20260924-01/logs/suite.log` (this is long — the native engines rebuild from scratch; write the log,
do not hold it in the tool output); (2) the long-form EN/RU re-measurement against the multilingual model,
transcripts captured into `data/fm-20260924-01/logs/`; (3) the report with totals, skip reasons and the
delta against 379/325/0/54 at `32aacc0`; (4) correct `RESUME.md` §4 item 6 and `FLEET-STATE.md` in place.
Never a bare `xcodebuild test`, never the GUI app, never `osascript`.
