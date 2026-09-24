# Task fm-20260923-05 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Captain (verbatim, 2026-09-23): "The app should also understand if I'm using Polish or English,
because I'm sometimes, right now, speaking English and I don't need always a translate feature. I
also want to sometimes use Polish without translate, so they need to be a toggle for translation
enabled."

Captain (verbatim, same day): "Ton adjustment should also have a toggle to be enabled and disabled
by a user."

So: two independent switches (translation, tone) and language awareness — English dictation must
never be sent to the Polish→English transform; Polish translates only when the translation switch is
on; tone is applied only when the tone switch is on. A translation switch already exists
(`translateEnabled`, Settings → Translation & Tone); the tone switch does not exist yet.

## Authoritative design

The design investigation is complete and is the spec: **read
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260923-04/report.md` in full before writing code.**
Its §3.2 decision table, §3.4 tone-only finding, §3.5 preferences, §3.6 prompt composition, §4
insertion points (with `file:line`, verified at `bd5ad0e`) and §5 test matrix are the contract.
Where this brief and the report disagree, the report wins — except the two first-mate calls listed
under "Deviations" below.

Summary of the required behaviour (report §3.2, §3.6):

| translate | tone | source language | action |
|---|---|---|---|
| off | off | any | none — raw transcript to the keypress path, no HTTP, no detection |
| off | on | `en` | toneOnly (same language in/out, no translation instruction) |
| off | on | `pl` | none — a tone-only prompt on Polish translates it anyway (measured 6/6), so passthrough |
| off | on | unknown | none |
| on | off | `pl` | translate, **no tone sentence at all** (the current neutral instruction must not be sent) |
| on | off | `en` | none — any model call mutates English (only 7/10 identity even when told to pass through) |
| on | on | `pl` | translate + tone (today's behaviour) |
| on | on | `en` | none |
| any | any | unknown | none |
| any | any | any, and the transcript is ≤ 3 words | none when the action would otherwise be a transform of unknown-language text |

Language source of truth (report §1.2, §1.3, §1.4): the whisper engine's own result from the same
`whisper_full` call the dictation path already makes — read `context.fullLangId` immediately after
`context.full(...)` (`WhisperEngine.swift:261`, before the state free at `:155`) and surface it as
`MyWhisperContext.langStr(id:)`, guarded by `context.isMultilingual`. A fixed `whisperLanguage`
setting is authoritative and needs no detection. Parakeet/FluidAudio offers no signal: `nil`.
**Never set `params.detectLanguage = true`** — whisper.cpp returns after detection and transcribes
nothing (measured `n_seg = 0`).

Fallback: a pure text heuristic (`Utils/LanguageDetector.swift`, new) implementing exactly the rule
set in report §2.1 (diacritics + function words + bigrams; tie ⇒ unknown). No model call for
detection; a classification call to the endpoint is explicitly rejected as a first-line signal.

## Firstmate calls (deviations from the report, both deliberate)

1. **Unknown language with translation on: passthrough, not the "unified" call.** Report §2.4 ranks a
   single unified "translate if Polish, otherwise return unchanged" call (measured 19/22) for the
   case where the engine gave nothing and the heuristic is unsure. That case is rare (the heuristic
   was 16/16 on real engine transcripts) and the safest behaviour is to paste what was said. Do not
   add the unified prompt variant; return the raw transcript. Document the choice in the code comment.
2. **`toneEnabled` defaults to `false` and there is no migration.** A `true` default would start
   rewriting dictation for installs that never enabled anything. Keep every existing install
   bit-identical until the switch is flipped. Do not add the optional migration in
   `AppPreferences.migrateOldPreferences()`.

## Definition of done

- `fm/fm-20260923-05` in `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-05` holds a
  clean, committed branch; no push, no PR.
- `Utils/LanguageDetector.swift`, the policy function, the optional-tone prompt composition, the
  `toneEnabled` preference and its Settings toggle, the engine language plumbing, and the updated
  caption all landed, following report §4's insertion points.
- Never-throw contract preserved: the gate always returns text (`TranslationService.swift:70-77`),
  and the raw transcript is still what reaches the recording store *before* the transform
  (`IndicatorWindow.swift:266/275` precede `:280`).
- Tone-only results whose language changed are discarded and the raw transcript is used (report §3.4)
  — the implementation must compare the heuristic's verdict on input and output.
- `Scripts/verify-transform.sh` extended to assert the new prompt shapes against the running backend
  (translate-only must contain no tone wording; tone-only must contain the same-language wording);
  the backend is already up on `127.0.0.1:1919`.
- Tests per report §5: the policy table (`none` rows assert the input text is returned **and** zero
  requests were made), the three prompt compositions, the pref round-trip, the heuristic table plus
  its adversarial cases, and the engine-language-to-policy wiring. `KeyboardSimulatorTests` needs no
  change.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./run.sh build` reports success with a
  non-zero exit code impossible to fake (the gate is fixed), and
  `xcodebuild test -scheme OpenSuperWhisper -destination 'platform=macOS,arch=arm64'
  -only-testing:OpenSuperWhisperTests` passes except the known pre-existing
  `NoMicrophoneGuardTests.testIndicatorViewModel_startRecording_withNoMicrophone_showsNoMicrophoneState`
  failure, which also fails at `bd5ad0e` with every feature file reverted — leave it failing, do not
  paper over it.
- Small conventional commits (`feat(transform):`, `feat(settings):`, `test:`, `fix:`).

## Worktree isolation assertion

Work in the worktree at `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-05` ONLY, branch
`fm/fm-20260923-05` (created from `feat/local-translate-tone` @ `bd5ad0e`). This path is NOT the
primary checkout. Never touch `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`, and never modify the
user's live preferences or app data under `~/Library/Application Support/`.

## Delegation guard

You are a crew member. Do not spawn subagents. If you need more depth, say so in your final report.

## Report

Outcome, files changed, exact commands, the test count, the heuristic's measured accuracy on the
report's own cases, any honest failure, and anything you deliberately did not do. Never claim
success you did not verify.
