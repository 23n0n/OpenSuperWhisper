# fm-20260924-11 — tone output: routing (A) + prompt/framing/guard (B)

**Status: A and B are implemented in code and proven where proof does not need the weights.
The weight-backed measurements (two languages on the 8B) and the full suite are NOT done** — the
first mate's revised instruction put a hard stop at 06:00 UTC, before either could be started
(peak billing 06:00–10:00 UTC). Everything below is exactly what was executed, plus what was not.

Branch `fm/tone-output`, worktree `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone`,
based on delivery tip `3dcde52`.

## A — routing

`TransformModelManager.model(for policy:)` resolves per job:

| job | language | 8B installed | 8B absent |
|---|---|---|---|
| tone (`.tone`, `.cleanUpWithTone`) | English | `qwen3-8b-q4_k_m` | `qwen2.5-1.5b-instruct-q4_k_m` |
| tone (`.tone`, `.cleanUpWithTone`) | Polish | `qwen3-8b-q4_k_m` | `qwen2.5-1.5b-instruct-q4_k_m` |
| clean-up alone | Polish | `qwen3-8b-q4_k_m` | `qwen2.5-1.5b-instruct-q4_k_m` |
| clean-up alone | English | `qwen2.5-1.5b-instruct-q4_k_m` | `qwen2.5-1.5b-instruct-q4_k_m` |

`TransformService` now injects `modelForPolicy: (TransformPolicy) -> TransformModel`; the policy is
what carries the language, so a tone policy can prefer the 8B in English without touching the
language rule. Nothing is refused, nothing substituted silently: the caller is handed the model that
will really run, and Settings states it.

### Proven by execution (no weights needed — the decision is file presence)

Harness: real `TransformModelManager.swift` + real `Utils/LanguageDetector.swift`, compiled
standalone with the shared `ModelDownloadDelegate` stubbed; a catalogue of two test models in a
temp directory, then the 8B's file installed through the manager's own `install(fileAt:model:)`
(pinned-digest verified) and the table re-read:

```
— 8B NOT installed (isPolishModelInstalled=false) —
PASS tone EN formal: qwen2.5-1.5b-instruct-q4_k_m
PASS tone PL casual: qwen2.5-1.5b-instruct-q4_k_m
PASS cleanUpWithTone EN: qwen2.5-1.5b-instruct-q4_k_m
PASS cleanup-only EN: qwen2.5-1.5b-instruct-q4_k_m
PASS cleanup-only PL: qwen2.5-1.5b-instruct-q4_k_m
— 8B installed (isPolishModelInstalled=true) —
PASS tone EN formal: qwen3-8b-q4_k_m
PASS tone PL formal: qwen3-8b-q4_k_m
PASS cleanUpWithTone EN: qwen3-8b-q4_k_m
PASS cleanup-only EN: qwen2.5-1.5b-instruct-q4_k_m
PASS cleanup-only PL: qwen3-8b-q4_k_m
ROUTING TABLE OK
```

Second harness, at the service level: the **real `TransformService.swift`** compiled standalone with only the
runtime, the preferences and the error centre stubbed (real `TransformModelManager` + `LanguageDetector` +
`TransformGuard`), staging the 8B through the manager's own install path:

```
PASS tone ran on the 8B once it is installed (Polish): qwen3-8b-q4_k_m
PASS English tone ran on the 8B once it is installed: qwen3-8b-q4_k_m
PASS English tone falls back to the shipped model without the 8B: qwen2.5-1.5b-instruct-q4_k_m
PASS English clean-up alone ran the shipped model: qwen2.5-1.5b-instruct-q4_k_m
```

(`evidence/service-checks.txt`.) That is the "with and without the 8B present" proof the acceptance asks for,
and "clean-up alone on English still on the 1.5B" with it. The same table is asserted in
`TransformBackendTests.testPolishPrefersTheEightBeeAndUsesTheShippedModelWithoutIt` (extended), which runs
without loading weights.

The 10-minute idle unload and the record-start warm-up were **not touched** (no edit in
`TransformRuntime`, `RecordingSessionController` or `TransformModelManager`'s load/unload paths).

### Card and Readme

- Card sentence (`Settings.transformLanguageModelDescription`): *"A tone rewrite runs on Qwen3 8B
  (Q4_K_M), in both languages. Clean-up alone: Polish runs on … English runs on …. The 8B is
  installed."* — with the existing "The 8B is not installed, so the shipped model does the work —
  nothing is refused…" when it is absent. The RAM figure per model is unchanged and still shown on
  each row (~5.6 GB wired for the 8B).
- Row roles: 8B = "Preferred for every tone rewrite and for Polish clean-up — used whenever it is
  installed"; 1.5B = "English clean-up always, and every transform until the 8B is installed".
- Missing-model notice now names all three jobs that wait for the shipped model.
- Settings card prose: tone on the 8B in both languages, English clean-up on the 1.5B, and why.
- Readme: feature bullet, §1 model paragraph, the model table ("Which model each job uses"), the
  known-limits bullet, and a new paragraph on the prompt frame + guard.

## B — prompt, framing, guard

1. **Prompt.** `TransformService.toneInstruction(for:tone:)` replaces the old one-sentence tone line:
   "You are not an assistant…" first, the register defined by *what may change* (`ToneMode.registerDefinition`),
   the must-not-change list (facts/numbers/terms, speaker, order and completeness, language in–out),
   and the output rules (no preamble/labels/markdown, keep line breaks, already-in-register ⇒
   unchanged, fragment/list/noise ⇒ unchanged). Clean-up wording, reference list and `/no_think` ride
   the same prompt as before. `stripReasoning` is untouched.
2. **Framing.** A tone policy now sends the framed user turn —
   `Rewrite this dictated text in a {TONE} register. Keep its language ({LANGUAGE}), the speaker, every fact and every number exactly as dictated. Output only the rewritten text.` +
   `<<<TRANSCRIPT … TRANSCRIPT>>>` (`TransformService.userPrompt(for:language:tone:)`). Clean-up
   alone keeps the bare transcript, which is what it was measured with.
3. **Temperature stays 0.2** — no sampling edit was made anywhere (`TransformRuntime` untouched).

### The guard (`OpenSuperWhisper/TransformGuard.swift`) — text only, no model call

Rejects, and the raw transcript is delivered with a visible notice through
`AppErrorCenter.shared.report(_:message:)` — the same path the injection interruptions use:

| rule | catches |
|---|---|
| assistant frame at the start of the first content line, after markdown/quotes are stripped | `Sure`, `Certainly`, `Of course`, `Understood`, `Here is`, `Here's`, `I've`, `Oczywiście`, `Oto`, `Jasne` |
| label / announcement | a line opening `Register:` / `Output:`, or `rewritten text` / `rewritten version` anywhere |
| stub | input ≥ 8 words and output < 25 % of its words (the measured collapse: 17 words → `Plan done.`) |
| language flip | input classifies as the pinned language (≥ 3 words) **and** output classifies as the other one **and** output shares no content word with the input |

Only the tone path is guarded (`policy.promptTone != nil`); clean-up alone is untouched.
`TransformOutcome.guardRejection` carries the reason for the dictation report.

### Positive and negative cases, executed

Harness: the real `TransformGuard.swift` + the real `Utils/LanguageDetector.swift` compiled
standalone (only the `TransformLanguage` enum mirrored), 19 cases:

```
PASS ack: got assistantFrame(sure) expected assistantFrame(sure)
     input  "Please send the report to the client today, and copy me on the reply."
     output "Sure, send the report to the client today and make sure to copy me on the reply."
PASS preamble: assistantFrame(sure)
     output "Sure, here's the rewritten text in a casual register:\n\nSure, send the report to the client today!"
PASS collapse: assistantFrame(understood)   (17-word run-on → "Understood.")
PASS stub: stub(17,2)                       (same run-on → "Plan done.")
PASS pl-frame-ocz: assistantFrame(oczywiście)   ("Oczywiście, wysyłam raport do klienta.")
PASS pl-frame-oto: assistantFrame(oto)          ("Oto przepisany tekst.")
PASS pl-frame-jasne: assistantFrame(jasne)
PASS label-register: label(register:)   ("Register: formal\nPlease send…")
PASS label-output: label(output:)
PASS label-rewritten: label(rewritten version)  ("The rewritten version: please send the report today.")
PASS flip-en->pl: languageFlip(English)
PASS flip-pl->en: languageFlip(Polish)
PASS n-in-register: nil       (output == input)
PASS n-two-word: nil          ("Send it now." → "Send it.")
PASS n-fragment: nil          ("the deployment is done and")
PASS n-mixed-term: nil        ("We should deploy the backend na produkcję every Friday evening.")
PASS n-rewrite: nil           ("I think we should probably just ship it on friday if nothing breaks" → "I believe we should probably ship it on Friday if nothing breaks.")
PASS n-drift-article: nil     ("invoice number is 423 and the amount is three thousand zloty" → "Invoice number is 423 …")
PASS n-drift-noun: nil        ("…ship it on friday…" → "…ship the product on Friday…")
ALL 19 CASES PASS
```

The same 19 cases are pinned as `OpenSuperWhisperTests/TransformGuardTests.swift` (XCTest).

**Found by execution, not by reading:** the first flip rule (detector verdict alone) *did* fire on the
mixed-language negative case — `We deploy the backend na produkcję every Friday evening.` classifies
as **Polish** because of the diacritics, so a legitimately re-written English sentence came back as a
"flip". The rule now requires the *input* to classify as the pinned language too, and the output to
share no content word with it. That is the one behaviour change the harness forced.

### Which measured 1.5B failures the guard catches, and which it does not

- **catches:** the added `"Sure,"` acknowledgement; the `"Sure, here's the rewritten text in a casual
  register:"` preamble; the temperature-0 `"Understood."` collapse; the same collapse as a plain stub.
- **cannot catch:** **subtle content drift** — the dropped articles (`"invoice number is 423…"`) and
  the invented noun (`"…ship the *product* on Friday…"`) pass the guard untouched (both are pinned as
  passing cases in `TransformGuardTests.testSubtleContentDrift_isOutOfReach`). They are the prompt's
  and the 8B's job. Also out of reach: a rewrite that keeps the language, the facts and the words but
  quietly changes the register's *intent*, and any drift the detector cannot place.

### The prompt and the frame, printed from the code as landed

`TransformService.systemPrompt(for: .tone(language: .polish, tone: .formal), cleanUp: false)` +
`userPrompt(for:…, language: .polish, tone: .formal)` — the exact two messages a Polish formal tone turn sends
(`evidence/service-checks.txt`):

```
You rewrite dictated text. You are not an assistant: never answer it, greet, acknowledge, thank, comment, explain, summarise or continue it.

The user dictated Polish text. Rewrite it in a formal register, in Polish. Nothing else may change.

What the register may change — only these:
- formal: write complete sentences, no contractions ("do not", not "don't"), no slang or filler, polite and professional word choice.

What must stay exactly as dictated:
- every fact, name, number, date, place, product and technical term — never add, never drop, never reword a commitment into a softer or stronger one;
- who is speaking and to whom: first person stays first person, a question stays a question, an order stays an order;
- the order and the completeness of the information — never summarise, never elaborate, never finish a half-sentence with new content;
- the language: Polish in, Polish out. Never translate, not even one word. If a term has no Polish equivalent, keep it exactly as spoken.

Output rules:
- Output only the rewritten text. No quotes, no labels, no preamble, no closing remark, no markdown, no commentary, no explanation of what you changed.
- Keep the dictated line breaks: do not join separate lines, do not split one line.
- If the text is already in the formal register, return it unchanged.
- If the text is a fragment, a list, or noise that carries no sentence, return it as it is.
Output ONLY the final Polish text, with no quotes, labels, or explanation.
/no_think
```

```
Rewrite this dictated text in a formal register. Keep its language (Polish), the speaker, every fact and every number exactly as dictated. Output only the rewritten text.

<<<TRANSCRIPT
wyślij raport do klienta dzisiaj
TRANSCRIPT>>>
```

Clean-up alone sends the wording it sent before this task (bare user turn, no tone text); the harness prints it
for comparison.

### Guard, end to end through the service

The same harness drives `transformDetailed` with a canned answer, so the guard is proven *wired in*, not only
correct in isolation:

```
PASS good answer delivered / no rejection recorded
PASS turn was framed (contains <<<TRANSCRIPT) / prompt names the language
PASS assistant frame rejected: wyślij raport do klienta dzisiaj
PASS rejection recorded: assistantFrame("oczywiście")
PASS label rejected / label recorded: label(register:)
PASS language flip rejected / flip recorded: languageFlip(Polish)
PASS stub rejected / stub recorded: stub(wordsIn: 17, wordsOut: 2)
PASS clean-up-with-tone IS guarded
PASS clean-up alone delivers the answer unguarded / records no rejection
PASS a notice was shown once per rejection: 5
NOTICE: Tone rewrite was not used — The model answered with an acknowledgement ("oczywiście") instead of rewriting the dictation, so your own words were used instead.
SERVICE CHECKS OK
```

**One real bug found this way:** `TransformOutcome.guardRejection` was a `let` with a default, and Swift drops
such a property from the memberwise initializer entirely — the guard path would not have compiled. It is a `var`
with a default now (`b9f6893`), which the initializer carries as an optional parameter. Without this harness that
error would have surfaced only at the deferred `xcodebuild`.


## New captain evidence (received 05:51Z, after the commits) — and what it changes

> **"The tone transcription is also bound with Polish. The English tone transcription works well."**

(His own dictation of it is in the recordings: *"Also the transcription, Tom transcription is also binded
slightly with Polish. English Tom transcription works well."*)

Three consequences, on the captain's terms:

1. **English must not regress — and that is not proven.** `A` as landed sends English tone to the 8B.
   The side-by-side the captain asks for (the same English dictation through the 1.5B — today's behaviour —
   and through the 8B with the new prompt, judged on meaning kept / register moved / nothing added / no
   assistant frame) **was not run**: it is a weight-backed measurement, which the 06:00 UTC stop forbids.
   The honest call made here, and its reason: **the routing was left as landed**, because flipping English
   tone to the 1.5B is not "today's English behaviour" either — today is *old prompt* + 1.5B, and the new
   prompt on the 1.5B is exactly where the measured `"Sure, here's the rewritten text…"` preamble came from
   (`fm-20260924-10`). With the guard in place that preamble would be rejected, so English tone would sometimes
   deliver no rewrite at all — a worse regression than an unmeasured, content-disciplined 8B. What the 8B costs
   English is the RAM figure the card already states (~5.6 GB wired), not a silent refusal.
   **If the measurement says the 8B is not clearly at least as good on English, the flip is one function** —
   in `TransformModelManager.model(for:)`, make the tone case fall through to `model(forSpokenLanguage:)` for
   `.english` — plus the routing table in this report, the card sentence, the row roles, the two Readme tables
   and the policy assertions in `TransformBackendTests`/`SettingsExposureTests`, which all read from that one
   function.
2. **Polish tone is the acceptance focus, and it is unmeasured.** The measurement input is prepared:
   `evidence/captain-dictations.md` holds his **real** dictations out of `recordings.sqlite`, bucketed with the
   app's own `LanguageDetector` (real source, compiled standalone): **7 Polish**, 35 English, 3 unplaceable.
   The Polish set is small and mostly short — e.g. *"Teraz próbuję coś nagrać."*, *"Mogę coś zarzucić za jej w
   tle."*, *"Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że
   żeś pieprzył po całości."* — which is itself the finding to carry forward: **three registers × 7 real Polish
   dictations is thin evidence**, so the next session must report input → output per register and judge
   register-moved / nothing-lost / nothing-invented / no English leakage / no honourific he never used
   ("Szanowni Państwo", Pan/Pani forms), and say plainly if Polish register control on the 8B is weak.
   **Not one output was produced here** — no weights were loaded.
3. **The branch was committed before the stop** and `git status` is clean at head `b9f6893`
   (the parent's "TransformService.swift still modified" was read from an earlier state).

### What the captain's evidence confirms about the design

His Polish failure is the class the guard covers (frames, labels, language leakage) plus the class it does not
(subtle drift) — which is why the acceptance has to be a human judgement over his own recordings, not a green
tick from the suite. Nothing in the new evidence changes B; it sharpens A and makes the English side-by-side the
first thing to run.


## Scoped build + test run (the last gap before the stop, closed)

`Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/TransformGuardTests`, headless, worktree,
no weights loaded. **The app target and the whole test bundle compile, and every guard case passes in-app:**

```
Test suite 'TransformGuardTests' started on 'My Mac - OpenSuperWhisper (1563)'
testAlreadyInRegister_isUntouched            passed
testAssistantAcknowledgement_isRejected      passed
testChatCollapse_isRejected                  passed
testFragment_isUntouched                     passed
testGuardAppliesOnlyToPoliciesThatSendToneText passed
testLabelLines_areRejected                   passed
testLanguageFlip_isRejected                  passed
testMixedLanguageTechnicalTerm_isUntouched    passed
testPolishAssistantFrames_areRejected        passed
testPreambleInsteadOfARewrite_isRejected     passed
testRegisterRewrite_passes                   passed
testSubtleContentDrift_isOutOfReach          passed
testTwoWordDictation_isUntouched             passed
** TEST SUCCEEDED **   (13/13, 53 s; full log evidence/scoped-guard-test-run.log)
```

The first attempt of this run (before the fix below) is what found the two remaining defects, which is why it
was worth starting: a stale `ToneMode.casual.instruction` assertion in `testSystemPrompt_toneAndCleanUp_rideOnePrompt`
(it is `ToneMode.casual.registerDefinition` now, `9c36eae`) and, earlier, the `let`/`var` initializer bug.
Both were compile errors, so nothing about them could have been guessed from reading.

Because the *whole* test target compiled, the edits to `TransformServiceTests`, `TransformBackendTests`,
`SettingsExposureTests` and `SameLanguageTransformIntegrationTests` are now type-checked as well; only their
runtime assertions are still unexecuted (the full suite is the gated step).

### The run's exit code was 51, and it is NOT the tests

`dev-run.sh` exits non-zero because its final **re-sign** step could not run: the local dev keychain is locked
and the stored password no longer opens it —

```
security: SecKeychainUnlock ~/Library/Keychains/opensuperwhisper-dev.keychain-db: The user name or passphrase you entered is not correct.
security: SecKeychainCopySettings …: User canceled the operation.      (no interactive prompt available)
security find-identity -v -p codesigning   →   0 valid identities found
```

so the bundle on disk is still linker-signed, exactly the state `dev-run.sh` exists to prevent:

```
# designated => cdhash H"d6c862b2394dd2389d84ba40f1269bbd695761f8"
Signature=adhoc     Identifier=OpenSuperWhisper
code has no resources but signature indicates they must be present
```

**This is an environment blocker, and it is not mine to clear:** the password file is at
`~/.opensuperwhisper-dev/keychain-password` (present, the unlock still fails), and `Scripts/dev-signing-identity.sh`
would *mint a new identity* — which changes the designated requirement the captain's Accessibility grant is
stored with. So the "bundle identity-signed (`certificate leaf`)" acceptance item is **not met**, and the
first thing the next session should do (after the keychain is unlocked by hand, or the identity re-minted
deliberately) is re-run the suite and check `codesign -d -r-` for a `certificate leaf` requirement.


---

## CLOSING NOTE (received at the boundary, 05:56Z): the captain is deleting the 8B

> **"The captain has decided to delete the 8B completely and run the whole transform on the shipped model."**

Consequences, recorded here so the follow-up task starts from the right place:

1. **Part A's 8B routing is superseded and is dead code.** `TransformModelManager.model(for policy:)`, the
   two-model routing table, the "8B installed / not installed" card copy and the per-job routing assertions all
   exist to choose between the shipped model and the 8B. With the 8B gone there is nothing to choose. Nothing
   further was written for it; the committed state stays as it is and the follow-up task reverts or replaces it —
   `TransformModelManager.model(for:)` and the four Readme places plus the card sentence are the whole surface.
   Do **not** read that code as a live decision; read it as pending deletion.
2. **Part B keeps its full value, and it is what makes the deletion possible.** The prompt, the framed and
   delimited user turn and the guard are model-agnostic: they are exactly what has to carry Polish on the
   shipped 1.5B. B is committed (`741431a`, plus `b9f6893` for the initializer bug and `9c36eae` for the last
   stale assertion) and its tests pass in the app.
3. **What the follow-up must now measure — and the honest state of it.** Nothing was measured on either model:
   no weights were loaded in this session (see §"What is NOT done"). So this report cannot say how Polish tone
   behaves on the 8B *or* on the shipped model with the new prompt. What it can say from the committed
   `fm-20260924-10` A/B is that the new prompt on the 1.5B produced exactly one extra measured failure — the
   `"Sure, here's the rewritten text in a casual register:"` preamble — and that the guard now rejects that
   class. The follow-up therefore has a sharp, single question: **on the shipped 1.5B, how often does Polish
   tone now (a) rewrite well, (b) get rejected by the guard and fall back to the raw transcript with a notice,
   (c) produce content drift the guard cannot see?** The expected shape is that (b) replaces the visible
   garbage — worth stating to the captain, because "sometimes the tone switch leaves the text alone and says
   why" is a different, better failure than a Polish transcript with `"Oczywiście,"` in front of it. If (a) is
   too rare, the next lever is the prompt on the small model (few-shot examples, a stricter output block), not
   the guard, and `TransformGuardTests` already pins the line between the two.
4. The measurement input is ready and model-independent: `evidence/captain-dictations.md` — his real Polish
   dictations out of `recordings.sqlite`, bucketed with the app's own `LanguageDetector`.

## What is NOT done (the honest list)

1. **No weight-backed measurement.** The seven adversarial cases in both languages on
   `qwen3-8b-q4_k_m` with the new prompt and framing were **not run**, and neither was the English
   1.5B-vs-8B side-by-side nor the Polish run over the captain's own recordings — a `llama-server` run is the
   gated step, and the stop at 06:00 UTC forbade starting it. The prompt/framing change is therefore
   *unmeasured*: the evidence that it is equal-or-better on the 8B is the `fm-20260924-10` A/B of the
   same wording, not a new run against the code as landed.
2. **The full suite was not run** (`/tmp/fm2411-suite.log` does not exist) and the bundle is **not**
   identity-signed — see the scoped-run section: the dev keychain will not unlock for this session, so the
   bundle is left linker-signed (`cdhash`). Deferred with the measurement, and the keychain has to be unlocked
   by hand first.
3. **~~No compile of the app target.~~ CLOSED by the scoped run above** — the app target *and* the whole test
   bundle compile clean (`Settings.swift` included), and `TransformGuardTests` is green in-app. What remains
   unexecuted is the rest of the suite's runtime assertions (the full-suite item) and the bundle signature.
4. Test-file updates are **compiled but not executed**: the old-wording prompt assertions were rewritten to the
   new invariant (the prompt names the language and carries the not-an-assistant rule) rather than re-pinned to
   strings; `TransformBackendTests.testEveryTransformRunsInProcess` now asserts the framed turn; the policy
   table asserts the prompt names the language. They type-check with the app; their assertions run in the
   full suite.

## Next step (for whoever resumes — revised by the closing note)

```
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone
Scripts/dev-run.sh test > /tmp/fm2411-suite.log 2>&1        # build + suite + re-sign, off-peak
# then the measurement: llama-server with the app's sampling (0.2 / top-k 40 / top-p 0.95 /
# min-p 0.05, enable_thinking=false) on qwen3-8b-q4_k_m, the seven cases, both languages,
# prompt+frame exactly as landed (system = TransformService.systemPrompt, user = userPrompt).
```

## Commit and diffstat

`741431a` (implementation) + `e194655` (Readme) + `b9f6893` (the initializer fix) + `9c36eae` (the stale
assertion the scoped run caught) on `fm/tone-output` (base `3dcde52`), head `9c36eae`, no push, no merge.
The first commit's diffstat:

```
 OpenSuperWhisper/Settings.swift                    |  26 ++-
 OpenSuperWhisper/TransformGuard.swift              | 217 +++++++++++++++++++++
 OpenSuperWhisper/TransformModelManager.swift       |  41 +++-
 OpenSuperWhisper/TransformService.swift            | 154 +++++++++++++++++---
 .../SameLanguageTransformIntegrationTests.swift    |   2 +-
 OpenSuperWhisperTests/SettingsExposureTests.swift  |  12 +-
 OpenSuperWhisperTests/TransformBackendTests.swift  |  35 +++-
 OpenSuperWhisperTests/TransformGuardTests.swift    | 176 +++++++++++++++++
 OpenSuperWhisperTests/TransformServiceTests.swift  |  41 ++--
 Readme.md                                          |  78 +++++---
 10 files changed, 679 insertions(+), 103 deletions(-)
```

Raw harness output and sources in `evidence/`: `guard-cases.txt`, `routing-table.txt`, `service-checks.txt`
plus the harness sources, and `captain-dictations.md` (the real-dictation measurement fixture).
