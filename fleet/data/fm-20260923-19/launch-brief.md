# Task fm-20260923-19 — OpenSuperWhisper — measure (read-only, no branch)

## Why

The captain demanded Polish output ("no feature to provide transcription into Polish"), and
`fm-20260923-13` measured the shipped 1.5B model failing at it while being good at Polish → English:

- "Close the window, it's cold outside." → "Zamknij okno, jest zimno **za nami**." (behind us)
- "Tomorrow morning I'm taking the train to Kraków at seven." → "Rano zjawi się za **trainem** do Krakowa
  w **sobotę**…" (English leak, invented "Saturday", dropped "tomorrow")

He has a much stronger model already on disk, so this is a measurement, not a purchase:
`~/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` (19 GB, MoE with ~3B active) on a 32 GB M4.

## Firstmate spec

Read-only. Deliverable `data/fm-20260923-19/report.md`. No branch, no repo changes; scratch in `/tmp` and
the firstmate home. Do not modify the captain's preferences or leave servers running.

1. **Same sentences, both directions, three backends.** Use the sentence set from fm-20260923-13 (the eight
   English → Polish examples and the eight Polish → English ones, including the long paragraph), and run
   them through:
   - `qwen2.5-1.5b-instruct-q4_k_m.gguf` (the shipped model, baseline),
   - `Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` (local),
   - if trivially available, one intermediate option (e.g. a 7B q4 inside `~/.cache` or an existing GGUF) —
     otherwise say it was not available and skip it.
   Use the same prompt shape the app composes (system prompt naming source and target language, temperature
   0.2), and the shipping inference path (`llama-cli`/in-process llama.cpp with Metal is fine; state
   exactly what you ran).
2. **Report per sentence**: input, output for each backend, verdict (correct / wrong word / invented
   content / broken grammar), and latency. Latency must distinguish cold start (model load) from warm
   per-sentence time, and report peak resident memory per backend.
3. **Answer the captain's actual question**: with the 30B-A3B model, is English → Polish good enough to
   ship as a selectable "Polish output" mode? Give numbers (seconds per sentence, RAM) so the tradeoff is
   his to decide, plus your recommendation on the smallest model that is still correct.
4. **State the integration consequence honestly**: what it would cost the app to offer this model (download
   size, disk, RAM ceiling on a 32 GB machine, whether it must be unloaded between dictations), and whether
   the shipped 1.5B should stay the default for Polish → English.
5. Also report whether the 30B changes the Polish → English direction for better or worse, since that is
   the captain's daily path and must not regress.

## Delegation guard

You are a crew member. Do not spawn subagents. Stop any server you start; leave no process bound to a port.

## Definition of done

`data/fm-20260923-19/report.md` with the tables (input, per-backend output, verdict, latency), the memory
numbers, an explicit recommendation, and a list of what you could not measure.
