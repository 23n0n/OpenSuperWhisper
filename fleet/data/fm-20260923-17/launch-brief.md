# Task fm-20260923-17 — OpenSuperWhisper — ship — mode=local-only

Owns three things the captain demanded in sequence: the English-only-model guard, the dictation clean-up
pass, and a reference/glossary. They live in the same prompt composition and the same Settings card, so
one crew owns all three rather than racing three branches through one function.

## Captain's intent

1. Verbatim: "A translate feature is basically shit… it does actually random sentence in English… Just
   random sentences in English." Root cause proven: his selected speech model was `ggml-tiny.en.bin`
   (English-only) with language `auto`, so Whisper hallucinated English and the transform correctly found
   nothing to translate. Nothing warned him; nothing showed him the model or the language in play.
2. Verbatim: "There is even nothing to provide it reference."
3. Verbatim: "I was thinking about adding at least one additional feature to basically scrub all the
   'hmmmm', 'aaaaa' and other artifacts and make the language a little bit polish. So basically correct
   the grammar… adding the 'a' when it's needed and maybe fixing the word's order to form proper
   sentences in English."

## Firstmate spec

1. **Refuse the impossible combination.** An English-only speech model (filename ending `.en.bin`, or
   `whisper_is_multilingual() == 0`) with `whisperLanguage != "en"` must never silently produce a
   transcript. Surface it inline, naming the model and the language setting, with the fix available in
   place (a multilingual model — `ggml-large-v3-turbo.bin` is already on this machine). Do not block
   plain English dictation, and never silently change the user's selected model.
2. **Show the pipeline per dictation.** `WhisperEngine.reportedLanguage` and the transform policy already
   exist — expose them: after each dictation show the detected language and, when the transform ran, the
   raw transcript beside the transformed text. History keeps the raw text; make the pair visible.
3. **Clean-up pass** (the captain's new feature). Two layers, in this order:
   - **Deterministic scrub** — remove disfluencies and artifacts the recogniser emits: repeated filler
     tokens ("hmm", "uh", "yyy", "aaa", "eee"), stutters and immediate word repetitions, false starts,
     stray non-lexical noise. Conservative: never delete a word that carries meaning; Polish and English
     fillers both. This layer must be unit-testable with fixed inputs, no model needed.
   - **Grammar repair via the transform** — fold into the *existing single* transform call (never a second
     model call): restore punctuation and capitalisation, add missing articles ("a"/"the"), fix word order
     and agreement to form proper sentences in the output language, without adding or dropping meaning.
   Visible as its own control in Settings → Transcription (e.g. "Clean up dictation: remove filler words
   and fix grammar"), on by default is acceptable if the measurement below justifies it. It must apply to
   Polish → Polish (translation off) as well as to the translated direction.
4. **Reference/glossary.** A user-editable field (names, jargon, domain terms) fed into the transform
   prompt, persisted as a preference, visible in the same card. Optional, empty by default, and it must
   not disturb the prompt when empty.
5. Confine the diff to the recognition path, the transform path and the Transcription tab of
   `Settings.swift`. `fm-20260923-15` is fixing that file's layout — rebase before touching the card.

## Measurement required before wiring the grammar layer

Take 8–10 real dictations (the captain's own recordings are on disk under
`~/Library/Application Support/ru.starmel.OpenSuperWhisper/recordings/` with the matching rows in
`recordings.sqlite`) and show, for each: raw transcript → cleaned transcript → final output, in both the
Polish → English and English → Polish directions, with latency. State honestly whether the 1.5B model
improves or degrades the text; if it fabricates or drops meaning, say so with the example and keep the
deterministic layer only until a stronger model is chosen.

## Verification

- `Scripts/dev-run.sh build` green; unit suite green (`NoMicrophoneGuardTests` is no longer a known flake:
  its one red case was deterministic, and fm-20260923-22 fixed it).
- Tests or harness proving: (a) English-only + auto is surfaced/refused rather than passed through;
  (b) the deterministic scrub on fixed inputs; (c) the glossary and clean-up instructions reach the
  composed prompt — assert the composed prompt, not the plumbing; (d) detected-language and
  raw-vs-transformed state is produced for a real fixture.
- The app bundle stays **identity-signed and single-binary** after build and after a test run
  (`codesign -d -r-` must show the identity requirement, not a cdhash).

## Worktree isolation assertion

Work in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-17` ONLY, branch
`fm/fm-20260923-17`, from the delivery tip at dispatch time. Initialize submodules with
`git -c protocol.file.allow=always submodule update --init --recursive`. Never edit the primary
checkout's sources, the captain's preferences, or any other worktree. Do not leave an app instance running.

## Delegation guard

You are a crew member. Do not spawn subagents. No push.

## Definition of done

<!-- original DoD marker -->

## Dispatch addendum — 2026-09-24 (read before starting)

The captain's standing instruction for this session is *as little new code as possible*. His three asks in
this brief are verbatim quotes and none may be dropped: the guard, the clean-up pass ("I was thinking
about adding at least one additional feature to basically scrub all the 'hmmmm', 'aaaaa' and other
artifacts and make the language a little bit polish…") and the reference field ("There is even nothing to
provide it reference."). Finish what is already written in your worktree; add nothing beyond this brief.

The tree moved. Repo: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`. Your worktree:
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-17`. Worktree
and submodule links were repaired by hand after the move — check `git status` first; a gitdir error means
stop and report, do not improvise a repair. Delete the stale native build caches before building
(`rm -rf libllama/build libwhisper/build`) — they embed old absolute paths and CMake refuses to reuse them.

Work in this order, committing each step:

1. **Commit the current uncommitted state as it stands** (so it cannot be lost), then **rebase onto
   `feat/local-translate-tone` @ `5e51124`**. One conflict is known and must be resolved in the delivery
   tip's favour: your worktree's `OpenSuperWhisper/Engines/WhisperEngine.swift` still carries
   `params.noTimestamps = !settings.showTimestamps`, while the tip has `params.noTimestamps = false` plus
   a 13-line rationale (repo `OpenSuperWhisper/Engines/WhisperEngine.swift:390-407`). **Keep the tip's
   line and rationale and re-apply only your `isModelMultilingual` addition** (worktree `:80-86`).
   Resolving that conflict in the worktree's favour silently re-introduces the long-form audio-loss bug
   this branch exists to fix. Quote the final state of that line in your report.
2. **Repair the three signature breaks you introduced and never fixed** — the test target as it stands
   cannot compile: `TransformPolicy.resolve` (`OpenSuperWhisperTests/TranslationServiceTests.swift:665-668`),
   `systemPrompt(for:)` (`TranslationServiceTests.swift:255,289,308,327-330,343,355`,
   `TransformBackendTests.swift:72,212`, `LlamaRuntimeIntegrationTests.swift:33,73,77`),
   `buildRequestBody` (`TranslationServiceTests.swift:237,273`) and `transformOverHTTP`
   (`TranslationServiceTests.swift:768,784,800,816,831`). Update the call sites; do not weaken an
   assertion, and say so in the report if one is now wrong.
3. **Close the three visibility gaps that make your other slices dead code** — no user can see or set what
   you built: (i) the clean-up control must exist in Settings → Transcription (`AppPreferences.cleanUpEnabled`
   is default true with no UI at all); (ii) the reference/glossary field must exist in the same card
   (`transformReference` is referenced only by its own definition and the prompt plumbing); (iii) something
   must display the detected language and the raw-vs-transformed pair (`DictationReportCenter.last` is
   published at `IndicatorWindow.swift:338-351` and read by nothing). Use the existing card chrome — no new
   panels, no new abstractions.
4. **Measure what the brief demands before leaving the grammar layer on by default**: a table of latency and
   model calls per dictation with clean-up on and off, for Polish → Polish (translation off) and
   Polish → English. The coupling to measure is `GateSettings.current` reading `prefs.cleanUpEnabled`
   (`TranslationService.swift:101`) with `resolve` turning it into a model call for same-language speech
   (`:205-206`). If the numbers do not justify default-on, default it off and say why.
5. **Two known quality risks in the deterministic scrub**: it runs an 8-pass regex with a 300-char window
   per transcript (`DictationScrubber.swift` ~`:380-400`), and it discards the audio when the scrub empties
   the transcript (`IndicatorWindow.swift:306-310`). Keep it conservative and report what a filler-only
   transcript produces.

Non-goals: the sampling mechanics (`OpenSuperWhisper/Llama/*`), the HTTP temperature literal, and the
Polish-output backend routing (`fm-20260923-28` owns that). The queue path shows a refused dictation as
"Failed to transcribe: …" with no remedy button (`TranscriptionQueue.swift:298-306`) — accepted for now,
do not redesign it.

Definition of done adds: commits on the rebased branch, per-file net line counts, `Scripts/dev-run.sh test`
green with the bundle identity-signed afterwards, the commit shas, the measurement table, the quoted
`noTimestamps` line, and an honest note of anything unverified. Run `Scripts/dev-run.sh test` exactly as
documented — never a bare `xcodebuild test`.

Committed branch; the three behaviours implemented and proven; the measurement table; an honest report of
quality, of anything unverified, and of anything you deliberately left out.

## Relaunch addendum 2 — 2026-09-24 (read before starting)

This task is a **deterministic relaunch**. The previous crew was killed mid-flight at 08:32 by a terminal
hangup (SIGHUP): a crew in a sibling task drove the GUI app with `open -n`, `osascript`/System Events
keystrokes and `screencapture`; one keystroke landed on the frontmost window — the agent's own terminal —
and the whole session, all four crews included, died with the tty. Nothing about that was your fault and
nothing you had written is lost: every byte of your work is on disk (state below).

**HEADLESS IS MANDATORY — this overrides anything above that assumes a visible app.**

Forbidden, no exceptions: `open`; `osascript` in any form; System Events / Accessibility automation;
synthetic keystrokes; `screencapture`; launching any OpenSuperWhisper build; `Scripts/dev-run.sh` with **no
mode argument** (it `exec`s the GUI app at the end); touching Terminal or iTerm at all.

Expected: `Scripts/dev-run.sh build|test`, `xcodebuild`, `git`, `python3`, text tools, unit and snapshot
tests. Redirect long output to a file (`> /tmp/<task>-step.log 2>&1`) and tail it. Never leave a process
attached to the foreground of a terminal.

If a check genuinely needs the app on screen, do **not** improvise it: state it in your report as
"needs the captain's screen" and stop that thread. The first mate runs screen-visible checks, not crews.

**State found on disk (verified before relaunch):** branch `fm/fm-20260923-17` @ `e019450`
"feat(dictation): guard English-only models, clean up dictation, add reference field" — parent is the
delivery tip `5e51124`, so the commit and the rebase are done. Dirty (7 files, +173/−33):
`OpenSuperWhisper/ContentView.swift`, `OpenSuperWhisper/Settings.swift`, and five test files
(`DictationInjectionTests`, `LlamaRuntimeIntegrationTests`, `TranscriptionLanguageGateTests`,
`TransformBackendTests`, `TranslationServiceTests`) — your signature repairs and the visibility work, mid-edit.

**Remaining scope, in this order:** (1) finish the signature repairs so the test target compiles;
(2) finish the two visibility gaps that are still open (clean-up control and reference field in Settings →
Transcription; detected-language / raw-vs-transformed display) — use the existing card chrome, no new
panels; (3) the latency/model-call table the brief demands; (4) `Scripts/dev-run.sh test` green, headless,
bundle identity-signed afterwards; (5) commit; (6) report shas, per-file net lines, the measurement table,
the quoted `noTimestamps` line, and anything unverified.
