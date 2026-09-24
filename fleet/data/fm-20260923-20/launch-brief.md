# Task fm-20260923-20 — OpenSuperWhisper — investigate (read-only reports, no branch)

## Why

`fm-20260923-12` measured, while wiring the test path, that
`WhisperLongFormLanguageIntegrationTests` **passes with `ggml-tiny.bin` and fails with
`ggml-large-v3-turbo.bin`**:

> "long_en lost its phrase across an adjacent 30-second boundary"

The captain was switched to `ggml-large-v3-turbo.bin` today (his Polish dictation needed a multilingual
model), so if that failure is a real defect rather than a fixture artefact, long dictations lose words.

## Firstmate spec

Read-only. Deliverable `data/fm-20260923-20/report.md`. No branch, no commit, no repo modifications
outside `/tmp` and the firstmate home.

1. **Reproduce and characterise.** Take a long fixture audio (the tests' own fixture, and a longer one
   synthesised or taken from the captain's recordings concatenated in `/tmp`) that is longer than two
   30-second windows, with known sentences placed so that one straddles a window boundary. Transcribe
   with `ggml-large-v3-turbo.bin` and with `ggml-tiny.bin` through the app's own engine path
   (`WhisperEngine`), and diff the transcripts against the known text.
2. **Answer precisely**: is a phrase lost at the boundary, garbled, or duplicated? At which timestamps?
   Does it happen with `ggml-tiny.bin` too under the same conditions? Is the boundary at 30 s because of
   `whisper_full`'s single-window limit, the app's chunking, or the fixture's own construction?
3. **Read the long-form path in the app** (`WhisperEngine.swift`, the `Whisper`/`WhisperFullParams`
   wrappers) for how chunks are stitched: is `no_context`/`initial_prompt`/`prompt_tokens` carried across
   chunks, is the overlap applied, and does the code treat a 30-second window as a hard boundary? Cite
   file:line for what it actually does.
4. **Verdict with evidence**: real defect (with the losing example and the mechanism) or fixture artefact
   (with the reason the fixture only worked for tiny). If it is real, say what the fix should be and how
   it would be verified — but do not implement it in this task.
5. **State the blast radius for the captain**: his dictations are mostly seconds long — say explicitly
   whether anything shorter than the boundary is affected.

## Worktree isolation assertion

Read-only: do not modify anything under `/Volumes/home/zenon/Projects/` or its worktrees. Scratch space:
`/tmp` and `data/fm-20260923-20/`.

## Delegation guard

You are a crew member. Do not spawn subagents.

## Definition of done

`data/fm-20260923-20/report.md` containing the reproduction, the transcripts side by side, the mechanism
with file:line, the verdict, the blast radius, and an explicit list of what you could not determine.
