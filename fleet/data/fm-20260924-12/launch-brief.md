# Task fm-20260924-12 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent (verbatim)

> "Also add a feature to ignore pauses. Essentially, it creates a sentence without a sense due to my long
> pauses. The pauses need to be ignored."

Then, narrowing it: **"The issue lies solely with polish."**

## Established before this brief — read before designing anything

**His own raw Polish transcripts, read out of `recordings.sqlite` (the stored text is the raw engine output):**

- `2026-09-25 05:47:35` — "Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork.
  Ben super whisper. Dałem drugi model. **Jestem.** **Znowu po polsku.**"
- `2026-09-25 05:33:32` — "Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą.
  Bo tu chodzi o to że żeś pieprzył po całości."

Both show the shape of the complaint: **short isolated fragments** (`"Jestem."`, `"Znowu po polsku."`) where a pause
was, and garbled word forms (`"Ben super whisper"`, `"ziameczku"`, `"że żeś pieprzył"`).

**The mechanism in the code (`Engines/WhisperEngine.swift`):**

- `params.language = nil` and `showTimestamps` is off by default, so decoding takes the **silence-removed** path:
  `speechOnlySamples(from:segments:)` (`:450-470`) concatenates the VAD speech segments and replaces the silence
  between them with **0.1 s of zeros** — the same 0.1 s upstream whisper.cpp uses when stitching VAD segments.
- A pause of *any* length therefore reaches the decoder as a 0.1 s breath. Whisper then decides sentence
  boundaries from prosody alone, and **Polish punctuation is markedly weaker than English** in this model — the
  most likely reason the captain sees this in Polish only. Where the decoder does emit a boundary, it emits a
  *fragment* (`"Jestem."`); where it does not, two thoughts arrive as one sentence.
- `assembleSegmentTexts` (`:368`) joins decoder segments with `""` (or `"\n"` in timestamp mode): it adds no
  punctuation of its own and never consults the VAD gaps it still has in hand.

**A separate finding, flagged because it is a strong hallucination trigger and it is in his preferences:**

```
initialPrompt = "You are a transcriber. Your role is just to clean up the text and make it look pretty and
attractive. Do not change the sense of the sentences."
```

That is an *instruction* sitting in whisper's `initialPrompt`, which is decoder context, not a system prompt:
whisper continues from it as if it were preceding text, and it is carried across windows (`carryInitialPrompt`).
"Make it look pretty and attractive" invites invention, and instruction-shaped context biases Polish decoding in
particular. Measure it (same recordings, prompt cleared vs kept) and report the delta; recommend clearing it, but
do not silently change the captain's preference.

## Firstmate spec

1. **Reproduce first.** His recordings are on disk
   (`~/Library/Application Support/ru.starmel.OpenSuperWhisper/recordings/<fileName>`); take two Polish ones and one
   English control and decode them through the app's own engine path with his settings. Record what the current
   build produces and **count the sentences** — the complaint is about sentence shape, so measure that: fragments
   where a pause was, and any place two thoughts were joined.
2. **Then change the assembly so a long pause survives as a boundary.** The VAD segments already carry the timing;
   the code throws it away. Cheapest first — measure, do not assume:
   - keep a longer patch of the real silence at a gap (up to ~0.5–0.8 s) so the decoder itself closes the sentence,
     instead of a fixed 0.1 s;
   - when a gap exceeds a measured threshold, insert a sentence terminator into the assembled text at that point
     (language-aware `.`), so a fragment cannot be joined to the next thought.
   State the threshold you picked and the evidence for it. Both are audio/text plumbing — **no model call, no word
   changed, no punctuation invented inside a sentence**.
3. **Polish is the target; English must not regress.** Report both, before and after.
4. **Name the feature honestly in the UI.** The captain asked to "ignore pauses"; the measurements will almost
   certainly show that *dissolving* a pause is what produces the nonsense, so the switch and its copy must say what
   it actually does ("long pauses end the sentence"), not the reverse. One line in Settings next to the language and
   clean-up controls; no new panel.
5. **Do not touch** the tone prompt or the model routing (`fm-20260924-11` owns those), the delivery path
   (`Utils/KeyboardSimulator.swift`, the injection part of `Indicator/IndicatorWindow.swift`), or
   `params.noTimestamps = false`.
6. **Tests:** the assembly is a pure function over segments and gaps — pin the new behaviour there (a gap over the
   threshold produces a boundary; a short gap does not; no word altered; timestamp mode unchanged), plus the
   measured before/after tables from step 1.

## Verification

- Before/after tables for two Polish recordings and one English control: sentence count, fragments, joined
  thoughts, with the commands and the raw outputs quoted.
- The `initialPrompt` A/B on the same recordings, with numbers and the recommendation.
- The assembly tests, with the command; the full suite green from a clean state, headless, output at
  `/tmp/fm2412-suite.log`; bundle identity-signed afterwards (`certificate leaf`, never a bare `cdhash`).
- `fleet/data/fm-20260924-12/report.md` and a UTC-stamped `status.log` line.

## Worktree isolation assertion

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pauses \
  -b fm/pause-boundary "$(git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo rev-parse --short HEAD)"
git -C <worktree> -c protocol.file.allow=always submodule update --init --recursive
```

Work in that worktree ONLY. **Headless only:** never launch the app, never `osascript`, never `screencapture`, never
`Scripts/dev-run.sh` without a mode argument.

## Time gate

The provider bills peak rates during **01:00–04:00 and 06:00–10:00 UTC, Monday to Friday**. Cheap steps run any
time; gate every expensive step (decoding his recordings, `llama-server`, the full suite) behind `date -u` and, if
the hour is 06–09 UTC, one shell sleep until 10:00 UTC. **At the peak boundary the captain wants work stopped, not
carried over:** if a window closes mid-task, commit what is coherent, report exactly what is left, and stop.

## Delegation guard

You are a crew member. Do not spawn subagents. No push, no merge, no branch deletion.

## Definition of done

Committed branch; the mechanism named with the recordings as evidence; the chosen threshold and its measurements;
before/after tables for Polish and the English control; the `initialPrompt` A/B and its recommendation; the assembly
pinned by tests; the UI line naming the behaviour honestly; the suite green; the report and `status.log`; an honest
note of anything unverified.
