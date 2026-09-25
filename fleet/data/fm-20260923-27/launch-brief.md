# Task fm-20260923-27 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Standing requirement, recorded in the fleet backlog: *"the app in-process transform is non-deterministic
(fm-13 measured 8/10 EN->PL outputs differing between identical runs) while the same prompt/model over
llama-server is byte-identical x3 in fm-24 … Same input must give the same output."*

The measurements behind that sentence, kept as stated:

- `fm-20260923-13` measured the **in-process** path: identical input, identical settings, 8 of 10 EN->PL
  outputs differed between runs.
- `fm-20260923-24` measured the **same five backends over `llama-server`**: byte-identical across three
  identical runs each, both directions. The weights and the prompt are therefore not the variable.

## Premise correction — read this before planning anything (2026-09-24)

The original brief of this task concluded that the nondeterminism lives in the app's seed handling. **That
conclusion is falsified**, by a read-only scout that read the delivery tip, and this task was never
dispatched on the old brief. The sampling configuration on the tip is already fully pinned:

- `OpenSuperWhisper/Llama/Llama.swift:270-278` builds the chain `top_k(40) -> top_p(0.95) -> min_p(0.05) ->
  temp(0.2) -> dist(seed = 0)`.
- The chain is constructed per request and freed immediately (`:158-159`), and the KV cache is cleared
  before each run (`:156`), so no sampler state carries between dictations.
- There is no `llama_set_rng_seed` anywhere in the app.
- `libllama/llama.cpp/src/llama-sampler.cpp:1399-1409` seeds `std::mt19937` from that literal seed; only
  `LLAMA_DEFAULT_SEED` randomises (`:340-353`), and nothing passes it.

A fixed seed cannot therefore explain run-to-run drift. The remaining candidate is **backend reduction
nondeterminism** — Metal or threaded accumulations producing different logits for the same input — which no
seed can remove and which greedy sampling (`temp = 0`) would only make rarer, not impossible. Do not spend
this task re-deriving the seed story; spend it on measuring what actually varies.

## Firstmate spec

1. **Reproduce and quantify, do not assume.** Run the in-process transform with one fixed input, the shipped
   settings, at least 5 times per direction, and record the **hash of each output** plus the text. Do it
   twice from separate process launches: a seed that is stable inside one process does not satisfy the
   contract. If the outputs are byte-identical this time, say so with the hashes and treat the drift as
   environment-dependent — the requirement still needs the guard from step 4.
2. **Attribute the cause if drift exists**, by experiment rather than opinion. The two cheap discriminators:
   run the same input with the transform pinned to a single thread, and run it with the Metal/GPU path
   disabled (CPU-only), and see whether either makes the outputs identical. Name which one does, with the
   commands and the hashes.
3. **Decide with evidence, then state it.** If a pinned configuration makes the path deterministic, land it
   and report the latency cost of that configuration for the same inputs. If nothing available makes it
   deterministic, do **not** silently weaken sampling: report the measured spread, state plainly that the
   requirement cannot be met on this backend, and keep the quality settings the product deliberately chose.
   Prefer determinism when its latency cost is small; when it is not, the trade belongs to the captain, so
   present both numbers rather than picking silently.
4. **Pin the contract with a test, in either outcome** — that part is not optional. Beside
   `OpenSuperWhisperTests/LlamaRuntimeIntegrationTests.swift` (which already runs against real weights), add
   a case that runs the transform >=5 times on one input and asserts the outputs are byte-identical. If a
   fix lands, that test must fail against the previous runtime — show it, by reverting only the fix.
   A test that asserts non-empty output is not this test.
5. **Keep the diff in the sampling/backend mechanics.** Do not touch the speech-model path, the language
   gate, the prompt text, or the target-language routing: `fm-20260923-28` owns routing and lands first.
   Rebase on the then-current delivery tip before finishing, and keep `params.noTimestamps = false` and its
   rationale intact.
6. **Machine reality:** this is a 32 GB machine and `fm-20260923-28` may have wired the 5.3 GB 8B backend
   into the app. Measure one direction and one backend at a time; do not hold two engines warm on purpose.

## Verification

- The commands, the per-run output hashes and the texts (or their differing parts), for >=5 runs, in both
  directions, over >=2 process launches.
- If a fix landed: the commands and hashes that show the pinned configuration is identical run to run, and
  the latency before/after for the same inputs. If none landed: the same table showing the spread, with the
  CPU-only and single-thread experiments included.
- The determinism test passing, with the command; and, if there was a fix, the command that shows it failing
  without it.
- `Scripts/dev-run.sh test` green headless on the branch tip, log under `/tmp`; bundle identity-signed
  afterwards (`codesign -d -r-` shows `certificate leaf`, never a bare `cdhash`), single binary.

## Worktree isolation assertion

The old `fm/fm-20260923-27` branch was deleted in the 2026-09-24 branch cleanup (its tip was an ancestor of
the delivery branch; every branch of that day is inside
`fleet-state/archive/all-local-branches-20260924.bundle`). Create a fresh worktree at dispatch, from the
delivery tip after `fm-20260923-28` has landed:

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-27 \
  -b fm/fm-20260923-27 <delivery tip>
git -C <worktree> -c protocol.file.allow=always submodule update --init --recursive
```

Work in that worktree ONLY; never edit the primary checkout's sources, the captain's preferences, or another
crew's worktree. Worktree builds carry bundle id `ru.starmel.OpenSuperWhisper.dev`. **Headless only:** never
launch the app, never `osascript`, never a bare `xcodebuild test`.

## Delegation guard

You are a crew member. Do not spawn subagents. No push, no merge, no branch deletion.

## Definition of done

Committed branch; the reproduction table with hashes; the mechanism named at file:line with the experiment
that isolated it; the decision and its justification, or the honest statement that determinism is not
reachable on this backend with the measured spread; the determinism test in the suite; latency numbers;
`fleet/data/fm-20260923-27/report.md` and a `status.log` line; an honest note of anything you could not
reproduce.
