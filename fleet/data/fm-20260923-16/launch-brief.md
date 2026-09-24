# Task fm-20260923-16 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

The UI-exposure audit (`firstmate-home/data/fm-20260923-14/report.md`) found the reason the captain
repeatedly concluded that delivered features do not exist:

> **G-01** — the status-bar menu has no Settings item. Settings opens only from the main window's gear or
> the app menu (⌘,), so when the window is hidden there is no way into Settings at all.

Fix that gap. It is the cheapest, highest-value item in the audit and it is independent of the branches
editing `Settings.swift`.

## Firstmate spec

1. Add a **Settings…** item to the status-bar menu in `OpenSuperWhisper/OpenSuperWhisperApp.swift` (the
   only file holding the `NSStatusItem` menu), posting the existing `NotificationName+App.openSettings`
   notification — do not invent a second path to the settings view.
2. If the main window is closed or hidden when the item is used, bring it forward first (`.openSettings`
   is consumed by `ContentView`, so the view must exist); say in your report exactly how you handled that.
3. Place it sensibly among the app-level items; do not reorder the rest of the menu.
4. Nothing else: no layout, preferences, permission flow, transform or model-management changes — three
   sibling branches are editing `Settings.swift`.

## Verification

- `Scripts/dev-run.sh build` green; unit suite green (`NoMicrophoneGuardTests` is no longer a known flake:
  its one red case was deterministic, and fm-20260923-22 fixed it).
- Evidence that the item reaches Settings: a build-level check plus, if you can, an automated one (a test
  that posts the notification and asserts the settings-presenting state), or an explicit reasoning chain
  with the exact lines.
- The app bundle stays **identity-signed and single-binary** after build and after a test run
  (`codesign -d -r-` shows the identity requirement, not a cdhash).

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-16` ONLY, branch
`fm/fm-20260923-16`. Initialize submodules with
`git -c protocol.file.allow=always submodule update --init --recursive`. Never edit the primary checkout's
sources, the captain's preferences, or any other worktree. Do not leave an app instance running.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch with the menu item; build and suite green; a short honest report of the diff, the
evidence, and anything unverified.

## Dispatch addendum — 2026-09-24 (read before starting)

The captain's standing instruction for this session: **achieve the goal with as little new code as
possible.** You are finishing work that already exists uncommitted in your worktree; commit it, do not
rewrite it, and add nothing beyond the brief.

- The tree moved. Repo: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`. Your worktree:
  `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-16`.
  Worktree and submodule links were repaired by hand after the move — verify with `git status` before
  you touch anything; if you see a gitdir error, stop and report it rather than trying to fix it.
- Your commit `8e8b92a` predates the delivery tip. **Rebase the branch onto
  `feat/local-translate-tone` @ `5e51124` before finishing** and confirm the tip is an ancestor of your
  branch afterwards. `OpenSuperWhisperApp.swift` was not touched on the delivery branch since your base,
  so the rebase should be trivial; say so in your report either way.
- Delete stale native build caches before building: `rm -rf libllama/build libwhisper/build` (they embed
  old absolute paths and CMake refuses to reuse them after a move).
- Do not touch the sampling path (`OpenSuperWhisper/Llama/*`), the transform prompt, or the Polish-output
  backend: two other decisions are pending there.
- Definition of done adds: the commit is on the rebased branch, `Scripts/dev-run.sh test` is green with the
  bundle identity-signed afterwards, and your report states the commit sha and `git log --oneline -1`.

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

**State found on disk (verified before relaunch):** branch `fm/fm-20260923-16` @ `6aa0266`
"feat(menu): add Settings… to the status-bar menu", worktree clean, parent is the delivery tip `5e51124`
(rebase already done). The occlusion delta you were carrying is **not** in the tree: it is in the repo-level
stash (`git stash list` → `On fm/fm-20260923-16: fm16 uncommitted delta`), pushed before your commit.

**Remaining scope:** (1) read that stash diff (`git stash show -p`) and decide it — if the closed/hidden
main-window case cannot be proven at unit-test level cheaply, leave it stashed and say so; (2) prove the
menu item reaches Settings; (3) `Scripts/dev-run.sh test` green with the bundle identity-signed
afterwards, headless; (4) commit anything left, report the sha and the `git log --oneline -1`.
