# Task fm-20260923-08 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

The project rule the captain set at the start, restated for this task: *"the app must ship as ONE
installable/uninstallable package, idempotent, no external parts connected by goodwill."* Scope as
briefed by the first mate (fm-20260923-07 architecture study): vendor llama.cpp on a single unified
ggml, both engines in-process, weights downloaded on first use with sha256 into app-owned storage, one
.pkg plus one idempotent uninstall.

The continuation spec the crew actually worked from is preserved below under "Relaunch 1".

## Firstmate spec

_RECONSTRUCTED 2026-09-24: this brief was dispatched with its two spec sections left as
unfilled template placeholders, and the dispatch prompt is not in the fleet records. The scope
below is reconstructed from `data/fm-20260923-08/status.log` and `state/tasks.json`; the outcome is in the
same file. Treat it as a record of what was asked, not as the brief the crew received._

* Deliverable: the one-package path above, with the in-process decode proven against real weights (the
  two-red-tests blocker), plus the relaunch priorities listed below.

## Worktree isolation assertion

Work in the isolated worktree only (path recorded at dispatch). Never touch the primary checkout
at /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo.

## Delegation guard

You are a crew member. Do not spawn subagents. Ask via your final report when you need more depth.

## Definition of done (mode=local-only)


## Relaunch 1 — continuation (same task id, same worktree, retries=1)

Your first pass committed `30cf28e` and reported PARTIAL. The work is not landed; the branch stays
yours. Continue from that commit in the same worktree. Priorities in order:

1. **Prove the in-process decode path (top priority).** `LlamaRuntimeIntegrationTests`'s two
   real-weights tests must pass — `translatesPolishThroughTheRealModel` and
   `doesNotCarryOneDictationIntoTheNext`. Your own note says they fail within 0.000 s of starting,
   consistent with the test host dying in the decode path rather than a content assertion. Diagnose
   it properly and show the mechanism:
   - capture the abort/exception from the test run and from `~/Library/Logs/DiagnosticReports` if the
     host crashed, and quote the decisive lines;
   - bisect: CPU-only (`n_gpu_layers = 0`) versus Metal, to separate a Metal/ggml-Metal fault from a
     core decode fault;
   - check the obvious decode-side suspects against llama.cpp's own `llama-server` defaults you
     mirrored: context size versus prompt length, KV cache state between requests, sampler chain
     construction/ordering, chat-template output and the tokenizer path (budget/n_ctx handling after
     the negative-return-size fix you already made), and any `llama_batch`/logits index mismatch;
   - state which hypothesis the evidence supports and what you changed.
   Do not land with those tests red, and do not delete or skip them to go green.
2. **Measure, with the probe that exists but was never built**: compile and run your
   `/tmp/fm08/probe.cpp` co-residency probe and report resident memory with both engines warm and the
   in-process transform latency against the HTTP baseline (`Scripts/verify-transform.sh` numbers).
3. **Release path**: produce a Release build and a Release `.pkg`, report the binary and package
   sizes, and run `Scripts/verify-packaging.sh` against the Release app.
4. **Loose ends from your report**: `make_release.sh` should emit the `.pkg` rather than only the DMG
   path (or state why not), the Cask `zap` list, and `docs/release_build.md` if that file exists in
   this repo.
5. **Signing**: a sibling task (`fm-20260923-09`) is producing a self-signed `OpenSuperWhisper Local
   Dev` identity plus `Scripts/dev-sign.sh`. If it is present by the time you get here, use it and
   show the identity-based `codesign -d -r-` output for the app in the package payload. If not, keep
   your signing step parameterised and say so.

Correction (2026-09-23, fm-20260923-22): `NoMicrophoneGuardTests.testIndicatorViewModel_startRecording_withNoMicrophone_showsNoMicrophoneState`
was recorded here as "a pre-existing flake". It was never a flake — it failed deterministically, and the
cause was found and fixed on the delivery branch by fm-20260923-22. A red case in this suite is a defect
to diagnose, not noise to step over.

Report the same way: outcome, exact commands, measured numbers, what is still unproven, honest
failure. Nothing lands until the suite is green and the decode path is demonstrated.
