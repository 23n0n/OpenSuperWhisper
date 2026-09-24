# Task fm-20260924-03 — OpenSuperWhisper — ops (preservation) — no branch

## Captain's intent

_Not raised by the captain: this is the first mate's own finding from the 2026-09-24 reconcile._

_Why it matters: one disk holds the branch, the unlanded branches and the uncommitted work._

## Why this exists

The whole fork exists on one disk:

- the delivery branch `feat/local-translate-tone` at `5e51124` — 160 tracked files, 60 commits ahead of
  `origin/develop` — is **not pushed**; `origin` has no such branch (`git ls-remote origin` shows only the
  upstream-derived refs);
- 15 local `fm/*` branches, three of them unmerged and carrying work found nowhere else
  (`fm/fm-20260923-15` at `5263999` plus five uncommitted files, `fm/fm-20260923-16` at `8e8b92a` plus one
  uncommitted file, plus the `fm/fm-20260923-09` duplicate);
- three worktrees hold **uncommitted** work that no push would capture:
  `OpenSuperWhisper-fm-fm-20260923-15` (5 files), `-16` (1 file), `-17` (7 modified + 3 new);
- `RESUME.md` section 6 is explicit that none of the uncommitted sets was ever built or tested together.

A bundle or push of the branch alone would silently drop exactly the work that is hardest to recreate.
Repo size is 6.6 GB, mostly build products and vendored sources.

## The decision to record (captain)

Option A — **local bundle, no remote change**. `git bundle create` of
`feat/local-translate-tone` plus the three unlanded branches, into `archive/` or another disk, together with
a manifest and a tarball of each worktree's uncommitted changes. Keeps delivery mode `local-only`; protects
against disk loss onto a second volume.

Option B — **publish the branch** to `https://github.com/23n0n/OpenSuperWhisper` on `origin`. This is a
publish, not a merge: it changes what the world can see, so it needs explicit captain authority under the
one-package/one-project rule the captain set at the start of this project. Note the fork is public and MIT;
the branch contains only the app's own sources.

Option C — **both**: bundle first (cheap, immediate), publish later on a deliberate decision.

## Firstmate spec

1. Whichever option: **capture the uncommitted work explicitly.** Per worktree, record
   `git status --porcelain` and a patch or tarball of the modified and untracked files, and write a manifest
   naming the worktree, the branch, the tip commit, and the file list. A snapshot that covers only committed
   history does not satisfy this task.
2. Include the fleet records in the snapshot: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/state/tasks.json`,
   `data/*/launch-brief.md`, `data/*/report.md`, `data/*/status.log`, `RESUME.md`, `FLEET-STATE.md`. The
   handoff's value is in those files and none of them lives in a git repository.
3. Verify the snapshot by restoring it, not by trusting the write: for a bundle, `git bundle verify` and a
   clone into a scratch directory, then compare the branch tips and the delivered file count (`git ls-files |
   wc -l` = 160 at `5e51124`) and the uncommitted file list. Quote the verification output.
4. For option B: push only the named branch, never `--all` or `--mirror`; do not push the `fm/*` branches;
   verify from the fetched ref (`git ls-remote origin feat/local-translate-tone` equals the local tip), not
   from the push output.
5. Do not rewrite or delete anything: no branch deletion, no worktree teardown, no garbage collection. The
   three unlanded branches stay until their work is landed or explicitly dropped by the captain.

## Worktree isolation assertion

No branch, no worktree. This task reads all worktrees and the fleet home, and writes only to the chosen
snapshot destination plus `data/fm-20260924-03/status.log`.

## Delegation guard

You are a crew member. Do not spawn subagents. No merge. Push only under option B and only the one branch
named above.

## Definition of done

A verified, restorable snapshot that includes the delivery branch, the unlanded branches, the uncommitted
sets and the fleet records — or, for option B, the pushed branch verified from the fetched ref — with the
manifest and the verification commands and their output recorded.
