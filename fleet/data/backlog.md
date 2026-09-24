# Backlog

Reconciled 2026-09-24 after the workspace consolidation. Delivery branch
`feat/local-translate-tone` @ `5e51124`, clean, unpushed. Ledger: `state/tasks.json`. Handoff: `RESUME.md`.
Workspace root: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork` (see its `README.md`).

Standing instruction for this session (captain): **finish with as little new code as possible.** Prefer
landing work that already exists over writing more, and prune what does not pay for itself.

## Done 2026-09-24

- [x] `fm-20260924-03` preservation — verified bundle + per-worktree patches + record tarball.
- [x] `fm-20260924-04` consolidation — one root (`repo/ worktrees/ fleet/ docs/ archive/`); five merged
      worktrees removed (~11 GB); worktree and submodule links repaired; record paths rewritten.
- [x] `fm-20260923-27` **premise falsified, not dispatched** — the in-process sampler is already
      seed-pinned and rebuilt per request (`Llama.swift:270-278`, `:158-159`). The residual run-to-run
      difference, if it reproduces, is backend reduction nondeterminism, which a seed cannot fix. Measure
      once against real weights, or drop the requirement. No code written.

## Open — in the order this session will work them

Rewritten 2026-09-24 after the three ready branches were merged into the delivery branch (`319f3a3`).
Tasks 1-4 of the previous list are landed and measured; what is actually left:

1. **fm-20260923-28** ship — Qwen3-8B as the Polish-output backend (the captain's decision). Now the top of
   the queue on evidence: the fm-17 measurement showed **en→pl output on the shipped 1.5B invents words**,
   and Polish output is the direction the 8B was chosen for. Same Settings card and model files as the
   landed model-management work.
2. **fm-20260923-27** ship — in-process determinism. Premise corrected 2026-09-24 (never dispatched): the
   sampler is already seed-pinned (`Llama.swift:270-278`, `dist(seed = 0)`, chain rebuilt per request), so a
   fixed seed cannot explain run-to-run drift. If it still drifts, the cause is backend reduction
   nondeterminism. Decide: measure once against real weights, or drop the requirement.
3. **fm-20260923-26** ship — layout-independent delivery test. 50 of the 53 suite skips are keyboard-layout
   gated, so the path the captain uses daily is the least covered. Test-only code; lowest product value of
   the open set. Related, cheap: the Turkish case's gate is environment-dependent and its green is weak
   (`FLEET-STATE.md`, skip reconciliation).
4. Optional measurement, not registered — the 14B rung (~9 GB) between the 8B and the 30B-A3B.

### Loose ends that are not tasks

- **The fm-16 occlusion delta** stays in `stash@{0}` (`On fm/fm-20260923-16: fm16 uncommitted delta`): its
  premise is a GUI-timing claim that the test host cannot exercise, so proving it needs the captain's
  screen, not a crew.
- **The merged surfaces have never been looked at by a human** — status-bar `Settings…`, the new Settings
  cards, the last-dictation card. The suite covers them; the eye does not. Needs the captain's screen.
- **The delivery branch is still unpushed.** Publishing is a captain decision.
- Duplicate branch `fm/fm-20260923-09` @ `98c63fd` (its change is already in the delivery tree) and the
  crew's pre-rebase safety branch `fm-25-prerebase-backup` @ `51f1bb9` can be deleted when convenient.
  Neither is in `archive/opensuperwhisper-20260924.bundle` (the bundle predates them).

## Shipped — merged into the delivery branch, do not re-litigate

- `fm-20260923-01`..`-05`, `-08`..`-13`, `-15` (layout half), `-18` (folded into `-17`), `-20`..`-23`.
  See `FLEET-STATE.md` for the per-task detail; every branch is inside `archive/`.

## Preserved, not merged

- branch `fm/fm-20260923-15` @ `5263999` + 5 uncommitted entries (this is the `fm-20260923-25` assignment).
- branch `fm/fm-20260923-16` @ `8e8b92a` + 1 uncommitted file.
- branch `fm/fm-20260923-17` @ `32aacc0` + 7 modified + 3 new files, uncommitted.
- branch `fm/fm-20260923-09` @ `98c63fd` — one unmerged commit whose change is already in the delivery
  tree (duplicate; inspect then delete, never merge).
- All of the above, plus the delivery branch, are in `archive/opensuperwhisper-20260924.bundle`.

## Machine configuration as left

Speech model `ggml-large-v3-turbo.bin` (multilingual) — never `ggml-tiny.en.bin` with language `auto`;
transform in-process 1.5B, `transformUseExternalEndpoint=0`. Details and cautions: `RESUME.md` §3, §8.
