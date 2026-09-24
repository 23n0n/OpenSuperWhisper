# Task fm-20260923-24 — OpenSuperWhisper — measure (read-only, no branch)

## Why

`fm-20260923-19` measured English → Polish on two backends:

| backend | clean | invented content | broken grammar | warm latency (mean) | wired memory |
|---|---|---|---|---|---|
| `qwen2.5-1.5b-instruct-q4_k_m` (shipped) | 3/15 | 3 | 4 | 0.43 s | 1.2 GB |
| `Qwen3-30B-A3B-Instruct-2507-q4_k_m` (local) | 11/15 | 0 | 0 | 1.1–1.2 s | **~17.2 GB wired**, 66 s cold load |

The 30B is good but pegs ~18 GB wired on a 32 GB machine that also runs Whisper large-v3-turbo — swap was
already 2.86 GB while it was loaded — and it cannot honour the app's 10-minute idle-unload contract (unload =
66 s wait for the next dictation). Before the captain is asked to accept that, measure the obvious middle:
a dense 4B–8B instruction model, which is ~2.5–5 GB and would fit the existing lifecycle.

## Firstmate spec

Read-only. Deliverable `data/fm-20260923-24/report.md`. No branch, no repo changes; do not touch the
captain's preferences; stop every server you start.

1. **Use an existing model if one is already on disk** (check `~/.lmstudio/models`, `~/.cache/huggingface`,
   `~/.cache/lm-studio`, `~/models`). Only download what is missing, into `/tmp/fm24-models/`, and report the
   exact URL, SHA-256 and size of anything you download so it can be added to a pinned catalogue — or deleted.
   Candidates in preference order: `Qwen3-4B-Instruct-2507` q4_k_m, `Qwen3-8B` q4_k_m (or the nearest
   equivalent already present, e.g. `Qwen2.5-7B-Instruct` q4_k_m). Name what you actually ran.
2. **Same sentence set, same prompt shape** as the previous measurement (system prompt naming source and
   target language, temperature 0.2, `enable_thinking=false` / `/no_think` for Qwen3): the 15 English →
   Polish cases including the long paragraph, and the 8 Polish → English cases. Verdict per sentence
   (correct / wrong word / invented content / broken grammar).
3. **Report per backend**: clean/total, invented-content count, broken-grammar count, warm per-sentence
   latency (mean, range), cold load time, and **wired memory** measured the way the previous measurement did
   (wired-memory delta on load, not process RSS — RSS lies because llama.cpp puts weights in wired Metal
   buffers).
4. **Determinism**: run each backend's Polish → English set three times and state whether the outputs are
   byte-identical. The shipped 1.5B was observed unstable in the English → Polish direction (8 of 10 outputs
   differed between identical runs) — establish whether the captain's daily direction is affected, since a
   non-deterministic transform on the daily path is its own defect.
5. **Answer plainly**: which is the smallest model that is reliably correct for Polish output, what it costs
   in memory and latency, and whether it can honour a 10-minute idle unload. Give the numbers that let the
   captain choose between quality and RAM.

## Delegation guard

You are a crew member. Do not spawn subagents. Leave no process bound to a port; delete any model you
downloaded into `/tmp` if it is not needed for the report's reproducibility, and say what you kept and where.

## Definition of done

`data/fm-20260923-24/report.md` with the tables, the memory numbers measured the same way as fm-19, the
determinism result, an explicit recommendation, and a list of what you could not measure.
