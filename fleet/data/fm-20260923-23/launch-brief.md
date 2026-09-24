# Task fm-20260923-23 — OpenSuperWhisper — ship — mode=local-only

## Why

`fm-20260923-20` investigated why `WhisperLongFormLanguageIntegrationTests` passes with `ggml-tiny.bin` and
fails with `ggml-large-v3-turbo.bin`. Its verdict was that the reported "lost its phrase across an adjacent
30-second boundary" is an **artefact of the test**, not word loss:

- With `ggml-large-v3-turbo` the same run passed `long_en`'s content assertions (unique-word recall ≥ 0.60,
  middle checkpoint "quiet", final checkpoint "silver"); only the seam-adjacency probes failed. Those probes
  assert **where whisper placed its own segment seams** — for a two-word probe pair the seam must fall on an
  exact word gap — which is a property of the decoder, not of the app.
- The Russian probe pair is additionally mis-calibrated: "последнее" does not exist in `long_ru.txt` (only
  "Последняя"), so a faithful transcript can never satisfy it.
- The app never splits audio: one `whisper_full` call per recording (`WhisperEngine.swift:270`), VAD-compacted
  speech only (`WhisperEngine.swift:205, 213-215, 431-452`), segment texts joined verbatim with no overlap or
  dedup (`290-313, 368-370`). All 30-second behaviour is whisper.cpp's long-form loop (seek from the last
  timestamp token; previous window's decoded tokens re-fed as prompt).

**Residual to close**: in the same `ggml-large-v3-turbo` run, `long_ru` also failed a **content** assertion
(unique-word recall 0.4047) and lost a checkpoint anchor (`XCTUnwrap` nil). The scout could not extract the
transcript (xcresult attachments are compressed) or re-run the engine (read-only, no execution tools), so the
cause is unknown: whisper.cpp seam conditioning (`no_context=false`), a decoder repetition loop, or the
known cross-worktree preference-domain race.

## Firstmate spec

1. **Reproduce the residual with execution**: run the long-form tests against `ggml-large-v3-turbo.bin`
   (fixture at `.build/test-models/ggml-tiny.bin`, a **hard link** — a symlink fails the size probe) and
   capture the actual Russian and English transcripts, not just pass/fail. Also cross-check the same audio
   with `/opt/homebrew/bin/whisper-cli` and the same flags, so app-side and library-side behaviour are
   distinguishable.
2. **Decide the cause with evidence** among: (a) whisper.cpp long-form conditioning, (b) a decoder repetition
   loop, (c) shared-preferences interference in the test process. State which, with the transcript lines and
   the file:line of the mechanism. If it is (b), show the repeated span.
3. **Fix the test so it can actually pass with a multilingual model**, without weakening what it is there to
   prove:
   - repair the mis-calibrated RU probes so they reference text that exists in the fixture, and make the
     seam-adjacency probes assert what matters (that the phrase survives somewhere in the transcript, and
     that the seam does not *cut a word*), rather than binding to the decoder's exact seam placement;
   - keep a real guarantee: no word may be dropped or duplicated across the window seam in the content
     sense. A test that a faithful transcript cannot satisfy is itself the defect.
4. **If the app is at fault** — for example the VAD compaction's 0.1 s overlap/gap concatenation or the
   `no_context=false` / `n_max_text_ctx = n_text_ctx/2` choice causes loss on long input — fix the app, not
   the test, and say so with the mechanism.
5. State the blast radius explicitly for the captain's use: dictations of seconds are in the single-window
   regime; confirm that with a measurement, not an assumption.

## Verification

- The long-form suite passes with **both** a tiny and a multilingual fixture, or the honest reason it cannot
  (with the evidence that the remaining difference is the model's own transcription, not a lost phrase).
- `Scripts/dev-run.sh test` green for the target, ending with the identity requirement on disk
  (`codesign -d -r-`); a bare cdhash is a failure.
- Report the exact commands, the transcripts, and the counts.

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-23` ONLY, branch
`fm/fm-20260923-23`, from the current delivery tip. Initialize submodules with
`git -c protocol.file.allow=always submodule update --init --recursive`. Never edit the primary checkout's
sources, the captain's preferences, or any other worktree. Do not leave an app instance or a model server
running. If you create the multilingual fixture for a run, remove it again afterwards, since the captain's
preference file and the shared `.build` directory are used by other crews.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

Committed branch; the cause identified with transcripts and file:line; the tests repaired or the app fixed
(whichever is truthful); both-fixture evidence; honest notes on anything unresolved.
