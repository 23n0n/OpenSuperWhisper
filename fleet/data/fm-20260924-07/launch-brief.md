# Task fm-20260924-07 — OpenSuperWhisper — ship — mode=local-only

## Captain's decision (verbatim)

> "Given this we will be dropping completely translation feature and keep only transcription, tone and
> judgment as a feature. So basically we will always keep the language recorded. So if it's Polish we
> will keep Polish, if it's English we will keep English and that's all."

Confirmed with him the same day, as four explicit choices:

1. **Tone** = a *same-language* rewrite, in both languages: Polish tone stays Polish, English tone stays
   English. There is no direction change anywhere in the product any more.
2. **The 8B** (`qwen3-8b-q4_k_m`) stays as an **optional** backend that **Polish prefers when it is
   installed**; when it is absent, Polish work runs on the shipped `qwen2.5-1.5b-instruct-q4_k_m` and the
   app says which model is in use. Nothing needs to be downloaded for the feature to work.
3. **"Judgement"** is the existing clean-up pass plus the reference/glossary field, running in the
   language that was spoken.
4. **The external endpoint override** (Settings → Advanced → external endpoint, `transform-server.sh`,
   `verify-transform.sh`'s endpoint mode) is **removed**. In-process only.
5. **The manual Language picker is removed: the engine always auto-detects.** Asked directly, the captain
   chose this over keeping a picker with a mismatch warning. So `whisperLanguage` stops being a user setting
   (`params.language = nil` always, `params.detectLanguage` stays `false` as it must), the Language control
   leaves Settings and onboarding, and the English-only-model guard is re-keyed: with no setting to compare
   against, it fires on the *detected* signal — an `.en` model cannot detect anything, so the guard's
   warning must be based on what the transcript itself looks like (the existing `LanguageDetector`
   heuristic) rather than on a preference that no longer exists. Tests that pin the picker or the old guard
   condition are rewritten with it.

The language of the transcript is never changed by the app. That is the whole point of this task.

## Why this supersedes what is on the delivery branch

The translation feature was built, measured and landed earlier the same day (`fm-20260923-13`,
`-17`, `-28`; `TransformPolicy` cross-language rows, the `Translate into …` switch, the Target-language
picker, routing by output language, the 8B-for-Polish rationale). The captain has now removed the
requirement. **Do not try to preserve that behaviour behind a switch, and do not leave it half-alive.**
This is a cutover: the translation paths are deleted, not deprecated.

One thing worth knowing while you work: the speech engine never translated anything. `params.translate`
in `OpenSuperWhisper/Whis/WhisperFullParams.swift` defaults to `false` and the app never assigns it
(`Engines/WhisperEngine.swift` sets language, temperature, thresholds — not `translate`). So every
Polish→English result the captain ever saw came from our own transform with an English target, which is
exactly what this task removes.

## Firstmate spec

1. **Delete the cross-language policy.** `TransformPolicy` (`TranslationService.swift`) keeps only what a
   same-language rewrite needs: clean-up, tone, or both. The `source != target` machinery, the
   `TransformLanguage` target parameter and the target-language preference all go. Keep the read of the
   *spoken* language: it decides which model is preferred and feeds the English-only-model guard.
2. **Rewiden the tone.** Tone is now applied to the transcript in its own language: the prompt says
   "rewrite this text in a formal/casual/neutral tone, keep its language exactly, change nothing else".
   The tone switch keeps its existing home and default; the sentence that says "a tone rides on a
   translation" is no longer true and must not survive anywhere — code comments, Readme, Settings copy.
3. **Model choice becomes a preference, not a requirement.** Polish tone/clean-up uses the 8B *when it is
   installed* and the 1.5B otherwise; English uses the 1.5B. `TransformModelManager.modelID(...)` loses
   its output-language meaning and gains this one. The Settings card must state which model a direction
   will use and whether the 8B is present — the existing "the card says which direction is waiting for
   its model" test becomes "the card says which model each language uses". **Nothing is refused for a
   missing 8B any more**, because nothing is *required* for correctness; the app must not present it as
   an error.
4. **Remove the surface, not just the plumbing:** the `Translate into …` toggle, the **Target language**
   picker, the external-endpoint override in Settings → Advanced, `Scripts/transform-server.sh` and the
   endpoint mode of `Scripts/verify-transform.sh`; `AppPreferences.translateEnabled`,
   `transformTargetLanguage`, `transformEndpoint`, `transformUseExternalEndpoint`, `transformTimeout`
   and any `TranslationService` HTTP path. Update the Readme sections that describe translation as a
   feature (the fork's own "Added by this fork" / "What this fork changes" text describes it in several
   places) so the documentation matches the product.
6. **Keep exactly as they are:** transcription itself and every other engine setting, the dictation
   clean-up pass and reference field (`Utils/DictationScrubber.swift`), the last-dictation card, keystroke
   delivery, the idle unload, the warm-up, and `params.noTimestamps = false`. The English-only-model guard
   stays as a *feature* but changes how it decides — see item 5.
6. **Tests are part of the cutover.** The suites that pin translation semantics
   (`TranslationServiceTests`, `TransformBackendTests`, `PolishOutputBackendIntegrationTests`,
   `TranscriptionLanguageGateTests`, `LlamaRuntimeIntegrationTests`, the Settings snapshot/exposure
   cases that assert the removed controls) must be rewritten around the new contract:
   **same language in, same language out**, tone applied when on, clean-up applied when on, no model call
   when both are off, and the 8B preferred for Polish when present. Do not keep a test that asserts
   translation. Do not weaken an unrelated assertion to make a suite pass.

## Verification (execution, not inspection)

- A same-language run in both directions with the real weights: Polish in → Polish out (byte-identical
  language, tone applied when the switch is on), English in → English out. Quote the outputs.
- With both switches off: **zero** model calls, transcript unchanged — quote the evidence that no call
  happened.
- With the 8B absent and Polish work requested: the app uses the 1.5B, says so, and produces Polish
  output; nothing is refused and nothing is substituted silently in the other direction.
- A Polish transcript must come out Polish through every switch combination; the words "translate",
  "target language" and "into English" must not appear in the UI copy any more (grep the app's strings
  and quote the result).
- The Language control is gone from Settings and onboarding, and a dictation in each language transcribes
  correctly with no setting to make: quote one Polish and one English dictation with the detected language
  and the transcript.
- `Scripts/dev-run.sh test` headless, clean state, green, output at `/tmp/fm2407-suite.log`; bundle
  identity-signed afterwards (`certificate leaf`, never a bare `cdhash`).

## Worktree isolation assertion

Create the worktree at dispatch, from the delivery tip after `fm/shortcut-recorder` has landed (both
tasks edit `Settings.swift`; they must not overlap):

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-translation-off \
  -b fm/translation-off <delivery tip>
git -C <worktree> -c protocol.file.allow=always submodule update --init --recursive
```

Work in that worktree ONLY. Never edit the primary checkout's sources or another crew's worktree.
Worktree builds carry bundle id `ru.starmel.OpenSuperWhisper.dev`. **Headless only:** never launch the
app, never `osascript`, never a bare `xcodebuild test`, never `Scripts/dev-run.sh` without a mode
argument.

## Delegation guard

You are a crew member. Do not spawn subagents. No push, no merge, no branch deletion.

## Definition of done

Committed branch; translation paths deleted rather than disabled; tone rewritten as a same-language
rewrite; the model choice a preference with the app saying which model each language uses; the removed
controls gone from the UI and the prefs (translation switch, target picker, Language picker, external
endpoint); auto-detection always on with the guard re-keyed to the detected signal; tests rewritten to the
new contract and green; Readme matching the product; `fleet/data/fm-20260924-07/report.md` and a UTC-stamped
`status.log` line; an honest note of anything left unverified or deliberately kept.
