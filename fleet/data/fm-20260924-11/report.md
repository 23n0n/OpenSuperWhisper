# fm-20260924-11 — tone output: routing (A) + prompt/framing/guard (B)

**Status: A and B are implemented in code and proven where proof does not need the weights.
The weight-backed measurements (two languages on the 8B) and the full suite are NOT done** — the
first mate's revised instruction put a hard stop at 06:00 UTC, before either could be started
(peak billing 06:00–10:00 UTC). Everything below is exactly what was executed, plus what was not.

**2026-09-25 fix pass:** the three suite failures are fixed and the suite is green (434 total / 380 passed / 0 failed / 54 skipped); the guard's false positives, the warm-up, the dictation report, the copy and the wording-pinning tests are fixed, and the exact compiled prompt is measured in both languages on the 8B — see §`## FIX PASS — 2026-09-25` at the end of this file.**

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

---

## RESUME RUN — 2026-09-25

Second session on the same branch: the two gates the 06:00Z peak stop left unrun.
Nothing about the code, the tests or the fixtures was changed; the worktree is
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone`,
branch `fm/tone-output` @ `9c36eae`. No merge, no push, no tag, no model moved.
Raw output for everything below is in `fleet/data/fm-20260924-11/evidence/`.

### Gate 1 — the full suite: ** TEST FAILED **, 3 real failures

| | result |
|---|---|
| log | `/tmp/fm2411-suite.log` (copy: `evidence/resume-full-suite.log`, 2 865 244 B) |
| xcresult | `<worktree>/build/Logs/Test/Test-OpenSuperWhisper-2026.09.25_09-18-33-+0200.xcresult` |
| total executed | **426** |
| passed | **369** |
| failed | **3** (three distinct test methods) |
| skipped | **54** |
| final line | `/tmp/fm2411-suite.log:20937: ** TEST FAILED **` |
| command | `Scripts/dev-run.sh test`, detached in its own session (macOS has no `setsid`) |

Delivery tip for comparison: 420 total / 367 passed / 0 failed / 53 skipped.
Counts are from `xcresulttool get test-results summary` and agree with the log text
itself (369 / 3 / 54 case lines; one log line is split by xcodebuild's own
interleaved output, which is the only reason a naive log grep shows 368).

**Bundle identity-signed — the re-sign step ran** (this was the previous session's blocker;
the dev keychain unlocks with the stored password this time — `security unlock-keychain`
exits 0 and `find-identity -v -p codesigning` reports 1 valid identity):

```
$ codesign -d -r- <worktree>/build/Build/Products/Debug/OpenSuperWhisper.app
designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
$ codesign --verify --deep --strict …openSuperWhisper.app   → exit 0
```

`certificate leaf`, never a bare `cdhash`. (`spctl -a -vv` rejects the bundle, as expected for a
locally minted, non-notarised identity; that is not a signature defect.)

#### The three failures, verbatim

1. `TransformServiceTests.testPolicyTable_returnsTheInputAndChargesACallOnlyWhenItActs()`
   — `OpenSuperWhisperTests/TransformServiceTests.swift:158`

   ```
   XCTAssertEqual failed: ("Please send the report to the client today.") is not equal to ("rewritten") - tone on, English: the model's answer is what is pasted
   ```

   The guard working, and a stale fixture. The row's input is 8 letter-words, so the new
   `stub` rule is armed (`stubMinimumInputWords = 8`, floor 2), and the fixture answer
   `"rewritten"` is 1 word → `TransformGuard.rejection` returns `.stub(wordsIn: 8, wordsOut: 1)`,
   the raw transcript is delivered instead of the fixture answer, and the expectation of
   `"rewritten"` fails. Independently diagnosed by the first mate before this run finished
   (07:23Z); **not touched here** on his instruction — it is being fixed in a separate pass.

2. `TransformServiceTests.testSystemPrompt_toneOnly_asksForASameLanguageRewrite()` —
   `OpenSuperWhisperTests/TransformServiceTests.swift:238`, six failures, one per
   (language × register):

   ```
   XCTAssertTrue failed - <the whole composed system prompt, verbatim>
   ```

   The assertion is `XCTAssertTrue(system.contains("never translate, not even one word"), system)`.
   The landed prompt says **"Never translate, not even one word."** — capital N, because in
   `TransformService.toneInstruction` it opens a sentence. The assertion still searches for the
   lowercase phrase of the *old* tone line ("… keep its language exactly Polish, never translate
   it, …"), so it fails on a stale string, not on the prompt. Nothing about the prompt is wrong:
   the phrase is present and the failure message prints it.

3. `TranscriptionLanguageGateTests.testEachSpokenLanguageIsRewrittenInItsOwnLanguage()` —
   `OpenSuperWhisperTests/TranscriptionLanguageGateTests.swift:124`

   ```
   XCTAssertEqual failed: (["Rewrite this dictated text in a formal register. Keep its language (Polish), the speaker, every fact and every number exactly as dictated. Output only the rewritten text.\n\n<<<TRANSCRIPT\nCześć, jak się masz?\nTRANSCRIPT>>>", "Rewrite this dictated text in a formal register. Keep its language (English), the speaker, every fact and every number exactly as dictated. Output only the rewritten text.\n\n<<<TRANSCRIPT\nPlease send the report.\nTRANSCRIPT>>>"]") is not equal to (["Cześć, jak się masz?", "Please send the report."]) - each transcription is what the model is given
   ```

   `XCTAssertEqual(recorder.texts, [polishText, englishText], …)`. Part B frames the user turn, so the
   service now hands the model the framed `<<<TRANSCRIPT …>>>` turn instead of the bare transcript.
   This file was not among the four the branch edited, so it still pins the pre-framing behaviour;
   the recorder shows the frame carrying the correct transcript. Stale test, not a behaviour defect.

All three are test-side staleness interacting with part B; none is a product defect. They are
reported, not repaired (`Do NOT change any code, test, or fixture`). The branch's suite is
therefore **red**, and it was red for reasons that only a full-suite run could reveal — the scoped
`TransformGuardTests` run of the previous session (13/13) could not see any of them.

### Gate 2 — the weight-backed measurement: what was measured and how

Three runs, all through `llama-server` with the app's exact sampling — temperature 0.2, top-k 40,
top-p 0.95, min-p 0.05, `chat_template_kwargs.enable_thinking = false`:

1. `qwen3-8b-q4_k_m` — Polish (the shipped route after the captain's decision)
2. `qwen3-8b-q4_k_m` — English (same route, other language)
3. `qwen2.5-1.5b-instruct-q4_k_m` — English (today's shipped English path, for the no-regression side-by-side)

Two harnesses, because the pinned one is not byte-faithful to the landed prompt:

* **`evidence/tone-ab.py`** (sha256 `7effbd09ca046d176e7163b946481d3162f8a2e3cf114242b1c3df0eae1c4157`, identical to
  `/tmp/tone-ab.py`) — the pinned A/B from `fm-20260924-10`, run as it stands for the record.
* **`tone-measure.py`** (also kept in `evidence/`) — the *shipped* prompt, composed exactly as
  `TransformService.systemPrompt(for:cleanUp:false)` and `userPrompt(for:language:tone:)` compose it
  at `9c36eae`, plus per-call latency and JSON output for the guard pass.

**Why the second harness exists — proved, not asserted** (`evidence/resume-prompt-fidelity.txt`):

```
system prompt reconstruction == landed code: True
user turn reconstruction == landed code: True
pinned harness proposal == landed code: False
pinned harness user turn == landed user turn: True
OLD PROMPT COLUMN REPRODUCES PRE-BRANCH CODE: True
```

The reconstruction is compared byte-for-byte against the real compiled service's own output
(`evidence/service-checks.txt`), and the "old" column is compared against `3dcde52`'s
`systemPrompt` + `tone.instruction` read out of git. The pinned harness's *new* prompt differs from
the landed one in exactly two places: it lists all three register definitions where the code emits
only the requested one, and it lacks the code's trailing
`Output ONLY the final <language> text, with no quotes, labels, or explanation.` line. Both columns
of the table below are therefore faithful — old to the pre-branch code, new to the branch.

Guard verdicts are not eyeballed: every output — old and new — was fed through the **real**
`TransformGuard.swift` + the real `Utils/LanguageDetector.swift`, compiled standalone with
`TransformLanguage` extracted verbatim from `TransformService.swift` (`evidence/guard-classify.swift`).

### Gate 2 — results: 100 answers, verbatim

All three runs completed, each with its own bounded `llama-server`; `pgrep llama-server`
returned nothing after every run — nothing is left resident. Latency is the wall time of the
single completion call (Metal, `-t 6`, M-series Mac mini), and includes no model load.

| run | model | language | cases × prompts | answers | latency median (min–max) |
|---|---|---|---|---|---|
| 1 | `qwen3-8b-q4_k_m` | Polish | 28 × 2 | 56 | 1.67 s (0.65–3.52) |
| 2 | `qwen3-8b-q4_k_m` | English | 11 × 2 | 22 | 1.06 s (0.45–3.91) |
| 3 | `qwen2.5-1.5b-instruct-q4_k_m` | English | 11 × 2 | 22 | 0.25 s (0.11–0.54) |

`⏎` marks a newline inside an output; the byte-exact text is in
`evidence/measure-*.json` and `evidence/table-*.md`. `guard` is the verdict of the **real**
`TransformGuard` on that answer for that dictation.

#### 1. `qwen3-8b-q4_k_m`, Polish — the shipped route after the captain's decision

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| pl-imperative | formal | old | 1.2s | ok | `Wyślij raport do klienta dzisiaj.` |
| pl-imperative | formal | new | 2.43s | ok | `Wyślij raport do klienta dzisiaj` |
| pl-question | formal | old | 1.09s | ok | `Czy możemy przenieść spotkanie na przyszły tydzień?` |
| pl-question | formal | new | 1.06s | ok | `Czy możemy przenieść spotkanie na przyszły tydzień` |
| pl-already-formal | formal | old | 1.64s | ok | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-already-formal | formal | new | 1.67s | ok | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-run-on | casual | old | 2.23s | ok | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-run-on | casual | new | 3.52s | ok | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-numbers | casual | old | 1.21s | ok | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-numbers | casual | new | 1.35s | ok | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-filler | neutral | old | 1.72s | ok | `yyy no więc w sumie chciałem powiedzieć, że wdrożenie jest zrobione` |
| pl-filler | neutral | new | 3.06s | ok | `yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione` |
| pl-plan-run-on | formal | old | 1.64s | ok | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-plan-run-on | formal | new | 1.67s | ok | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-real-odzyskalem-formal | formal | old | 2.78s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-formal | formal | new | 2.82s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | old | 2.79s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | new | 2.8s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | old | 2.71s | ok | `Dobra wiadomość to to, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | new | 2.8s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-ziameczku-formal | formal | old | 2.57s | ok | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że przekląłeś po całości.` |
| pl-real-ziameczku-formal | formal | new | 2.66s | ok | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | old | 2.56s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | new | 2.59s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-neutral | neutral | old | 2.52s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że przeszkodziłeś po całości.` |
| pl-real-ziameczku-neutral | neutral | new | 2.53s | ok | `Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-jeszcze-raz-formal | formal | old | 1.85s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-formal | formal | new | 1.87s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | old | 1.86s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | new | 1.87s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | old | 1.88s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | new | 1.9s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-zarzucic-formal | formal | old | 0.92s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-formal | formal | new | 0.92s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | old | 0.9s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | new | 0.92s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | old | 0.9s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | new | 0.91s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-nagrywam-formal | formal | old | 1.28s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-formal | formal | new | 1.28s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-casual | casual | old | 1.06s | ok | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-casual | casual | new | 1.11s | ok | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-neutral | neutral | old | 1.29s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-neutral | neutral | new | 1.29s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-podgrywam-formal | formal | old | 1.73s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-formal | formal | new | 1.74s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-casual | casual | old | 1.36s | ok | `Teraz graję w polskim, teraz nagrywam w polskim.` |
| pl-real-podgrywam-casual | casual | new | 1.52s | ok | `Teraz podgrywam w polskim, teraz nagrywam w polskim.` |
| pl-real-podgrywam-neutral | neutral | old | 1.77s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-neutral | neutral | new | 1.74s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-probuje-formal | formal | old | 0.65s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-formal | formal | new | 0.67s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | old | 0.65s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | new | 0.68s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | old | 0.74s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | new | 0.7s | ok | `Teraz próbuję coś nagrać.` |

#### 2. `qwen3-8b-q4_k_m`, English — the same route, the other language

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| en-imperative | formal | old | 0.9s | ok | `Please send the report tomorrow.` |
| en-imperative | formal | new | 3.91s | ok | `Send the report tomorrow.` |
| en-question | formal | old | 0.99s | ok | `May we reschedule the meeting to next week?` |
| en-question | formal | new | 0.66s | ok | `Can we move the meeting to next week?` |
| en-already-formal | formal | old | 0.96s | ok | `Please send the report to the client today and copy me on the reply.` |
| en-already-formal | formal | new | 1.03s | ok | `Please send the report to the client today, and copy me on the reply.` |
| en-run-on | casual | old | 1.34s | ok | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-run-on | casual | new | 2.75s | ok | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-numbers | casual | old | 1.08s | ok | `the invoice number is 423 and the amount is three thousand zloty` |
| en-numbers | casual | new | 1.1s | ok | `the invoice number is 423 and the amount is three thousand zloty` |
| en-filler | neutral | old | 1.25s | ok | `um so basically I wanted to say that the deployment is done` |
| en-filler | neutral | new | 2.65s | ok | `um so basically I wanted to say that the deployment is done` |
| en-plan-run-on | formal | old | 1.12s | ok | `The plan is first to test, then to deploy, and then to monitor the logs.` |
| en-plan-run-on | formal | new | 1.14s | ok | `The plan is first to test, then to deploy, and then to watch the logs.` |
| en-real-problem-polish | formal | old | 0.56s | ok | `The problem is only with polish.` |
| en-real-problem-polish | formal | new | 0.56s | ok | `The problem is only with polish.` |
| en-real-keyboard | formal | old | 0.87s | ok | `Keyboard simulation is functioning intermittently. It is not consistently operational.` |
| en-real-keyboard | formal | new | 0.99s | ok | `Keyboard simulation is working from time to time. It is not always working.` |
| en-real-dispatch | casual | old | 0.45s | ok | `dispatch prod after you finish` |
| en-real-dispatch | casual | new | 0.46s | ok | `dispatch prod after you finish` |
| en-real-pauses | formal | old | 1.89s | ok | `Also add a feature to ignore pauses. Basically, it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |
| en-real-pauses | formal | new | 1.97s | ok | `Also add a feature to ignore pauses. Basically, how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |

#### 3. `qwen2.5-1.5b-instruct-q4_k_m`, English — today's shipped English path

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| en-imperative | formal | old | 0.16s | ok | `send the report tomorrow` |
| en-imperative | formal | new | 0.42s | ok | `send the report tomorrow` |
| en-question | formal | old | 0.16s | ok | `can we schedule the meeting for next week?` |
| en-question | formal | new | 0.16s | ok | `Can we schedule the meeting for next week?` |
| en-already-formal | formal | old | 0.24s | ok | `Please transmit the report to the client immediately, and forward a copy to me.` |
| en-already-formal | formal | new | 0.25s | ok | `Please send the report to the client today, and copy me on the reply.` |
| en-run-on | casual | old | 0.29s | ok | `I reckon we should just ship it on Friday if nothing breaks.` |
| en-run-on | casual | new | 0.54s | ok | `I reckon we should just ship it on Friday if nothing breaks.` |
| en-numbers | casual | old | 0.29s | ok | `The invoice number is 423, and the amount is three thousand zloty.` |
| en-numbers | casual | new | 0.25s | ok | `invoice number is 423, amount is three thousand zloty.` |
| en-filler | neutral | old | 0.27s | ok | `um so basically I wanted to say that the deployment is done` |
| en-filler | neutral | new | 0.47s | ok | `basically, the deployment is done` |
| en-plan-run-on | formal | old | 0.27s | ok | `OK, the plan is to first test, then deploy, and finally watch the logs.` |
| en-plan-run-on | formal | new | 0.32s | ok | `First, we will test. Subsequently, we will deploy, and finally, we will monitor the logs.` |
| en-real-problem-polish | formal | old | 0.16s | ok | `The issue pertains solely to the polish.` |
| en-real-problem-polish | formal | new | 0.14s | ok | `The problem lies solely with polish.` |
| en-real-keyboard | formal | old | 0.22s | ok | `The keyboard simulation function operates intermittently. It does not consistently function.` |
| en-real-keyboard | formal | new | 0.2s | ok | `Keyboard simulation is occasionally functioning. It is not consistently operational.` |
| en-real-dispatch | casual | old | 0.12s | ok | `dispatch prod after you're done` |
| en-real-dispatch | casual | new | 0.11s | ok | `dispatch prod after you finish` |
| en-real-pauses | formal | old | 0.45s | ok | `Also add a feature to ignore pauses. Essentially, this will create a sentence without a sense due to my long pauses. The pauses need to be ignored.` |
| en-real-pauses | formal | new | 0.45s | ok | `Also add a feature to ignore pauses. Essentially, the system creates a sentence without a sense due to my long pauses. The pauses need to be ignored.` |

#### The mechanical screen — every answer, not a skim

`evidence/analyze-*.txt` runs each pair through the app's own `LanguageDetector`
(`evidence/lang-verdict.swift`) and compares the case-folded words. The comparison cannot tell a
register change from an invention — it is a screen, and it is here so that all 100 answers were
looked at by something other than a human skim.

| run | prompt | unchanged | guard rejects | answers with a word the dictation never had | answers missing a word the dictation had |
|---|---|---|---|---|---|
| 8B Polish (28) | old | 14 | 0 | 6 | 7 |
| 8B Polish (28) | **new** | **15** | **0** | **2** | **4** |
| 8B English (11) | old | 3 | 0 | 4 | 4 |
| 8B English (11) | **new** | **4** | **0** | **1** | **2** |
| 1.5B English (11) | old | 1 | 0 | 8 | 8 |
| 1.5B English (11) | new | 3 | 0 | 6 | 8 |

Two more checks over all 56 Polish answers: **no honourific the captain never used** (no
`Szanowni Państwo`, no `Pan`/`Pani` form — zero matches), and **no language flip** — the
detector's verdict stayed `polish` on every output, input and output alike. Every English answer
stayed `english`.

#### The guard, on this data

* **Zero of the 100 answers were rejected** — the frame/label/stub/flip class did not appear at
  all with the framing in place, so the guard never had to fire and there is no false positive on
  real dictation. That is a *measurement of 100 answers*, not a proof of absence.
* Fed the **historical** measured 1.5B failures — the added `"Sure,"`, the
  `"Sure, here's the rewritten text in a casual register:"` preamble, the `"Understood."` and
  `"Plan done."` collapses, the Polish `Oczywiście`/`Oto`/`Jasne` frames, the `Register:`/`Output:`
  labels, the language flips — the real guard catches every one, and leaves all six legitimate
  negatives alone (`evidence/resume-guard-cases.txt`, re-run at `9c36eae` this session,
  **ALL 19 CASES PASS**).
* And that is the limit: the **1.5B's content loss is invisible to it**. `en-filler` neutral on
  the 1.5B with the new prompt returned `basically, the deployment is done` — the input's
  `um so basically I wanted to say that` is gone, 13 words in, 5 out, above the stub floor, same
  language, no frame. The guard delivers it. Same for the dropped articles on `en-numbers`
  (`invoice number is 423, amount is …`). Subtle drift stays the prompt's and the model's job, as
  the report said it would be.

#### Verdict — is the new prompt equal-or-better on the 8B, in both languages?

**Yes, plainly so, and by every measure this run took.**

* **Polish (28 cases: the captain's own 7 dictations × 3 registers, plus 7 adversarial cases).**
  The new prompt is *more conservative*, which is exactly what the captain's complaint needs: it
  invents less (2 answers carry a word the dictation never had, against 6 with the old prompt) and
  loses less (4 against 7), and it leaves **15 of 28** dictations byte-identical instead of 14.
  Where the old prompt invented vocabulary the captain never said, the new one kept his words:
  `…że przekląłeś po całości` (old) → `…że żeś pieprzył po całości` (new, unchanged);
  `…że przeszkodziłeś po całości` (old, nonsense) → unchanged; `Dobra wiadomość to to, że …` (old,
  broken Polish) → unchanged; `Teraz graję w języku polskim` (old, not a word) → unchanged. On his
  registers, formal and neutral tone now mostly only fix punctuation — the safe outcome, and the
  card's copy does not promise a visible difference in that case.
* **English (11 cases).** Same direction: 1 answer with a word the dictation never had, against 4;
  2 with a loss, against 4. The old prompt's rewrites were the driftier ones
  (`Keyboard simulation is functioning intermittently. It is not consistently operational.` against
  the new prompt's `Keyboard simulation is working from time to time. It is not always working.`;
  `The problem is only with polish.` kept verbatim by the new prompt, re-worded to
  `pertains solely to the polish` by the old). **Moving English tone to the 8B does not regress what
  the captain says works — it removes the 1.5B's re-writing habit.**
* **The cost is latency and RAM**, both already on the card: about 1.1–1.7 s per tone call on the
  8B against about 0.25 s on the 1.5B in the same harness (4–7×), and the 5.6 GB wired the Settings
  card states.
* **One incidental finding worth keeping:** the landed prompt is *not* byte-identical to the
  `fm-20260924-10` proposal, and the difference helps. With the proposal wording the 8B turned
  `yyy no więc …` into `yyy nie więc …` (inventing a word) on the neutral filler case; with the
  landed wording it kept `no` (`evidence/tone-ab-8b-polish-pinned.log` against
  `evidence/measure-8b-polish.json`). One sample at temperature 0.2, so an observation, not a
  distribution.

**What this does not change:** the 1.5B is still the weak link. If English tone were ever moved
back to it, the new prompt would need work — on this data it *loses content* on the 1.5B in a case
where the old prompt kept it (`en-filler`).

#### What is left unverified in Gate 2

1. **One sample per case.** Temperature 0.2 means these outputs are draws, not distributions, and
   the counts are indicative. No repeat runs were made; `TransformDeterminismIntegrationTests`
   covers in-app repeatability and passed in the suite.
2. **Polish register control is still thin evidence** — 7 real dictations, 4 of them one clause
   long, where any register change is noise-level. The run-ons (the `ziameczku` and `odzyskalem`
   dictations) are the informative ones and they favour the new prompt.
3. **Register quality is judged by a mechanical screen plus my reading**, not by the captain.
   Nothing here replaces his ear on his own dictations.
4. **No end-to-end run inside the app.** The measurement uses the app's exact prompts, sampling and
   chat template through `llama-server`, not the app's own process; the in-app path is covered by
   the suite (`SameLanguageTransformIntegrationTests`, `TransformDeterminismIntegrationTests`),
   which passed.

## FIX PASS — 2026-09-25

Fix pass over the review findings on `fm/tone-output` @ `9c36eae`, same worktree, no merge, no push, no
tag, no branch deleted, no model moved or copied, primary checkout untouched. The prompt wording and the
routing are **unchanged** (that was the condition for the measurement's verdict to stand); everything
below is the guard's false positives, the warm-up, the report plumbing, copy, tests and the measurement
the verification run left as an exact-prompt gap.

### A — the three suite failures, fixed test-side

1. **`TransformServiceTests.swift:158` (the blocker).** The decision-table rows paired the 8-word English
   fixture with the one-word answer `"rewritten"`, so the guard's stub rule (armed at eight input words,
   floor 2) fired and the raw transcript was asserted against `"rewritten"`. The rows are about the
   decision table, not about rejection, so the fixture is what changed: each row now carries its own
   answer — a same-language rewrite the guard accepts — and the row asserts *that* answer was pasted **and
   that no rejection was recorded**. The guard was not weakened.
2. **`TransformServiceTests.swift:238` (six times).** The assertion pinned the sentence
   `"never translate, not even one word"` in lowercase; the landed prompt says `Never translate` because
   it opens a sentence there. It is rewritten to the invariant behind the sentence: the prompt forbids
   translation (`never translate`, case-insensitively — so the rule survives a re-worded sentence) and
   pins the outgoing language to the dictated one (`<Language> in, <Language> out`).
3. **`TranscriptionLanguageGateTests.swift:124`.** It still expected the bare transcript; part B sends the
   framed turn. It now asserts the **intended** behaviour: each dictation is handed over inside
   `<<<TRANSCRIPT … TRANSCRIPT>>>`, and each turn pins its own language and not the other one.

### B — the guard's false positives

The defect class: a rewrite that legitimately keeps the user's own opening was thrown away and the raw
transcript delivered with a notice blaming the model.

| # | finding | fix |
|---|---|---|
| 4 | `"here is"`, `"here's"`, `"i've"` are ordinary *dictated* openings | the frame rule now needs **the model to have added** it: an answer only rejects when it opens with a frame the **dictation did not open with** |
| 5 | `announcingPhrases`/`labelPrefixes` fired on text the input already carried | both are skipped when the dictation itself contains the phrase, or carries the label line |
| 6 | the label/announcement phrases were English-only | the Polish counterparts are added: `przepisany tekst`, `przepisana wersja`, `oto przepisany` |

The one interpretation made here, stated rather than buried: "absent from the input" is implemented as
**absent from the input's own opening** for frames. A frame in the *middle* of a dictation does not
excuse an answer that opens with one — `I'm not sure, maybe we ship Friday` answered with
`Sure, we ship Friday.` is the measured failure and is still caught — and every false positive the review
named (`Here is the summary, …`, `I've already deployed …`) is an opening. The wider reading would have
traded a real catch for nothing the review asked for.

**The measured catch survives** (`TestChatCollapse` / `testFrameTheModelAdded_isStillRejected`): a
dictation without `Understood.` answered with `Understood.` still rejects, as does an answer that opens
with a frame the dictation only mentioned mid-sentence.

Pinned by tests (each fix, both directions) — `TransformGuardTests`:
`testFrameTheDictationOpenedWith_isDelivered`, `testFrameTheModelAdded_isStillRejected`,
`testLabelTheDictationAlreadyCarried_isDelivered`, `testLabelTheModelAdded_isStillRejected`,
`testPolishAnnouncementPhrases_areRejected`; standalone, against the compiled guard:
`evidence/fix-guard-false-positives.txt` (15/15) and the verification run's 19 cases re-run at this head
(`evidence/fix-guard-cases.txt`, 19/19).

### B — the two limits the review accepted as deferred (documented, not fixed)

* the stub floor counts **fillers** (`TransformGuard.stubMinimumKeptFraction`): a legit tone+clean-up that
  strips heavy stutter can fall under 25 % and be rejected. Fixing it needs a language-specific filler
  list, which the guard deliberately does not carry — the limit is now written where the constant lives.
* the flip rule needs the **engine's language to agree with the detector's**
  (`TransformGuard.flipMinimumInputWords`): mixed or technical dictation the engine called `pl` and the
  detector calls `en` cannot be caught at all, because the rule's first condition fails before the answer
  is looked at. Same treatment.

### C — warm-up and the claim it made

* `TransformRuntime.warmUpIfEnabled()` no longer loads `models.defaultModel`. It resolves the policy from
  the switches (`TransformRuntime.warmUpPolicy(toneEnabled:toneMode:)`) and asks the same
  `models.model(for:)` the dictation path asks, so **with tone on and the 8B installed it warms the 8B**
  (both languages) instead of warming a model nothing then uses; clean-up alone still warms the shipped
  floor. Pinned in `TransformBackendTests.testPolishPrefersTheEightBeeAndUsesTheShippedModelWithoutIt`.
* `TransformRuntime.swift:219` — the swap now logs "for a different model"; the comment says a job change
  swaps it too.
* `Readme.md:461-462` — the promise that the cold load is hidden behind your own speech now says which
  model is warmed: the one the current switches imply.

### D — the rejection is visible

`TransformOutcome.guardRejection` was set and never read, and `DictationReport` had no such field, so the
report printed the tone policy as if it had run. It is now plumbed end to end:
`TransformService` → `IndicatorWindow` → `DictationReport.guardRejection`/`guardNotice` →
`transformLabel` ("… — answer rejected, transcript kept") and the notice line beside the last dictation's
language and raw-to-final text (`ContentView`). Pinned by
`DictationInjectionTests.testTheDictationReportCarriesAGuardedRejection` (through `IndicatorViewModel`:
the transcript is what is injected, the report carries the rejection and the notice, and the label is not
the policy summary) and by `TransformServiceTests.testGuardedRejection_keepsTheTranscriptAndRecordsTheReason`.

### E — copy and docs that contradicted the code

* `Settings.swift:271` — the missing-model notice no longer claims tone, English clean-up and Polish
  clean-up all wait for the shipped model: it names the floor and the single job with no fallback
  (English clean-up always; every tone rewrite until the 8B is installed).
* `Settings.swift:1673` — the model-list caption is now job-based (tone on the larger model in both
  languages when installed, Polish clean-up too, English clean-up always on the shipped floor) instead of
  the old "what Polish prefers", which contradicted the card 10 lines below it.
* `TransformModelManager.swift` — the class doc names `model(for:)` (not `model(forSpokenLanguage:)`) as
  what the runtime asks; `modelID(forSpokenLanguage:)` says it is test-facing, not read on the transform
  path; `model(forSpokenLanguage:)` is documented as the clean-up-only preference.
* tests that pinned wording instead of behaviour, rewritten to the invariant: `SettingsExposureTests`
  (:99, :123, :148 — the card's tone routing is now asserted as the resolution of `model(for:)`),
  `TransformBackendTests:52` (the exact user-turn sentence is gone; the `<<<TRANSCRIPT` framing stays),
  `TransformBackendTests:204` (the message no longer says "English clean-up" while exercising an English
  *tone* policy).

### The environment failure found while proving A — and its fix

The first suite run of this pass (`** TEST FAILED **`, 378/2/54) failed **two** tests in
`TranscriptionLanguageGateTests`, neither of them the one the review named, with `caught error:
"ggml-tiny.en.bin understands English only, but this dictation is Polish…"`. The cause is a
**pre-existing cross-class leak**: `TranscriptionService.speechLanguageConflict` falls back to the
*machine's* selected model (`AppPreferences.shared.selectedWhisperModelPath`) when the engine was handed
no explicit selection, and another class in the same process can leave an `.en` path there
(`WhisperModelManager.ensureDefaultModelPresent` points a missing selection at the bundled
`ggml-tiny.en.bin`; `ModelStorageTests` also writes one). Those two tests hand a stub engine Polish text,
never plant that preference, and so were asserting whatever the process happened to have stored —
the exact thing `PreferenceIsolationTests` says must not happen ("the model a test transcribes with is an
argument, never a preference").

Fixed at the **test double**, not in the product and not by weakening an assertion: `StubLanguageWhisperEngine`
now takes a `multilingual:` argument (default `nil`, i.e. today's behaviour) and the two tests whose premise
is "a multilingual engine heard this dictation" declare it, so the gate cannot consult the ambient
selection for them. The tests that pin the refusal keep `nil`, so the model path they hand the service
stays the whole evidence. This is the only change in this pass that is outside the findings list, and it is
a test-isolation repair, not a scope change.

### F — the exact compiled prompt, measured

**What this closes, precisely.** The verification run's Gate-2 tables *were* produced with the exact
compiled prompt: `evidence/measure-*.json` comes from `tone-measure.py`, which composes
`TransformService.systemPrompt`/`userPrompt` byte for byte, and `evidence/resume-prompt-fidelity.txt`
proves that reconstruction against the prompt the compiled service printed. The pinned `tone-ab.py`
(which lists all three register definitions and omits the trailing `Output ONLY the final …` line) was
run *beside* it, "for the record". What the record did **not** carry is (a) the case-by-case **delta**
between the two prompt variants, and (b) the same answers re-classified by the **fixed** guard. This
pass re-ran the measurement at the fixed head, re-classified every answer with the guard and detector
rebuilt from the fixed sources, and adds the delta — plus a rerun baseline, so the wording delta can be
read against the noise of rerunning the *identical* prompt.

**Method.** `llama-server` (Homebrew, 0.3.0) with the app's exact sampling: temperature 0.2, top-k 40,
top-p 0.95, min-p 0.05, `chat_template_kwargs.enable_thinking = false`. Two runs, one per language,
each with its own bounded server; `pgrep llama-server` is empty after both. The 8B's path is read, never
copied or moved. The prompt for every request is the reconstruction proven byte-equal to the compiled
service (`evidence/fix-prompt-fidelity.txt`; the prompt block is byte-identical to the verification
run's `service-checks.txt`, i.e. this pass changed no wording). Guard verdicts and detector verdicts
come from the real sources at head `877d19e`, compiled standalone
(`evidence/fix-guard-cases.txt`, 19/19; the fresh answers were then fed through the same binary).

| run | model | language | cases × prompts | answers | latency median (min–max) |
|---|---|---|---|---|---|
| 1 | `qwen3-8b-q4_k_m` | Polish (7 real dictations × 3 registers + 7 adversarial) | 28 × 2 | 56 | 1.76 s (0.67–3.79) |
| 2 | `qwen3-8b-q4_k_m` | English | 11 × 2 | 22 | 1.08 s (0.48–2.76) |

**Headline: 0 of the 78 answers were rejected by the fixed guard, and no answer flipped language.** The
mechanical screen over the fresh exact-prompt run reproduces the verification run's numbers:

| model / language | prompt | unchanged | has a word the dictation never had | missing a word |
|---|---|---|---|---|
| 8B Polish (28) | old | 13 | 7 | 8 |
| 8B Polish (28) | **new (exact)** | **15** | **2** | **4** |
| 8B English (11) | old | 3 | 4 | 4 |
| 8B English (11) | **new (exact)** | **4** | **1** | **2** |

(the verification run recorded 15 / 2 / 4 for Polish and 4 / 1 / 2 for English with the same prompt: the
draws agree in aggregate; the `old` column's unchanged count drifts by one case and four of its 28 outputs differ verbatim, which is the rerun noise measured below.)

**The delta against the harness variant** — the number the fix pass was asked for. The harness variant
differs from the landed wording on **8 of 28 Polish cases and 2 of 11 English cases**, while rerunning
the *identical* prompt differs on 1 of 28 and 0 of 11:

| | exact `new` vs harness-variant `new` | exact `new` vs previous exact `new` (identical prompt, rerun) |
|---|---|---|
| Polish, 28 answers | 20 identical, **8 differ** | 27 identical, 1 differs |
| English, 11 answers | 9 identical, **2 differ** | 11 identical, 0 differ |

So the two wordings are **not interchangeable** — the delta is several times the noise — and where they
differ, the landed wording is the more conservative of the two on the captain's own dictations:

* `pl-filler` (neutral, his own run-on): harness variant invents a word — `yyy **nie** więc …` where he
  said `yyy **no** więc …` — and collapses his repeated `że`. The landed wording returns his words
  (`yyy no więc … że że wdrożenie …`).
* `pl-plan-run-on` (formal): the harness variant expands it
  (`Zatem plan jest taki: najpierw przeprowadzamy testy, następnie wdrażamy, a potem analizujemy logi.`);
  the landed wording keeps his phrasing (`Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.`).
* `pl-real-odzyskalem` (formal): harness `Dobra wiadomość to fakt, że … Udało mi się **stworzyć** fork`;
  landed `Dobra wiadomość jest taka, że … Udało mi się **zrobić** fork` (his word).
* `pl-real-ziameczku` (formal): harness reorders his last clause (`…że po całości pieprzyłeś`); landed
  keeps `…że żeś pieprzył po całości`.
* `pl-real-podgrywam` (casual): harness expands `w polskim` → `w języku polskim`; landed keeps `w polskim`.
* `en-real-pauses`: the **old** prompt and the harness variant both drop his `how` (`Basically, it creates
  a sentence…`); the landed wording keeps it (`Basically, how it creates a sentence…`).
* `en-real-keyboard`: harness rewrites it more idiomatically
  (`Keyboard simulation is functioning intermittently. It is not consistently operational.`); landed keeps
  his plainer words. Both are legitimate; neither invents anything.

Two rows where the landed wording is *coarser* rather than safer, stated rather than smoothed over: on
`pl-question`, `pl-imperative` and `pl-numbers` it returned the dictation without the final `?`/`.,` that
the harness variant produced — tone-only asks for a register, not punctuation repair, and the clean-up
path is what restores punctuation, but the difference is real. And `pl-real-podgrywam` casual returns
`Teraz podgrywam w polskim` — his own odd phrase kept verbatim, which is the conservative outcome the
review asked for, not a correction.

**Guard verdicts.** Every answer in both delta columns is `ok` (`evidence/fix-table-8b-*.md`,
`evidence/fix-delta-8b-*.txt`); the fixed guard rejects nothing here, so the fix pass's narrowing cost no
catch on this data, and the harness variant would not have been rejected either. The catches are pinned
where a rejection is actually expected: `evidence/fix-guard-cases.txt` (the 19 measured failures, 19/19)
and `evidence/fix-guard-false-positives.txt` (the new directions, 15/15).

**The exact-prompt tables, verbatim.** Every answer in both columns below was fed through the fixed guard and the real detector; `guard` is that verdict.

#### 1. `qwen3-8b-q4_k_m`, Polish — the exact compiled prompt

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| pl-imperative | formal | old | 1.29s | ok | `Wyślij raport do klienta dzisiaj.` |
| pl-imperative | formal | new | 2.68s | ok | `Wyślij raport do klienta dzisiaj.` |
| pl-question | formal | old | 1.21s | ok | `Czy możemy przenieść spotkanie na przyszły tydzień?` |
| pl-question | formal | new | 1.18s | ok | `Czy możemy przenieść spotkanie na przyszły tydzień` |
| pl-already-formal | formal | old | 1.8s | ok | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-already-formal | formal | new | 1.81s | ok | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-run-on | casual | old | 2.36s | ok | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-run-on | casual | new | 3.79s | ok | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-numbers | casual | old | 1.3s | ok | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-numbers | casual | new | 1.41s | ok | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-filler | neutral | old | 1.77s | ok | `yyy no więc w sumie chciałem powiedzieć, że wdrożenie jest zrobione` |
| pl-filler | neutral | new | 3.21s | ok | `yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione` |
| pl-plan-run-on | formal | old | 1.7s | ok | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-plan-run-on | formal | new | 1.74s | ok | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-real-odzyskalem-formal | formal | old | 2.93s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-formal | formal | new | 2.97s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | old | 3.02s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | new | 3.06s | ok | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | old | 3.04s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | new | 3.02s | ok | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-ziameczku-formal | formal | old | 2.75s | ok | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że przekląłeś po całości.` |
| pl-real-ziameczku-formal | formal | new | 2.89s | ok | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | old | 2.83s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | new | 2.87s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-neutral | neutral | old | 2.71s | ok | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że przeszkodziłeś po całości.` |
| pl-real-ziameczku-neutral | neutral | new | 2.72s | ok | `Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-jeszcze-raz-formal | formal | old | 1.99s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-formal | formal | new | 2.0s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | old | 1.98s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | new | 1.99s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | old | 1.94s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | new | 1.98s | ok | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-zarzucic-formal | formal | old | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-formal | formal | new | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | old | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | new | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | old | 0.94s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | new | 0.96s | ok | `Mogę coś zarzucić za jej w tle.` |
| pl-real-nagrywam-formal | formal | old | 1.32s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-formal | formal | new | 1.32s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-casual | casual | old | 1.16s | ok | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-casual | casual | new | 1.11s | ok | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-neutral | neutral | old | 1.33s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-neutral | neutral | new | 1.33s | ok | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-podgrywam-formal | formal | old | 1.79s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-formal | formal | new | 1.81s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-casual | casual | old | 1.47s | ok | `Teraz podgrywam po polsku, teraz nagrywam po polsku.` |
| pl-real-podgrywam-casual | casual | new | 1.61s | ok | `Teraz podgrywam w polskim, teraz nagrywam w polskim.` |
| pl-real-podgrywam-neutral | neutral | old | 1.56s | ok | `Teraz gram w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-neutral | neutral | new | 1.84s | ok | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-probuje-formal | formal | old | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-formal | formal | new | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | old | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | new | 0.69s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | old | 0.67s | ok | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | new | 0.69s | ok | `Teraz próbuję coś nagrać.` |

#### 2. `qwen3-8b-q4_k_m`, English — the exact compiled prompt

| case | register | prompt | latency | guard | output |
|---|---|---|---|---|---|
| en-imperative | formal | old | 0.78s | ok | `Please send the report tomorrow.` |
| en-imperative | formal | new | 2.29s | ok | `Send the report tomorrow.` |
| en-question | formal | old | 0.74s | ok | `May we reschedule the meeting to next week?` |
| en-question | formal | new | 0.68s | ok | `Can we move the meeting to next week?` |
| en-already-formal | formal | old | 0.99s | ok | `Please send the report to the client today and copy me on the reply.` |
| en-already-formal | formal | new | 1.05s | ok | `Please send the report to the client today, and copy me on the reply.` |
| en-run-on | casual | old | 1.41s | ok | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-run-on | casual | new | 2.76s | ok | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-numbers | casual | old | 1.18s | ok | `the invoice number is 423 and the amount is three thousand zloty` |
| en-numbers | casual | new | 1.11s | ok | `the invoice number is 423 and the amount is three thousand zloty` |
| en-filler | neutral | old | 1.26s | ok | `um so basically I wanted to say that the deployment is done` |
| en-filler | neutral | new | 2.65s | ok | `um so basically I wanted to say that the deployment is done` |
| en-plan-run-on | formal | old | 1.19s | ok | `The plan is first to test, then to deploy, and then to monitor the logs.` |
| en-plan-run-on | formal | new | 1.2s | ok | `The plan is first to test, then to deploy, and then to watch the logs.` |
| en-real-problem-polish | formal | old | 0.57s | ok | `The problem is only with polish.` |
| en-real-problem-polish | formal | new | 0.58s | ok | `The problem is only with polish.` |
| en-real-keyboard | formal | old | 0.88s | ok | `Keyboard simulation is working intermittently. It is not consistently functioning.` |
| en-real-keyboard | formal | new | 1.0s | ok | `Keyboard simulation is working from time to time. It is not always working.` |
| en-real-dispatch | casual | old | 0.48s | ok | `dispatch prod after you finish` |
| en-real-dispatch | casual | new | 0.48s | ok | `dispatch prod after you finish` |
| en-real-pauses | formal | old | 1.95s | ok | `Also add a feature to ignore pauses. Basically, it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |
| en-real-pauses | formal | new | 1.98s | ok | `Also add a feature to ignore pauses. Basically, how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |

(`⏎` would mark a newline inside an output; this run produced no multi-line answer, so every output is a single line. Latency is the wall time of the single completion call and excludes the model load.)

### The case-by-case delta against the harness variant (`tone-ab.py`, its `v1` = new prompt at 0.2)

`same?` compares the exact compiled prompt's answer with the harness variant's answer for the same case. The last column is the previous run of the *identical* exact prompt, i.e. the noise baseline.

#### Polish


| case | register | exact `new` | harness-variant `new` | guard (exact / harness) | same? | previous exact `new` (rerun noise) |
|---|---|---|---|---|---|---|
| pl-imperative | formal | `Wyślij raport do klienta dzisiaj.` | `Wyślij raport do klienta dzisiaj.` | ok / ok | yes | `Wyślij raport do klienta dzisiaj` |
| pl-question | formal | `Czy możemy przenieść spotkanie na przyszły tydzień` | `Czy możemy przenieść spotkanie na przyszły tydzień?` | ok / ok | **no** | `Czy możemy przenieść spotkanie na przyszły tydzień` |
| pl-already-formal | formal | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` | ok / ok | yes | `Proszę o wysłanie raportu do klienta jeszcze dziś oraz o przesłanie mi kopii odpowiedzi.` |
| pl-run-on | casual | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` | ok / ok | yes | `no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje` |
| pl-numbers | casual | `numer faktury to 423 a kwota to trzy tysiące złotych` | `numer faktury to 423, a kwota to trzy tysiące złotych` | ok / ok | **no** | `numer faktury to 423 a kwota to trzy tysiące złotych` |
| pl-filler | neutral | `yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione` | `yyy nie więc w sumie chciałem powiedzieć, że wdrożenie jest zrobione` | ok / ok | **no** | `yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione` |
| pl-plan-run-on | formal | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` | `Zatem plan jest taki: najpierw przeprowadzamy testy, następnie wdrażamy, a potem analizujemy logi.` | ok / ok | **no** | `Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.` |
| pl-real-odzyskalem-formal | formal | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` | `Dobra wiadomość to fakt, że odzyskałem swój polski. Udało mi się stworzyć fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` | ok / ok | **no** | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-casual | casual | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` | ok / ok | yes | `Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-odzyskalem-neutral | neutral | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` | ok / ok | yes | `Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.` |
| pl-real-ziameczku-formal | formal | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że po całości pieprzyłeś.` | ok / ok | **no** | `Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-casual | casual | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` | ok / ok | yes | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-ziameczku-neutral | neutral | `Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` | `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` | ok / ok | **no** | `Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.` |
| pl-real-jeszcze-raz-formal | formal | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` | ok / ok | yes | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-casual | casual | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` | ok / ok | yes | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-jeszcze-raz-neutral | neutral | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` | ok / ok | yes | `Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.` |
| pl-real-zarzucic-formal | formal | `Mogę coś zarzucić za jej w tle.` | `Mogę coś zarzucić za jej w tle.` | ok / ok | yes | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-casual | casual | `Mogę coś zarzucić za jej w tle.` | `Mogę coś zarzucić za jej w tle.` | ok / ok | yes | `Mogę coś zarzucić za jej w tle.` |
| pl-real-zarzucic-neutral | neutral | `Mogę coś zarzucić za jej w tle.` | `Mogę coś zarzucić za jej w tle.` | ok / ok | yes | `Mogę coś zarzucić za jej w tle.` |
| pl-real-nagrywam-formal | formal | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` | ok / ok | yes | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-nagrywam-casual | casual | `Teraz nagrywam po polsku, sprawdzam jak to działa.` | `Teraz nagrywam po polsku, sprawdzam jak to działa.` | ok / ok | yes | `Teraz nagrywam po polsku, sprawdzam jak to działa.` |
| pl-real-nagrywam-neutral | neutral | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` | ok / ok | yes | `Teraz nagrywam w języku polskim, sprawdzam, jak to działa.` |
| pl-real-podgrywam-formal | formal | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` | ok / ok | yes | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-podgrywam-casual | casual | `Teraz podgrywam w polskim, teraz nagrywam w polskim.` | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` | ok / ok | **no** | `Teraz podgrywam w polskim, teraz nagrywam w polskim.` |
| pl-real-podgrywam-neutral | neutral | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` | ok / ok | yes | `Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.` |
| pl-real-probuje-formal | formal | `Teraz próbuję coś nagrać.` | `Teraz próbuję coś nagrać.` | ok / ok | yes | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-casual | casual | `Teraz próbuję coś nagrać.` | `Teraz próbuję coś nagrać.` | ok / ok | yes | `Teraz próbuję coś nagrać.` |
| pl-real-probuje-neutral | neutral | `Teraz próbuję coś nagrać.` | `Teraz próbuję coś nagrać.` | ok / ok | yes | `Teraz próbuję coś nagrać.` |

* exact `new` vs harness-variant `new`: **20/28 identical**, 8 differ
* exact `new` vs previous exact `new` (identical prompt, rerun): **27/28 identical**, 1 differ
* exact `old` vs previous exact `old` (identical prompt, rerun): 4 differ
* guard on the harness-variant answers: 0 rejections 
* guard on the exact-prompt answers: see `fix-table-8b-*.md`

#### English


| case | register | exact `new` | harness-variant `new` | guard (exact / harness) | same? | previous exact `new` (rerun noise) |
|---|---|---|---|---|---|---|
| en-imperative | formal | `Send the report tomorrow.` | `Send the report tomorrow.` | ok / ok | yes | `Send the report tomorrow.` |
| en-question | formal | `Can we move the meeting to next week?` | `Can we move the meeting to next week?` | ok / ok | yes | `Can we move the meeting to next week?` |
| en-already-formal | formal | `Please send the report to the client today, and copy me on the reply.` | `Please send the report to the client today, and copy me on the reply.` | ok / ok | yes | `Please send the report to the client today, and copy me on the reply.` |
| en-run-on | casual | `I think we should probably just ship it on Friday if nothing breaks.` | `I think we should probably just ship it on Friday if nothing breaks.` | ok / ok | yes | `I think we should probably just ship it on Friday if nothing breaks.` |
| en-numbers | casual | `the invoice number is 423 and the amount is three thousand zloty` | `the invoice number is 423 and the amount is three thousand zloty` | ok / ok | yes | `the invoice number is 423 and the amount is three thousand zloty` |
| en-filler | neutral | `um so basically I wanted to say that the deployment is done` | `um so basically I wanted to say that the deployment is done` | ok / ok | yes | `um so basically I wanted to say that the deployment is done` |
| en-plan-run-on | formal | `The plan is first to test, then to deploy, and then to watch the logs.` | `The plan is first to test, then to deploy, and then to watch the logs.` | ok / ok | yes | `The plan is first to test, then to deploy, and then to watch the logs.` |
| en-real-problem-polish | formal | `The problem is only with polish.` | `The problem is only with polish.` | ok / ok | yes | `The problem is only with polish.` |
| en-real-keyboard | formal | `Keyboard simulation is working from time to time. It is not always working.` | `Keyboard simulation is functioning intermittently. It is not consistently operational.` | ok / ok | **no** | `Keyboard simulation is working from time to time. It is not always working.` |
| en-real-dispatch | casual | `dispatch prod after you finish` | `dispatch prod after you finish` | ok / ok | yes | `dispatch prod after you finish` |
| en-real-pauses | formal | `Also add a feature to ignore pauses. Basically, how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` | `Also add a feature to ignore pauses. Basically, it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` | ok / ok | **no** | `Also add a feature to ignore pauses. Basically, how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.` |

* exact `new` vs harness-variant `new`: **9/11 identical**, 2 differ
* exact `new` vs previous exact `new` (identical prompt, rerun): **11/11 identical**, 0 differ
* exact `old` vs previous exact `old` (identical prompt, rerun): 1 differ
* guard on the harness-variant answers: 0 rejections 
* guard on the exact-prompt answers: see `fix-table-8b-*.md`

### What is left unverified or deferred

* one sample per case at temperature 0.2: the outputs are draws, not distributions;
* Polish register quality is judged mechanically plus by reading, not by the captain's ear;
* the two guard limits above (fillers in the stub floor, engine/detector agreement for the flip) stay
  documented and unfixed;
* no end-to-end run inside the app: the measurement uses the app's exact prompts, sampling and chat
  template through `llama-server`.
