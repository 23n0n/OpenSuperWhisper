# Task fm-20260923-27 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Standing requirement recorded in the fleet backlog: *"the app in-process transform is non-deterministic
(fm-13 measured 8/10 EN->PL outputs differing between identical runs) while the same prompt/model over
llama-server is byte-identical x3 in fm-24 … Same input must give the same output."*

Context, measured, not assumed:

- `fm-20260923-13` measured the **in-process** path: identical input, identical settings, 8 of 10 EN->PL
  outputs differed between runs.
- `fm-20260923-24` measured the **same five backends over `llama-server`**: byte-identical across three
  identical runs each, both directions. The model and the prompt are therefore not the variable.
- Conclusion carried by the fleet: the nondeterminism is in the app's in-process sampling path (seed
  handling in the sampler), not in the weights and not in the prompt.

## Firstmate spec

1. **Read the in-process sampling configuration first** (`OpenSuperWhisper/Llama/TransformRuntime.swift`,
   `Llama.swift`) and state, with file:line: the sampler chain, the seed actually set, temperature, top-k /
   top-p, and whether a seed is set at all. Name the mechanism before changing anything.
2. **Fix the mechanism, not the symptom.** The contract is: the same input, the same settings, and the same
   model produce the same output, in-process, across processes. Acceptable mechanisms include setting an
   explicit seed on the sampler/chain and constructing the sampler per request rather than reusing a chain
   that carries state; greedy or temperature 0 if that is what the product wants. If a non-zero temperature
   is deliberately kept for output quality, say so and prove determinism by seed, not by removing sampling.
3. **Prove it with execution**, not with code inspection: run the identical request at least 5 times in the
   in-process path, in both directions (PL->EN on the 1.5B, EN->PL on whichever backend is installed), and
   show byte-identical outputs. Show the same check over two separate process launches, because a
   per-process seed that is stable within a process does not satisfy the contract.
4. **Pin it with a test** where the suite can host it: the existing in-process integration tests
   (`LlamaRuntimeIntegrationTests`) already run against real weights, so a determinism case belongs beside
   them. A test that only asserts non-empty output does not prove determinism.
5. **Measure the cost**: report latency before/after for the same inputs. Determinism must not be bought
   with a large regression on the transform path.
6. **Do not** change the speech-model path, the language gate, the prompt text, or the target-language
   routing. `fm-20260923-28` owns the Polish-output backend and may land in the same files afterwards; keep
   this diff confined to the sampling mechanics.

## Verification

- Byte-identical outputs across >=5 identical requests, and across >=2 process launches, with the commands
  and the outputs quoted.
- The new test fails against the pre-fix runtime (revert only the sampling change to show it) and passes
  afterwards; state the command.
- Full suite green on the branch tip; the app bundle still identity-signed and single-binary.
- Latency numbers for the same inputs, before and after.

## Worktree isolation assertion

Branch `fm/fm-20260923-27` already exists and points at the delivery tip `5e51124`. Create the worktree at
dispatch:

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-27 fm/fm-20260923-27
```

then `git -c protocol.file.allow=always submodule update --init --recursive` inside it. Work in that
worktree ONLY; never edit the primary checkout's sources, the captain's preferences, or another crew's
worktree. Do not leave an app instance running while building.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; the mechanism named at file:line; determinism proven by execution and pinned by a test
that fails before the change; latency reported; an honest note of anything you could not reproduce.
