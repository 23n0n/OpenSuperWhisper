# Task fm-20260923-28 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

*"Polish output uses Qwen3-8B"* — the captain's decision after `fm-20260923-24` measured the candidates.
Pinned, do not re-derive:

- url: `https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf`
- sha256: `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785`
- size: 5 027 783 488 bytes; local copy already on disk at `~/models/Qwen3-8B-Q4_K_M.gguf`.

Measured basis (fm-20260923-24, do not re-litigate):

| backend | EN->PL clean | invented | wired RAM | cold load |
|---|---|---|---|---|
| Qwen2.5-1.5B (shipped) | 3/15 | 3 | 1.2 GB | — |
| Qwen3-4B | 9/15 (5 broken) | — | — | — |
| Qwen3-8B-Q4_K_M | **11/15** | 0 | 5.33 GB | 3.2 s |
| Qwen3-30B-A3B | 12/15 | 0 | 18.17 GB | 43.7 s |

The 30B is better and faster per call but cannot honour the 10-minute idle unload (43.7 s cold load, 18 GB
wired on a 32 GB machine that is already swapping). It stays a manual option, not the shipped default.

## Firstmate spec

1. **Route by direction**: `transformTargetLanguage = Polish` uses the 8B when it is installed; PL->EN
   keeps the 1.5B (8/8 correct, ~0.29 s, 1.1 GB) and must not regress.
2. **Never silently substitute.** If Polish output is selected and the 8B is not installed, say so in the
   UI and offer the download (with the pinned digest); do not fall back to the 1.5B for Polish, whose
   EN->PL output the same measurement found unreliable.
3. **Reuse the existing model plumbing**: the app-managed download and sha256 verification in
   `TransformModelManager` and its Settings card. No new download mechanism, no second source of truth for
   the digest.
4. **State the cost in the UI**: per-backend RAM (and disk, for the download) next to the choice, so the
   memory footprint is visible before it is paid.
5. **Keep the idle-unload contract** the fleet already documents (10 minutes), and hide the 8B's 3.2 s cold
   load behind a warm-up on record start — measure and report the resulting first-utterance latency, and
   the behaviour when the warm-up has not finished.
6. **Sequence**: land after `fm-20260923-17` and `fm-20260923-25` — same Settings card and model files.
   Rebase on the delivery tip before finishing.
7. **Do not** touch the sampling mechanics: `fm-20260923-27` owns determinism and may touch the runtime in
   the same files.

## Verification

- Prove routing with execution, both directions, with the model names in the output: target Polish uses the
  8B; PL->EN uses the 1.5B; spoken == target performs zero model calls.
- Prove the missing-model path: with the 8B absent and Polish selected, the app says so and does not call
  the 1.5B for Polish. Show the message and the absence of a transform call.
- Prove the digest check: the download refuses a wrong digest; a re-verify of the on-disk file passes.
- Report wired RAM and latency for the 8B path, measured, not asserted.
- Full suite green; the app bundle identity-signed and single-binary.

## Worktree isolation assertion

Create the worktree at dispatch:

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-28 -b fm/fm-20260923-28 <delivery tip from fm-17/fm-25>
```

then `git -c protocol.file.allow=always submodule update --init --recursive` inside it. Work in that
worktree ONLY; never edit the primary checkout's sources, the captain's preferences, or another crew's
worktree. The worktree build carries bundle id `ru.starmel.OpenSuperWhisper.dev`; one app instance at a
time.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; routing and the missing-model path proven by execution with quoted output; RAM and
latency measured; the 10-minute unload preserved with the warm-up reported; an honest note of anything
unverified.
