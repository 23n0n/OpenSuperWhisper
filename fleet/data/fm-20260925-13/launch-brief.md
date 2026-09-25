# Task fm-20260925-13 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent (verbatim)

Asked what "write better prompt than …" meant, he chose **both**: the transcription-prompt candidates ride the running
pause crew (already instructed), and this task is the **tone-prompt round** — *"then a tone-prompt round"*.

## What already exists (do not re-derive)

The tone rewrite prompt landed today in `877d19e` (`OpenSuperWhisper/TransformService.swift`, `systemPrompt()` /
`userPrompt()`), with a deterministic guard (`TransformGuard.swift`) and a framed user turn
(`<<<TRANSCRIPT … TRANSCRIPT>>>`). It was measured **equal-or-better** than the prompt it replaced, on the exact
compiled bytes, with the captain's own Polish dictations and an English control:

| | unchanged answers | invented a word | lost a word |
|---|---|---|---|
| Polish, old prompt | 13 / 28 | **7** | 8 |
| Polish, landed prompt | 15 / 28 | **2** | 4 |
| English, old prompt | 3 / 11 | 4 | 4 |
| English, landed prompt | 4 / 11 | **1** | 2 |

So the residual failures are **invented words and dropped words**, concentrated in Polish — which is exactly the
captain's original complaint (*"the tone transcription is bound with Polish"*). The harness, the sampling
(temp 0.2 / top-k 40 / top-p 0.95 / min-p 0.05, `enable_thinking=false`), the case list, the real guard and
`LanguageDetector`, and the trick that proves prompt fidelity against the compiled service are all in
`fleet/data/fm-20260924-11/` (`evidence/tone-ab.py`, `evidence/resume-prompt-fidelity.txt`, `report.md`). **Reuse them.**

## Hypothesis (this is the task — one of these, or your own, must win on measurement)

1. **Instruction language.** The prompt is written in English with `{language}` interpolated. Dictating Polish and
   instructing in Polish may hold Polish content better than instructing in English about Polish. Test a Polish
   instruction block for `language == .polish` (English stays English), otherwise identical.
2. **One worked example.** A single short input→output pair in the same language and register, showing a rewrite that
   changes register and keeps every content word. Few-shot anchors small models better than rules alone; the risk to
   measure is that the model copies the example's *content* — count that as an invented word.
3. **An explicit self-check clause.** One line ordering a verification of the answer against the dictation (every noun,
   number and proper noun present, nothing added). Measure whether it reduces inventions or merely lengthens outputs.

You may add a fourth only if you can state it as falsifiable in one sentence.

## Method

- Same harness, same cases, same sampling, same guard classification as the landed measurement, so the numbers are
  comparable row for row. The landed prompt is the control in every run.
- **Polish first.** The captain's pain is Polish; 28 Polish answers minimum (his 7 real dictations × 3 registers +
  the adversarial set). English must be re-measured only for a candidate that wins on Polish, to prove no regression.
- Report per candidate: unchanged / invented / lost, the number of guard rejections, latency median, and the verbatim
  outputs for every case where a candidate differs from the control. A candidate that fixes punctuation but changes
  words is **not** a win — that is precisely the failure this round exists to remove.
- Determinism: run the winner twice, as the earlier round did, and report how many answers differ between identical
  runs, so run noise is separated from the effect.
- If nothing beats the control beyond run noise, **say so and land nothing.** A negative result delivered cleanly is
  worth more than a rewrite with no evidence.

## Constraints

- Change `systemPrompt()` / `userPrompt()` only if a candidate wins; if you change it, the guard's tests must stay
  green (they assert invariants, not sentences, since today's fix pass) and the Readme's tone section must match.
- Do not touch `TransformGuard.swift`'s detection classes, the routing (`model(for:)`), the warm-up, `WhisperEngine`,
  or the pause task's files.
- **Machine contention:** the pause crew is running. Before any build, model load or measurement, confirm
  `/tmp/fm2412-suite.log` ends in a final `** TEST SUCCEEDED **`/`** TEST FAILED **` (or that the pause task has landed)
  and that no `xcodebuild`/`llama-server` is alive. Design, write the harness and prepare tests meanwhile — never
  busy-wait; one `sleep 60` loop.
- Long runs detached: macOS has no `setsid`; use
  `python3 -c "subprocess.Popen([...], start_new_session=True, stdout=open(log,'w'), stderr=subprocess.STDOUT)"`.
  A harness-backgrounded job is torn down with its session — that has already cost this fleet one build.
- Headless only: never launch the app, never `osascript`, never `screencapture`, never a bare `xcodebuild test`,
  never `pkill`/`killall` anything you did not start. Leave no `llama-server` resident.
- Provider is off-peak (guard-checked) — no billing gate.

## Definition of done

Committed branch (only if something won), the per-candidate tables with verbatim differing outputs, the determinism
figures, the `** TEST SUCCEEDED **` full suite with real counts on the final head and an identity-signed bundle
(`certificate leaf`), `fleet/data/fm-20260925-13/report.md`, a UTC-stamped `status.log` line, and an honest list of
what remains unverified — including a clean negative result if that is what the numbers say.
