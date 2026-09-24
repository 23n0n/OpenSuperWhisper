# Task fm-20260923-25 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Verbatim: "All features have to be explicitly shown in the UI."

He has twice concluded that delivered features do not exist because the UI never showed them — first a
tone toggle that was there in code, then a translation direction. The audit in
`firstmate-home/data/fm-20260923-14/report.md` walked 80 user-affecting behaviours and found 17 gaps; this
task closes the ones that are still open after today's merges.

## Firstmate spec — the specific gaps

_Heading renamed 2026-09-24 for consistency with the other briefs; the crew worked from this text as
"Scope"._

Close these, each as a control the user can operate or a state the user can see. Tab and section are named;
use the existing card chrome.

| id | gap | where |
|---|---|---|
| G-02 | Accessibility / keystroke-injection state invisible in Settings (the warning exists only for some trigger modes) | Shortcuts → new Permissions section |
| G-03 | Microphone permission state absent from Settings entirely | same Permissions section |
| G-04 | Speech models can be downloaded but never removed; only the transform model has a Remove control | Model tab, per row (+ size freed) |
| G-05 | Models installed on disk but not in the catalogue are never listed, so the tab can show no current model | Model tab ("Installed models (N)", "Selected model") |
| G-06 | No visible verification: transform weights verify a pinned SHA-256 silently; speech downloads are HTTP-status-checked only | Model tab rows + the transform model row ("Verified ✓" / "Verify") |
| G-07 | Silent fallback to the bundled model when the selected model file disappears (log only) | Model tab status line |
| G-10 | Delivery mechanism undescribed: label says "paste", mechanism is synthetic keystrokes, clipboard untouched, Accessibility required | Transcription → Clipboard & Paste subtitle |
| G-11 | "Debug Mode" is a visible but inert toggle (preference never read); `qwen3Variant` is a stored key with neither UI nor reader | Advanced → Debug Options — wire it or drop both |
| G-12 | `hasCompletedOnboarding` cannot be reset from the UI, so the welcome flow cannot be re-shown | Advanced |

## Explicit non-goals

- **Do not touch the Transcription → Translation & Tone card.** `fm-20260923-17` is rebuilding it right now
  (clean-up pass, glossary, English-only-model guard, detected-language display). Leave that card and the
  transform prompt path to that crew.
- Do not change defaults, the permission flow, the transform, or speech recognition behaviour. This is
  exposure: showing and operating what already exists.
- Do not add new features beyond making these visible.

## Verification

- `Scripts/dev-run.sh test` green; the app left **identity-signed and single-binary** (`codesign -d -r-`
  shows the identity requirement, never a cdhash).
- Tests must not read or write the user's preferences — `AppPreferences.defaults` is the test seam, and
  fixtures resolve their own models.
- For G-04, G-06 and G-07 especially: prove the behaviour with a real check, not a label — e.g. remove a
  downloaded model and show it is gone from disk; verify a model and show the checksum comparison; point the
  selection at a missing file and show the surfaced message. State the exact commands and output.
- Since you are editing `Settings.swift` while another crew edits one card of it: rebase on the current tip
  before finishing and keep your diff out of their card.

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-15` ONLY (your existing worktree),
branch `fm/fm-20260923-15`, merged into the delivery branch already; commit on top. Never edit the primary
checkout's sources, the captain's preferences, or another crew's worktree. Do not leave an app instance
running.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; each listed gap closed with its evidence; the non-goals respected; an honest report of
anything you could not make visible or chose to leave alone.

## Dispatch addendum — 2026-09-24 (read before starting)

The captain's standing instruction for this session: **achieve the goal with as little new code as
possible.** The work already exists uncommitted in your worktree (5 entries + the committed `5263999`).
Finish and commit it; add nothing beyond the brief.

- The tree moved. Repo: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`. Your worktree:
  `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-15`.
  Worktree and submodule links were repaired by hand after the move — check `git status` first; a gitdir
  error means stop and report, do not improvise a repair.
- **Rebase onto `feat/local-translate-tone` @ `5e51124` before finishing.** Your base is `32aacc0`, which
  predates the long-form audio fix. One conflict is known and must be resolved in the delivery tip's
  favour: your `OpenSuperWhisper/Engines/WhisperEngine.swift` still contains
  `params.noTimestamps = !settings.showTimestamps`, while the tip has `params.noTimestamps = false` plus
  its 13-line rationale (repo `OpenSuperWhisper/Engines/WhisperEngine.swift:393-409`). Your `debugMode`
  hunk (`params.debugMode = settings.debugMode`, worktree lines 388-391) sits inside that same context
  window. **Keep the tip's line and its rationale; re-apply only your two-line addition.** Reverting that
  line silently re-introduces the audio-loss bug the branch exists to fix — it is the one thing in this
  rebase that must not go wrong, and your report must quote the final state of that line.
- Delete stale native build caches before building: `rm -rf libllama/build libwhisper/build` (they embed
  old absolute paths and CMake refuses to reuse them after a move).
- `WhisperModelManager.swift` and the `Settings.swift` model-management block are yours; the
  Transcription → Translation & Tone card belongs to `fm-20260923-17` (sequential, after you).
- Do not touch the sampling path (`OpenSuperWhisper/Llama/*`), the transform prompt, or the Polish-output
  backend: two other decisions are pending there.
- Definition of done adds: commits on the rebased branch, `Scripts/dev-run.sh test` green with the bundle
  identity-signed afterwards, the commit shas listed, and the quoted `noTimestamps` line.

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

**State found on disk (verified before relaunch):** branch `fm/fm-20260923-15` @ `a123947` (G-02/G-03/G-10/
G-11/G-12), previous `8bcc8f6` (G-04..G-07), both already on top of `5e51124`. Dirty: `Settings.swift` (12
lines) and `Readme.md` (10 lines) — your last two polish edits, never built.

**Remaining scope:** (1) finish those two files; (2) `Scripts/dev-run.sh test` green, headless, with the
bundle identity-signed afterwards; (3) commit; (4) report the shas, the diffstat and the quoted
`params.noTimestamps` line from your `WhisperEngine.swift`.
