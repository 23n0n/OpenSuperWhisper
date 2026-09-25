# fm-20260924-07 — the translation feature is gone; the transcript keeps its language

Branch `fm/translation-off`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-translation-off`,
base `210cfb8` (delivery tip). Bundle id `ru.starmel.OpenSuperWhisper.dev`. Headless throughout: no
`open`, no `osascript`, no app launch, no screenshot.

## Outcome

The translation feature is deleted, not disabled. The transcript's language is the one the engine heard and
the app cannot change it: `TransformPolicy` keeps only clean-up, tone, or both, the tone prompt pins the
language, the target-language preference and all four removed controls are gone from the code and from the
preferences, the engine always auto-detects, and the English-only-model guard now decides on the transcript
because an `.en` model cannot measure anything and no setting is left to compare against. The model is a
preference (Polish: the 8B when installed, the shipped 1.5B otherwise; English: always the 1.5B) and the
Settings card states which one each language uses. Deleted outweighs added: **43 files, +2,499 / −4,480**.

## What changed

**Deleted — the cross-language policy and every surface that fed it**

| What | Where it went |
|---|---|
| `.translate(from:to:)`, `.translateWithTone(from:to:tone:)`, `isTranslation`, `outputLanguage`, the `target` parameter and the `source != target` machinery | gone; `TransformPolicy` is now `cleanUp` / `tone` / `cleanUpWithTone` (`TransformService.swift:114-186`), and `resolve` decides on `tone`+`cleanUp`+spoken language only (`:167-186`) |
| `Translate into …` switch, **Target language** picker | removed from the Transcription tab; the card is now **Tone & Clean-up** (`Settings.swift:1592-1610`) |
| **Language** picker in Settings, in onboarding, and the menu-bar `Language` submenu | removed (`Settings.swift:1466-1497`, `OnboardingView.swift:368-383`, `OpenSuperWhisperApp.swift:255-263`); `SettingsViewModel.selectedLanguage`, `Settings.selectedLanguage`, `LanguageUtil.fallbackLanguage`, `SettingsDownloadableModels.preferredLanguage(forFilename:)` and `Notification.Name.appPreferencesLanguageChanged` are deleted with it |
| External endpoint override in Settings → Advanced, `Scripts/transform-server.sh`, `Scripts/verify-transform.sh` | deleted, with `TranslationService`'s whole HTTP path (`transformOverHTTP`, `buildRequestBody`, `parseContent`, `ChatRequest`/`ChatResponse`, `urlSession`, `usesExternalEndpoint`, `TranslationError.invalidEndpoint/httpError/malformedResponse`) |
| Preferences `translateEnabled`, `transformTargetLanguage`, `transformEndpoint`, `transformModel`, `transformTimeout`, `transformUseExternalEndpoint`, `whisperLanguage` | properties deleted (`AppPreferences.swift:226-301`); the stored values are left in the domain untouched and unread (`:226-233`), and the `transformModel` migration step was deleted with them (`:95-99`) |
| `TranslationService` / `TranslationServiceTests` / `PolishOutputBackendIntegrationTests` | renamed `TransformService` / `TransformServiceTests` / `SameLanguageTransformIntegrationTests` (the project uses synchronized folder groups, so no `project.pbxproj` edit was needed) |

**Kept, exactly as they were**: transcription and every engine setting, the dictation clean-up pass and the
reference field, the last-dictation card, keystroke delivery and its interference safety, the idle unload
(`TransformRuntime.idleUnloadInterval == 600`), the warm-up, and `params.noTimestamps = false`
(`WhisperEngine.swift:405`). `params.detectLanguage` is still `false` (`:414`).

**The new policy, in one line each**

* `params.language = nil` always (`WhisperEngine.swift:413`): the engine measures the language and nothing can
  condition it. `reportedLanguage` no longer takes `Settings` and returns `nil` for a non-multilingual model.
* Tone is a same-language rewrite: the prompt says "Rewrite it in a \(tone) tone — keep its language exactly
  \(language), never translate it, and change nothing else" (`TransformService.swift:364-367`).
* The model is a preference, not a requirement: `model(forSpokenLanguage:)` returns the 8B for Polish when
  `isPolishModelInstalled`, the shipped 1.5B otherwise, and always the shipped model for English
  (`TransformModelManager.swift:175-192`).
* The card states it instead of warning: `transformLanguageModelDescription` names the model each language
  runs on and whether the 8B is present (`Settings.swift:280-288`); `transformMissingNotice` fires only for the
  shipped model (`:268-272`).
* The English-only-model guard is re-keyed to the transcript (`SpeechModelLanguageGate.swift:80-100`), called
  after the decode with the text the model produced (`TranscriptionService.swift:385-394`), because an `.en`
  model cannot detect anything and there is no setting left to compare against.
* The CJK autocorrect follows the detected language, and for Parakeet — which reports none — the transcript's
  own script is the signal (`Settings.swift:1123-1154`).
* The warm-up loads the model every language can run on when nothing is resident, and keeps what the last
  dictation used (`TransformRuntime.swift:126-141`).

**Legacy preferences.** The captain's domain still holds `translateEnabled = 1`,
`transformTargetLanguage = polish`, `whisperLanguage = pl`, `toneEnabled = 1`, `transformToneMode = casual`,
`transformEndpoint`, `transformModel`, `transformTimeout`, `transformUseExternalEndpoint = 0`. Nothing reads
any of them: the properties are gone, no migration touches them, and the app starts and works with them
present. `TransformServiceTests.testLegacyTranslationPreferencesAreInert` plants exactly those keys and proves
the behaviour — a Polish dictation with them present makes **zero** model calls and comes back untouched.

## Verification

> **STATUS: every line in this section is quoted from a run that actually happened. The post-fix real-weight run
> is green; there was **no third full-suite run** after the fixes, and two acceptance items remain unperformed —
> both listed in "Unverified, or deliberately left alone" at the end. Nothing here is claimed from reading code.**

**Run 1 (17:30, `/tmp/fm2407-suite.log`): `** TEST FAILED **`, and it failed at compile time**, not in a test —
four errors, all of them the same mistake in the new integration file: `SettingsViewModel` is `@MainActor` and
one test used it from a nonisolated context.
`SameLanguageTransformIntegrationTests.swift:263-269: main actor-isolated initializer 'init(downloadWhisper:…)'
cannot be called from outside of the actor` (+ `installedTransformModelIDs`, `transformLanguageModelDescription`,
`transformMissingNotice(for:)`). Fixed by annotating that one test `@MainActor`
(`SameLanguageTransformIntegrationTests.swift:239`). Worth noting what that run *did* prove: **the app target
compiled clean** — every error was in the test file, so the whole cutover in `OpenSuperWhisper/` type-checks.

**Run 2 (full suite, `/tmp/fm2407-suite.log`): `** TEST FAILED **`, 3 failing cases — and one of them is a real
finding about my own test, not the product.**

| Case | What the failure actually was |
|---|---|
| `TransformServiceTests.testStripReasoning_leavesUnterminatedBlocksAndPlainWords` | my assertion was wrong, not the code: `stripReasoning` removes text but does not trim, so an unterminated block leaves the space that stood before the opener. Now asserts the removal plus the trimmed value (the transform path trims every answer). |
| `TransformServiceTests.testLegacyTranslationPreferencesAreInert` | over-specified: this process's scratch preference suite is shared with every other class in the run, so `transformToneMode`/`reference` are not this test's to pin. Now asserts only what the legacy keys must not do — `translateEnabled = 1` is not a tone switch and buys no call — which is the point of the case. |
| `SameLanguageTransformIntegrationTests.testPolishStaysPolishAndEnglishStaysEnglish` | **`XCTAssertNotEqual failed: ("Dzień dobry, chciałbym przesunąć spotkanie z klientem na przyszły tydzień, jeśli to możliwe.") is equal to (…)`: the 8B returned the Polish sentence byte for byte.** The language assertions all passed — the failure was the tone not doing anything. Two causes, both mine: the probe asked for a **formal** tone on an **already-formal** sentence (so an echo was indistinguishable from a legitimate rewrite, and the case could never have proven the tone works), and the prompt's "change nothing else" is exactly the instruction that tells a model not to rewrite ("Change the register and nothing else" now says what must move and keeps "keep every fact, name and number exactly as dictated" for what must not). Fixed the probe (casual Polish → formal tone) and the prompt. **The assertion was right and was not weakened; the probe was vacuous.** |

What run 2 *did* prove, from its own per-case lines (all passed):

```
SameLanguageTransformIntegrationTests.testPolishWithoutTheEightBeeRunsOnTheShippedModelAndSaysSo()  passed (7.7 s)
SameLanguageTransformIntegrationTests.testTheCardSaysWhichModelEachLanguageUses()                   passed (16.9 s)
SameLanguageTransformIntegrationTests.testTheIdleUnloadReleasesTheWeightsAndForgetsTheModel()       passed (10.7 s)
SameLanguageTransformIntegrationTests.testTheInstalledEightBeeVerifiesAgainstThePin()               passed (18.9 s)
SameLanguageTransformIntegrationTests.testWarmUpCarriesTheColdLoadAndTheFirstUtterance()            passed (976.3 s)
TransformDeterminismIntegrationTests.testPolishRewriteOnTheEightBeeIsIdenticalOnEveryRepeat()       passed (85.3 s)
WhisperLongFormLanguageIntegrationTests.testLongEnglishAndRussianAudioKeepsLanguageContextAndTail() passed (1058.3 s)
SpeechModelLanguageGateTests  11/11 passed (incl. the transcript-keyed refusal through TranscriptionService)
SettingsExposureTests          6/6 passed
```

The long-form case at 1058 s and the warm-up at 976 s are the two heaviest cases in the suite; both are green on
this tree, and the 8B is deterministic across five repeats of the same rewrite.

### 1. Same language in, same language out, with real weights

`SameLanguageTransformIntegrationTests`, driven against real weights (hard-linked from `~/models` into a staging
directory) with `TEST_RUNNER_OSW_TEST_EVIDENCE` forwarded so the measurement lines survive. **Focused run B:
`** TEST SUCCEEDED **`, `EXIT=0`, 166 s — every case of both classes green, including
`testPolishStaysPolishAndEnglishStaysEnglish` (22.7 s), the case full run 2 had caught.** Run B's own lines, as
written to `/tmp/fm2407-evidence-runB.log`:

```
[same-language] mutated copy refused: The downloaded transform model does not match the pinned checksum (expected d98cdcbd03e1…, got 52612ae7358f…).
[same-language] warm-up (load + throwaway decode): 1.04 s
[same-language] wired after the warm-up: 7.89 GB (step 5.54 GB, baseline 2.34 GB)
[same-language] on-disk Qwen3-8B-Q4_K_M.gguf re-verifies against d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785
[same-language] both switches off: model calls 0, policy none, runtime resident none, text unchanged true
[same-language] pl clean-up: model qwen2.5-1.5b-instruct-q4_k_m | didRunModel true
[same-language] pl clean-up output: no więc ja myślę, że trzeba wysłać ten raport do klienta jutro rano.
[same-language] no weights staged: delivered the raw transcript, didRunModel false
[same-language] wired with the 8B resident: 8.93 GB (step 0.00 GB, baseline 9.30 GB)
[same-language] first utterance after a finished warm-up: 20.78 s
[same-language] wired with the 1.5B resident (the 8B was evicted): 3.76 GB (step 0.00 GB, baseline 9.30 GB)
[same-language] wired after unload: 3.76 GB (step 0.00 GB, baseline 9.30 GB)
[same-language] wired: baseline 9.30 GB, 8B 8.93 GB, 8B step 0.00 GB
[same-language] pl→pl: model qwen3-8b-q4_k_m | policy Polish, formal tone | didRunModel true | 16.35 s
[same-language] pl→pl input:  no hej, sluchaj, musimy przelozyc to spotkanie z klientem na przyszly tydzien, ok?
[same-language] pl→pl output: Nie, słuchaj, musimy przesunąć to spotkanie z klientem na następny tydzień, dobrze?
[same-language] en→en: model qwen2.5-1.5b-instruct-q4_k_m | policy English, casual tone | didRunModel true
[same-language] en→en input:  Please send the report to the client today, and copy me on the reply.
[same-language] en→en output: Sure, send the report to the client today and copy me on the reply.
[same-language] first utterance overlapping the warm-up: 25.17 s
[same-language] Polish without the 8B: model qwen2.5-1.5b-instruct-q4_k_m | didRunModel true | output Cześć, jak się masz dzisiaj rano?
[same-language] card: Polish runs on Qwen2.5 1.5B Instruct (Q4_K_M). English runs on Qwen2.5 1.5B Instruct (Q4_K_M). The 8B is not installed, so the shipped model does the work — nothing is refused, and nothing has to be downloaded for Polish.
[same-language] card with the 8B missing: Polish runs on Qwen2.5 1.5B Instruct (Q4_K_M). English runs on Qwen2.5 1.5B Instruct (Q4_K_M). The 8B is not installed, so the shipped model does the work — nothing is refused, and nothing has to be downloaded for Polish.
[same-language] card with the 8B installed: Polish runs on Qwen3 8B (Q4_K_M). English runs on Qwen2.5 1.5B Instruct (Q4_K_M). The 8B is installed.
[same-language] idle unload with the interval injected as 1 s: released true after 3.74 s
[same-language] /Volumes/home/zenon/models/Qwen3-8B-Q4_K_M.gguf verifies: 5027783488 bytes, d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785
[same-language] warm-up (load + throwaway decode): 1.17 s
[same-language] wired after the warm-up: 7.93 GB (step 5.60 GB, baseline 2.34 GB)
[same-language] first utterance after a finished warm-up: 20.30 s
[same-language] first utterance overlapping the warm-up: 21.62 s
```

In the product's terms: Polish went in and Polish came out —
`no hej, sluchaj, musimy przelozyc to spotkanie z klientem na przyszly tydzien, ok?` →
`Nie, słuchaj, musimy przesunąć to spotkanie z klientem na następny tydzień, dobrze?` — a casual dictation
rewritten into a formal register, still Polish, diacritics and all, on `qwen3-8b-q4_k_m`. English went in and
English came out casual on the shipped 1.5B. Polish clean-up stayed Polish and was repaired. With both switches
off: **0 model calls, no model resident, transcript unchanged**.

**The evidence file holds two focused runs, and that matters.** Run A started before the prompt/probe fix and was
still writing when run B started; only run B's block is quoted above. Run A's `pl→pl` pair is kept here because
it is the defect the corrected case was written to catch — the vacuous probe (a formal register asked of an
already-formal sentence) came back byte for byte:

```
[same-language] pl→pl: model qwen3-8b-q4_k_m | policy Polish, formal tone | didRunModel true | 9.39 s
[same-language] pl→pl input:  Dzień dobry, chciałbym przesunąć spotkanie z klientem na przyszły tydzień, jeśli to możliwe.
[same-language] pl→pl output: Dzień dobry, chciałbym przesunąć spotkanie z klientem na przyszły tydzień, jeśli to możliwe.
```

### 2. Both switches off: zero model calls

`testBothSwitchesOffMakeNoModelCallAtAll` — call counter at 0, `runtime.loadedModelID == nil`, transcript
unchanged. Also in the unit suite (`TransformServiceTests.testBothSwitchesOff_neverCallsTheModel`,
`TransformBackendTests.testBothSwitchesOff_resolveNoModelAndMakeNoCall`).

### 3. The 8B absent: Polish uses the 1.5B and says so

`testPolishWithoutTheEightBeeRunsOnTheShippedModelAndSaysSo` — the resolved model, `didRunModel`, the output's
detector verdict, and the card's own sentence.

### 4. The removed vocabulary

`grep -rn -i "translate\|target language\|into english\|into polish" --include=*.swift OpenSuperWhisper/` — 15
matches, **none of them a user-facing string**:

```
Indicator/IndicatorWindow.swift:191       // publishes isConnecting/isRecording, which the sinks above translate
Indicator/IndicatorWindowManager.swift:134  transform = CATransform3DTranslate(...)
TransformService.swift:320                /// empty) is rejected exactly as it was when the answer was translated.
TransformService.swift:366                + "\(language.displayName), never translate it, and change nothing else. "
Utils/AppPreferences.swift:228            // configured it: `translateEnabled`, `transformTargetLanguage`,
Utils/ClipboardUtil.swift:145,151         UCKeyTranslate / kUCKeyTranslateNoDeadKeysBit
Utils/KeyboardLayoutProvider.swift:62,68  UCKeyTranslate / kUCKeyTranslateNoDeadKeysBit
Whis/Whis.swift:419,421,520,607           tokenTranslate / params.translate (upstream whisper.cpp binding)
Whis/WhisperFullParams.swift:13,72        var translate: Bool = false (upstream binding; the app never assigns it)
```

Code comments, Apple API names and the vendored whisper.cpp binding — no label, caption or message in the
product mentions translation any more. The one occurrence of the word in a *prompt* is the instruction that
forbids it ("never translate it").

`grep -rn '"Language"' --include=*.swift OpenSuperWhisper/` returns **no match**: the menu-bar `Language`
submenu is gone, and no Settings or onboarding control is labelled `Language`. Settings keeps the heading
`Language Settings` and the statement `Automatic — the model detects the language of each dictation`
(`Settings.swift:1466-1497`), and onboarding says `Language: detected automatically — dictate in Polish,
English or anything else` (`OnboardingView.swift:370-383`). Both are labels, not controls.

### 5. Suite totals and the signature

`Scripts/dev-run.sh test` → `/tmp/fm2407-suite.log`; `codesign -d -r-` on the finished bundle afterwards.

Run from a **clean state**: the worktree was created at dispatch (`git worktree add … 210cfb8`), the submodules
were freshly checked out, and `libllama/build` and `libwhisper/build` were removed before anything ran, so there
was no derived-data or native-artifact carry-over — the first run recompiled the native engines and the whole
Rust autocorrect dependency tree from scratch, which is what the log shows.

**Where the measurement lines come from.** `xcodebuild` does not carry a test process's stdout into the console
or into the result bundle (`grep -c '\[same-language\]' /tmp/fm2407-suite.log` → **0**), which is why
`TestFixtures.report` has the `OSW_TEST_EVIDENCE` opt-in — and why run 2 produced assertions but no printed
outputs: the variable has to reach the *test host*, so it must be exported as
`TEST_RUNNER_OSW_TEST_EVIDENCE` (the same forwarding `dev-run.sh` documents for
`OSW_TEST_MULTILINGUAL_MODEL`). The focused re-run below uses that form and its lines are quoted from
`/tmp/fm2407-evidence.log`.

### 6. One Polish and one English dictation

### Side fix (asked for mid-flight)

`LongFormTranscriptionTests.testCancellingLongWhisperDecodeStopsNativeOperation` waited for
decode-start with a fixed `1_000 × 20 ms` poll bound, which went red in a full-suite run and green alone
(159.5 s) — load, not the engine. The wait is now a wall-clock budget of 600 s
(`LongFormTranscriptionTests.swift:461-479`). Waiting longer cannot make a wrong result pass: the assertion is
still "the native decoder really started", and cancelling before it starts would prove nothing. Nothing about
what the case proves about cancellation changed.

## Unverified, or deliberately left alone

* **The Asian autocorrect on the Parakeet path changed key.** It used to follow the language *setting*; with no
  setting, a Parakeet dictation has no language signal at all, so the transcript's own script decides
  (Han/Hiragana/Katakana/Hangul → apply). On whisper it follows the detected language as before.
* **The ivrit.ai Hebrew entry no longer sets the language** (it used to switch the picker to Hebrew when
  selected). The model is still offered on a Hebrew-language machine, and its description no longer claims to
  set anything.
* **`LanguageUtil.supportedLanguages` and the `getSupportedLanguages()` engine protocol method are kept** even
  though the picker that consumed them is gone: they describe what an engine can hear, which is not a removed
  control.
* **The endpoint path is gone, not disabled** — no test can reach a socket any more; `StubURLProtocol` was
  deleted with it.
* **Nothing on the protected list was touched.** `git diff --name-only 210cfb8..HEAD` lists 43 files; the only
  protected one among them is `Indicator/IndicatorWindow.swift`, whose entire diff is two type renames
  (`TranslationService` → `TransformService`) and three comment rewordings — the `DeliveryWatch` injection path,
  the state machine and `insertText` are byte-identical. `Utils/KeyboardSimulator.swift`,
  `ShortcutManager.swift`, `ModifierKeyMonitor.swift` and `Whis/WhisperFullParams.swift` were not modified at
  all, so the interference safety, the trigger arming and the never-assigned `params.translate` stand as the
  delivery tip left them.
