# Task fm-20260923-04 — OpenSuperWhisper — scout

## Captain's intent

Captain (verbatim): "The app should also understand if I'm using Polish or English, because I'm
sometimes, right now, speaking English and I don't need always a translate feature. I also want to
sometimes use Polish without translate, so they need to be a toggle for translation enabled."

Reading of the ask: dictation must not be blindly translated. When the captain speaks English the
app must deliver the English transcript as-is; when the captain speaks Polish with translation on,
it translates; Polish with translation off stays Polish. A translation on/off control must exist.

Facts already established by the first mate (do not re-derive, verify only if cheap):

- A translation toggle already exists and already gates the transform:
  `AppPreferences.translateEnabled` (default false), Settings UI "Translation & Tone" section
  (`Settings.swift` ~1045-1106), and `TranslationService.transformIfEnabled`
  (`TranslationService.swift:67`) returns the raw text when disabled. So the toggle half of the ask
  is largely satisfied; the missing half is language awareness.
- `WhisperEngine.swift:351` sets `params.detectLanguage = false`, and the transcription path used by
  dictation returns only a `String`:
  `IndicatorWindow.decodeRecording()` calls
  `transcriptionService.transcribeAudio(url:settings:operationID:pcmSamples:)` and then
  `TranslationService.shared.transformIfEnabled(text)` (`IndicatorWindow.swift:245-283`).
  Detected source language is therefore not available at the decision point today.
- The repo has language machinery to build on: `Utils/LanguageUtil.swift` (`"auto"` =
  "Auto-detect", per-engine supported language lists, `languageNames`), `Whis/WhisperFullParams.swift`
  (`language`, `detectLanguage`), `Whis/Whis.swift` (`langId(lang:)`, auto-detect helpers around
  lines 228-260).

## Firstmate spec

Read-only investigation. Deliverable is a self-contained report; **no branch, no repo changes**.

Answer these, each with `file:line` evidence and a verdict:

1. **Where the language signal can come from per STT engine.** The fork has several engines under
   `OpenSuperWhisper/Engines/`. For the engine(s) actually used by dictation (read the engine
   preference and defaults in `Settings`/`AppPreferences`; state which engine is the default and what
   the current language preference is):
   - Can the engine report the detected language of one utterance, and what is the exact call
     (e.g. whisper.cpp `detect_language` param plus `whisper_full_lang_id`, or an explicit
     `autoDetectLanguage` run over the utterance audio)? Cost in ms on this machine, measured if you
     can (real audio exists in the repo: `jfk.wav`, and tests reference other fixtures).
   - Is the language property already populated anywhere (e.g. `WhisperEngine` transcription result)
     and simply dropped on the way to the dictation hook? Show the drop point.
   - What does the *user-facing* language setting mean for this feature: with `language = auto` the
     engine decides; with a fixed `pl` or `en` the answer is already known. State how a fixed setting
     should interact with the detection gate.
2. **Fallback detection when no engine signal exists.** Evaluate, with measurements on a small
   sample set (>= 8 sentences, mixed Polish and English, including short ones of 2-4 words):
   - A text heuristic on the transcript (Polish diacritics plus common Polish function words against
     English ones) — propose the exact rule set and report accuracy plus the failure modes
     (diacritic-free Polish, English words inside Polish sentences, single-word utterances).
   - A single detection call to the local OpenAI-compatible transform endpoint used by the app
     (`http://127.0.0.1:1919/v1/chat/completions`; port is currently free, start the backend only if
     one is already available — see `firstmate-home/data/fm-20260923-03` for the runtime work in
     flight; do not create it) — report expected latency and whether it is worth it versus the
     heuristic.
   - Rank the options by reliability/cost and recommend one, with the fallback chain stated.
3. **Gate design.** Specify the decision table at the transform hook for these inputs and outputs:
   `translateEnabled` (existing), detected/known source language (pl / en / unknown), transcript
   length, and the chosen tone mode. Cover explicitly:
   - English input while translation is on: raw passthrough (recommended default, zero model call) or
     tone-only rewrite (costs a model call, changes English text the captain may not want touched).
     Give the tradeoff and a recommendation; the captain decides.
   - Polish with translation off: unchanged today (raw Polish).
   - Unknown/very short transcript: what to do, and why (avoid translating a two-word English
     phrase into nonsense Polish-English).
   - Whether the new behavior needs a preference at all, or whether it should be automatic whenever
     `translateEnabled` is on. Propose the preference name/default if it does.
4. **Insertion points and blast radius.** Exact `file:line` list of what a ship task would touch:
   the engine's transcription API (does it need to return a language alongside the text, or can the
   language be obtained without changing that signature?), the dictation hook, `AppPreferences`,
   `Settings` UI, and tests. Call out anything that would change public/internal API shape, and note
   the recording store's existing behavior (history keeps the raw transcript).
5. **Tests.** What a ship task must prove: which decisions are unit-testable (gate table, detector,
   passthrough) and which need the real engine. Point at the existing test files to extend
   (`OpenSuperWhisperTests/TranslationServiceTests.swift`, `KeyboardSimulatorTests.swift`).

## Delegation guard

You are a crew member. Do not spawn subagents. If you need more depth, say so in your final report.

## Definition of done (scout)

- `data/fm-20260923-04/report.md` — self-contained: question, method, findings with evidence
  (measured numbers where they exist, `file:line` everywhere), the gate design, ranked options, one
  recommendation, and an explicit list of what you did NOT verify.
- No branch, no commit, no repo modification. Reading the repo and running throwaway probes in `/tmp`
  is expected; do not touch `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-03`
  (another crew is working there).

Report through your final message: outcome, files read, probes run, honest failure. Never claim
verification you did not perform.
