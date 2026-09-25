# Task fm-20260924-11 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

> "Tone transcription is not working as intended. Probably it is a matter of a system prompt. Because all other
> things are working properly, the whole mechanism or pipeline is working. The only thing that is lacking is the
> correct output. So prepare a system prompt for a tone change."

Then, on the evidence produced before this brief: **"Both tasks A and B should be completed."**

**A** — run the tone transform on the 8B for **both** languages while it is installed.
**B** — adopt the tightened tone prompt **and** add a deterministic guard, so the failure he hit cannot reach the
transcript.

## What was measured before this brief (do not re-derive; extend it)

Full method and tables: `fleet/data/fm-20260924-10/tone-prompt.md`. Harness: `/tmp/tone-ab.py`, real weights via
`llama-server` with the app's sampling (temperature 0.2, top-k 40, top-p 0.95, min-p 0.05,
`chat_template_kwargs.enable_thinking = false`).

Seven adversarial cases (imperative, question, "already formal", run-on, numbers, filler) × three prompt variants:

- **The model is the dominant variable.** Every failure a user would notice on `qwen2.5-1.5b-instruct-q4_k_m` —
  an added `"Sure,"`, a preamble (`"Sure, here's the rewritten text in a casual register:"`), dropped articles
  (`"invoice number is 423, amount is…"`), an invented noun (`"the product"`), and at temperature 0 an outright
  `"Understood."` instead of a rewrite — **is absent on `qwen3-8b-q4_k_m` with the same prompt.**
- **Temperature 0 is worse than 0.2** on both models (the small one collapses into chat; the 8B becomes verbose).
  Keep 0.2.
- **The new prompt is equal-or-better than the current one on the 8B, not a win by itself on the 1.5B**
  (it introduced the preamble there). That is why A and B ship together: the prompt makes good output likelier,
  the 8B makes it possible, the guard makes the bad case impossible.
- **Casual and neutral legitimately return the text unchanged** when it is already in that register. The card's
  copy must not promise a visible difference in that case.

## Firstmate spec

### A — routing

1. A tone transform (`.tone` and `.cleanUpWithTone` policies) uses **`qwen3-8b-q4_k_m` when it is installed,
   regardless of the language**; `qwen2.5-1.5b-instruct-q4_k_m` otherwise. Clean-up alone keeps the language-based
   preference the cutover landed (Polish → 8B when installed, English → 1.5B), because grammar repair does not need
   the larger model.
2. Nothing is refused and nothing is substituted silently: the Settings card states, per job, which model will run
   and whether the 8B is present — extending the sentence the cutover already added.
3. The 10-minute idle unload and the record-start warm-up stay exactly as they are; the card keeps stating the RAM
   cost of the model in use (~5.6 GB wired for the 8B).

### B — prompt and guard

4. Replace the tone wording in `TransformService.systemPrompt` with the version in
   `fleet/data/fm-20260924-10/tone-prompt.md`: register defined by *what may change*, an explicit
   "you are not an assistant" rule, the must-not-change list (facts, speaker, order, completeness, language), and
   the output rules (no preamble/labels/markdown, keep line breaks, already-in-register ⇒ unchanged, fragment ⇒
   unchanged). Keep `/no_think` and the reasoning strip.
5. Frame the user turn instead of sending the transcript bare:
   `Rewrite this dictated text in a {TONE} register …` + `<<<TRANSCRIPT … TRANSCRIPT>>>`. Dictated text is often an
   imperative or a question, and an unframed turn makes the model obey or answer it.
6. **Guard, deterministic and tested.** A tone result is rejected and the raw transcript is delivered instead —
   with a visible notice, using the same reporting path the injection interruptions use — when it:
   - opens with an assistant frame or acknowledgement (`Sure`, `Certainly`, `Of course`, `Understood`, `Here is`,
     `Here's`, `I've`, `Oczywiście`, `Oto`, `Jasne`), or contains `rewritten text` / `rewritten version` /
     a `Register:`/`Output:` label line;
   - is a stub: the input carries a sentence but the output is a small fragment of it (threshold chosen from the
     measured cases, stated in the report);
   - **flips language**: the output contains no word of the language the input was written in while the input had
     content words (checked with the app's own `LanguageDetector`).
   The guard works on text alone — no model call, no second pass — so it cannot itself hallucinate. It must not fire
   on the legitimate cases: an already-in-register output equal to the input, a genuinely short dictation, a
   fragment, or a text mixing a technical term from another language.
7. Keep the honest limits visible in the report: the guard catches frames, stubs and language flips; it cannot
   catch subtle content drift (an article dropped, a noun invented). Those are the prompt's and the 8B's job.

## Verification

- Re-run the seven adversarial cases in **both languages** on the 8B with the new prompt and the framing, and quote
  input → output; state explicitly which of the measured 1.5B failures the guard would have caught, by feeding those
  exact strings through it.
- Prove the guard's negative cases too: already-in-register text unchanged, a two-word dictation, a fragment, and a
  mixed-language technical term — all delivered as-is, none flagged.
- Prove A by execution: with the 8B installed, an English tone transform runs on `qwen3-8b-q4_k_m`; with it renamed
  away, the same transform runs on the 1.5B and the card says so; clean-up alone on English still runs the 1.5B.
- `Scripts/dev-run.sh test` headless from a clean state, green, output at `/tmp/fm2411-suite.log`; bundle
  identity-signed afterwards (`certificate leaf`, never a bare `cdhash`).
- The Readme's tone and model-routing text updated to match; the card copy updated.

## Worktree isolation assertion

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone \
  -b fm/tone-output <delivery tip>
git -C <worktree> -c protocol.file.allow=always submodule update --init --recursive
```

Work in that worktree ONLY. Do not touch `Utils/KeyboardSimulator.swift` or the injection path in
`Indicator/IndicatorWindow.swift` (delivery safety landed there today).

## Delegation guard

You are a crew member. Do not spawn subagents. No push, no merge, no branch deletion. **Headless only:** never launch
the app, never `osascript`, never `screencapture`, never `Scripts/dev-run.sh` without a mode argument. `llama-server`
from Homebrew is available and is how the measurements above were taken.

## Definition of done

Committed branch; A and B both implemented; the measured tables for both languages; the guard's positive and negative
cases proven by tests, including the exact failure strings measured on the small model; the suite green; the card and
Readme matching the new behaviour; `fleet/data/fm-20260924-11/report.md` and a UTC-stamped `status.log` line; an honest
note of what the guard cannot catch and anything else left unverified.

## RESUME — 2026-09-25T07:22Z, same task, same branch, head `9c36eae`

The peak stop that ended the previous attempt is over and **the provider is off-peak now** (the peak-hours guard
reports `OFF-PEAK (chinese-public-holiday)`; next peak Mon 2026-09-28 01:00Z). Nothing about the branch changed in
between; the worktree is clean. Two gates were never executed, and they are the entire remaining work.

### Gate 1 — the full suite (allowed now)

```
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone
setsid Scripts/dev-run.sh test > /tmp/fm2411-suite.log 2>&1 &
# read /tmp/fm2411-suite.log until the final ** TEST SUCCEEDED ** / ** TEST FAILED ** line
```
`Scripts/dev-run.sh test` is the ONLY correct entry point (it keeps `ENABLE_DEBUG_DYLIB=NO`, removes a stale split
layout, signs with the identity, re-signs after the run). A bare `xcodebuild test` leaves the app ad-hoc-signed and
silently breaks the Accessibility grant. Report the real counts (passed / failed / skipped) from the log — the
delivery tip's suite was 420 total / 367 passed / 0 failed / 53 skipped, and this branch differs only by the transform
changes and the four edited test files, so expect a comparable shape.

### Gate 2 — the weight-backed measurement (allowed now)

The harness is `/tmp/tone-ab.py`, copied to `fleet/data/fm-20260924-11/evidence/tone-ab.py` (sha256 in the adjacent
`.sha256` file) so a `/tmp` loss cannot take it again. It A/Bs the old prompt (`TransformService.systemPrompt()` as it
composed before) against the new one over `llama-server` with the app's exact sampling: temperature 0.2, top-k 40,
top-p 0.95, min-p 0.05, no thinking.

Run it on **the 8B for both languages** — that is the shipped route after the captain's decision, so Polish and English
tone output must both be evidenced, verbatim. Then run **the 1.5B for English** as well: the captain says today's
English tone is good, and today's English runs on the 1.5B, so moving English tone to the 8B must be shown not to
regress it.

Model paths (do not copy, do not delete, do not move them; the two 8B paths are the same inode):
- `$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models/qwen3-8b-q4_k_m.gguf` (5,027,783,488 B)
- `$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models/qwen2.5-1.5b-instruct-q4_k_m.gguf` (986,048,768 B)

Report a verbatim table: case × language × model, the exact output text, plus latency and whether the guard would have
rejected the answer. Raw outputs go to `fleet/data/fm-20260924-11/evidence/`.

### Hard scope limits

**Do not merge, do not push, do not delete anything, do not move any model between roots.** Part A (one model serving
tone in both languages) is the captain's decided single route; the previous attempt's closing note — that part A should
be deleted and the transform run on the shipped model — was **withdrawn by the captain**: *"one model to govern them
all… a single route for tone transcription that is applicable to both Polish and English. If the current setup is in
place, no changes should be made."* The branch as landed is that setup. Change nothing else.

### Safety rules, learned the hard way (a crew that ignored them ended two sessions)

- Never `osascript`, never `screencapture`, never GUI automation, never launch the app directly.
- Never `pkill`/`killall` on anything you did not start — in particular not `omp`, not `OpenSuperWhisper`, not the
  terminal. A sibling crew's GUI automation sent SIGHUP to two whole sessions; that is the failure this rule exists for.
- The dev keychain **works** now: the stored password at `~/.opensuperwhisper-dev/keychain-password` unlocks it
  (verified: exit 0, 1 valid identity, a real signing test produced `certificate leaf = H"32266bcc…"`). Signing needs
  no hand unlock, and a failed unlock is **not** evidence that the password is wrong — report it instead.
- `llama-server` from Homebrew is available and is how these measurements are taken; give it a bounded lifetime and do
  not leave it resident (the app's idle-unload contract is 10 minutes).

## REVIEW FINDINGS — fix pass (dispatched after the verification run settles)

An independent read of `3dcde52..9c36eae` landed 2026-09-25T07:35Z. It **confirms the captain's requirement is met**
(the tone path has no language branch: `TransformModelManager.model(for:)` sends `.tone` and `.cleanUpWithTone` to one
model regardless of language, reached from `TransformService.swift:368`), and confirms **no dead code survives from
the withdrawn "run everything on the 1.5B" plan**. The findings below are what must change before this branch lands.
The review's one blocker is already expected to show up in the verification run's suite log —
`TransformServiceTests.swift:158` — so a red suite from that run is not new information.

### Must fix — the branch is not landable without these

1. **`TransformServiceTests.swift:158` (blocker, the suite fails).** The decision-table rows "tone on, English" and
   "tone and clean-up, English" pair the input *"Please send the report to the client today."* (8 letter-words, so the
   stub rule is armed with floor 2) with the fixture answer *"rewritten"* (1 word). The guard returns
   `.stub(wordsIn: 8, wordsOut: 1)`, `outcome.text` becomes the transcript, and the assertion fails. Give those rows a
   fixture answer the guard accepts, or a sub-8-word input, or assert the guarded passthrough **as the expected
   behaviour** for a row that is deliberately about rejection — whichever matches what the row is actually testing.
   Never weaken the guard to make a fixture pass.
2. **`TransformGuard.swift:54` (major — false rejection of good output).** `"here is"`, `"here's"` and `"i've"` are
   ordinary *dictated* openings, not assistant frames: a rewrite that legitimately keeps "Here is the summary, …" or
   "I've already deployed the backend …" is currently thrown away and the raw transcript delivered with a misleading
   notice. Fix it the precise way: **a frame only rejects when the frame was absent from the input** — the model added
   it. The measured catch must survive: input without "Understood." → answer "Understood." still rejects.
3. **`TransformGuard.swift:59` (minor, same class).** `announcingPhrases` (`"rewritten text"`, `"rewritten version"`)
   and the any-line `labelPrefixes` check fire even when the phrase or label was **already in the input**. Ignore
   anything that was already there; the `answer == input` early return only covers the unchanged case.
4. **`TransformRuntime.swift:142` (major — latency the captain would feel).** The record-start warm-up still loads
   `models.defaultModel`, but tone now runs on the 8B in both languages: with tone on and the 8B installed, the warm-up
   warms the wrong model and the first dictation then unloads it and pays the 8B's cold load anyway. Warm the model the
   current switches imply — resolve the policy from the switches and ask `models.model(for:)`. Then correct
   `Readme.md:461-462`, which currently promises this cold load is hidden (and `:462` describes the shipped model
   warming up).
5. **`TransformService.swift:276` (minor — but it is why "tone did nothing" is invisible).** `TransformOutcome.guardRejection`
   is set at `:342` and **never read**: `DictationReport` has no such field, so the report prints the tone policy as if
   it had been applied (`didRunModel: true`) and the guard's `notice` string — the only explanation the user could get
   for their own words being used instead — is dead. Plumb the rejection (and its notice) through `DictationReport` and
   the surface that already shows the last dictation's language and raw-to-final text. If that turns out to be more
   than a small change, delete the field and the false doc claim instead, and say so — but do not leave a silent
   fallback behind a comment that claims it is visible.

### Fix — cheap, and all of it contradicts what the user reads

6. `Settings.swift:271` — the copy says tone, English clean-up and Polish clean-up "all wait for this one" (the
   shipped model); with the 8B installed, only English clean-up waits. Say the shipped model is the floor and name the
   single job with no fallback. `Settings.swift:1673` — the model-list caption still describes the 8B as "what Polish
   prefers when it is installed" and never mentions tone, contradicting the card directly below it (`:292`). Use the
   same job-based wording in both places.
7. `TransformModelManager.swift:71` — the class doc says `model(forSpokenLanguage:)` "is what the runtime asks it
   for"; the runtime asks `model(for:)`. `:189` documents `model(forSpokenLanguage:)` with the old whole-product rule
   though it is now clean-up-only, and `:95` claims `modelID(forSpokenLanguage:)` is "read on the transform path"
   although only tests call it. `TransformRuntime.swift:219` — "unloaded the previous model for a language change"
   should say "for a different model" (job changes also swap it now).
8. **Tests that pin wording instead of behaviour** — the project rule is that these are rewritten to the invariant or
   deleted, never re-pinned: `SettingsExposureTests.swift:99` (`:123`, `:148`) pins card copy — assert the resolved
   model from `model(for:)` instead; `TransformBackendTests.swift:52` pins the user turn's exact sentence (keep the
   `<<<TRANSCRIPT` delimiter assertion, which *is* the invariant); `TransformBackendTests.swift:204` has an assertion
   message about English clean-up while exercising `.tone(language: .english, …)`; `TransformServiceTests.swift:171`
   loosened the language assertion to `prompt.contains(language.displayName)`, which the clean-up block satisfies on
   its own, so it no longer proves the tone prompt pins the outgoing language; `TransformServiceTests.swift:232-245`
   re-pins prompt sentences ("You are not an assistant", "never translate, not even one word", "first person stays
   first person", "/no_think") — assert the invariants (language pinned, translation forbidden, register named,
   must-not-change list present) instead.
9. `TransformGuard.swift` — one gap I found myself: the label and announcement phrases are **English-only**
   (`"register:"`, `"output:"`, `"rewritten text"`), while the frames list already carries Polish entries. Either add
   the Polish equivalents (`"przepisany tekst"`, `"oto przepisany"`, `"przepisana wersja"`) or state the gap where it
   is decided, next to the other documented limits.

### Deliberately deferred — record, do not fix

- **The stub floor counts fillers** (`TransformGuard.swift:69`): a legitimate tone+clean-up that strips heavy stutter
  could fall under 25% and be rejected. Fixing it properly needs a language-specific filler list, which the guard
  deliberately avoids; the guard's doc comment already owns its limits. Note the risk in the report instead.
- **The flip rule needs the engine's language to agree** (`TransformGuard.swift:180`): mixed or technical dictation
  (engine "pl", detector "en") cannot be caught. Same treatment — document, do not widen.

### After the fixes

Re-run the full suite on the fixed head (`/tmp/fm2412-tone-fix-suite.log`) and re-sign; re-validate the measurement
only if the **prompt wording changed** (it must not — this pass changes the guard, the warm-up, the docs and the
tests, never the prompt or the routing). The verification run's measurement evidence carries over otherwise.

## VERIFICATION RUN RESULT — 2026-09-25T07:52Z (Fm11Resume, head `9c36eae`)

Read `report.md` §`## RESUME RUN — 2026-09-25` for the tables; this is the summary the fix pass must act on.

**Suite: `** TEST FAILED **` — 426 executed / 369 passed / 3 failed / 54 skipped** (log
`/tmp/fm2411-suite.log`, copy in `evidence/resume-full-suite.log`; the delivery tip for comparison is 420/367/0/53).
All three failures are **test-side staleness**, not runtime behaviour:

1. `OpenSuperWhisperTests/TransformServiceTests.swift:158` — the guard-vs-fixture row already diagnosed above.
2. `OpenSuperWhisperTests/TransformServiceTests.swift:238`, six times (2 languages × 3 registers) —
   `XCTAssertTrue(system.contains("never translate, not even one word"), system)` while the landed prompt says
   `Never translate, …` (capital N at sentence start). A stale lowercase pin of a sentence — exactly the class the
   project rule says to rewrite to the invariant.
3. `OpenSuperWhisperTests/TranscriptionLanguageGateTests.swift:124` — expects the bare transcript but part B now sends
   the framed `<<<TRANSCRIPT …>>>` turn; that file was never updated by the branch. Update it to the **intended** new
   behaviour (the frame is part of the design) — assert the frame and the same-language guarantee, not the old shape.

**Measurement (Gate 2) — 3 runs, 100 answers, all verbatim, guard-classified with the real `TransformGuard` +
`LanguageDetector`: 0 rejections.** Sampling matched the app exactly (temp 0.2, top-k 40, top-p 0.95, min-p 0.05,
`enable_thinking=false`); each run had its own bounded `llama-server` and none was left resident.

| run | model | language | answers | latency median (min–max) |
|---|---|---|---|---|
| 1 | `qwen3-8b-q4_k_m` | Polish (7 real captain dictations × 3 registers + 7 adversarial) | 56 | 1.67 s (0.65–3.52) |
| 2 | `qwen3-8b-q4_k_m` | English | 22 | 1.06 s (0.45–3.91) |
| 3 | `qwen2.5-1.5b-instruct-q4_k_m` | English (today's shipped path) | 22 | 0.25 s (0.11–0.54) |

**Verdict: the new prompt is equal-or-better on the 8B in both languages.** Polish: 15/28 answers unchanged vs 14,
answers carrying an invented word 2 vs 6, answers missing a word 4 vs 7 — the old prompt's inventions on the captain's
own dictations are gone. English: 1 vs 4 invented, 2 vs 4 lost words. Moving English tone to the 8B does not regress
the 1.5B path (the 1.5B drifts far more and under the new prompt even deletes content, which the guard cannot see).
Price: 4–7× latency and the 5.6 GB wired the Settings card already states.

**Residual gap this fix pass must close (the crew named it honestly):** the harness `tone-ab.py` differs from the
landed prompt in two places — it defines all three registers instead of only the selected one, and it omits the
trailing `Output ONLY the final …` line. So the **exact compiled prompt is still unmeasured**. Re-run the measurement
feeding the harness the bytes the compiled `TransformService.systemPrompt` / `userPrompt` actually emit
(`evidence/resume-prompt-fidelity.txt` proves which bytes those are) for **both languages on the 8B**, re-classify
with the real guard, and report the delta against the harness-variant run above. The prompt wording itself must not
change in this pass; if it must, say so and re-measure everything.
