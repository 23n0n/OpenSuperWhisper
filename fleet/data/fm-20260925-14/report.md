# fm-20260925-14 — does a deliberate decoder prompt pair with the pause switch?

Branch `fm/pause-pairing`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pairing`, base `eaecd28` (the
delivery tip, which already holds the pause work). Headless throughout: no app launch, no `osascript`, no
`screencapture`, no bare `xcodebuild test`, no subagents, no model file touched; every run detached with
`subprocess.Popen(..., start_new_session=True)` and a log under `/tmp/fm2414-*`.

**STATUS: refused, with evidence. Nothing landed: the branch is still `eaecd28`, no default is flipped, no decoder
prompt ships.**

The pairing does not pass the brief's criterion, and the reason is measurable rather than a matter of taste: with
the switch on, the **English control is never word-identical to the switch-off/none control** — not with any of the
six prompts measured, and not without a prompt either. The best any prompt achieves is a two-word difference
(`how` → `now`, `sentence` → `sentences`), and that difference is the **switch's own audio half**, not the prompt:
it is present in the arm that sends *no prompt at all*, and the prompt's contribution is exactly the other five
invented words. So a prompt cannot fix it, however deliberate it is.

Everything below is measured on his three recordings, through `transcribeAudioDetailed` — the app's own decode
path — with his `ggml-large-v3-turbo`, his settings and the VAD the app ships.

## 1. The question, and the criterion it has to meet

The pause fix is landed with its switch **off** because with the decoder prompt this app sent — none — the switch
on invented a fragment in the English control at every cap tried (`fleet/data/fm-20260924-12/report.md`). The
captain chose **both** halves of "write better prompt than…", so this task is the missing half: pair the switch
with a deliberate decoder prompt, and flip the two defaults **only if**, on his own recordings, through the app's
own decode path, **the English control stays clean (no invented words versus the switch-off/none control) and the
Polish win survives** (`pl-1` gains its sentence boundary; `pl-2` recovers `Open Super Whisper` and `Dodałem`).
Anything short of both is a refusal, and a refusal reported cleanly is a good outcome.

Not re-derived here: the two numbers the pause switch ships with (threshold 0.6 s, cap 0.8 s), the sweep that chose
them, and the four-prompt table of `fm-20260924-12`. This report adds the pairing measurement those tables could not
give: the arms cross **both** languages, and every arm is diffed against the control word by word.

## 2. Method

`OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift` (preserved at
`evidence/WhisperPauseBoundaryPairingTests.swift`). Opt-in twice over — `OSW_TEST_CAPTAIN_RECORDINGS` and a
multilingual model; with either missing the cases skip, which is the state CI runs in. The run:

```
Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests
# OSW_TEST_MULTILINGUAL_MODEL=…/ggml-large-v3-turbo.bin (his own),
# TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS=…/recordings, TEST_RUNNER_OSW_TEST_EVIDENCE=<file>
```

Result, from the run's own bundle:

```
build/Logs/Test/Test-OpenSuperWhisper-2026.09.25_11-02-40-+0200.xcresult
  passed 2  failed 0  skipped 0  result "Passed"   (finished 2026-09-25T09:05:48Z)
```

(Read with `xcresulttool get test-results summary` before the clean-state suite run in §8 removed `build/`; the log
and the summary are the surviving record. The two cases took 56.3 s — the pre-pass cost measurement — and 121.1 s —
the arm matrix, 39 decodes.)

`** TEST SUCCEEDED **`, `dev_run_exit=0`, log `/tmp/fm2414-pairing-focused-iter1.log`, evidence
`/tmp/fm2414-pairing-evidence-iter1.log` (388 measurement lines; the arm rows are also in
`evidence/arms-iter1.txt`).

Per recording, decoded once per arm:

* **`off / none (control)`** — the switch off with no prompt: upstream's 0.1 s of zeros at every pause, i.e. the
  app as it ships today. Every delta below is against this arm, word by word (case-folded, alphanumeric tokens,
  multiplicity counted, punctuation ignored).
* **`on / …`** — the switch on (`PauseBoundaryPolicy.restored`: threshold 0.6 s, cap 0.8 s) with each prompt.
* **`off / …`** — the prompt on its own, so a change can be attributed to the prompt rather than to the switch.
* **`on / none (repeated)`** — the determinism anchor.

The prompts, verbatim, and why each is in the set:

| label | string |
|---|---|
| *none* | `""` — the decoder prompt the app ships today |
| *attributed* | `You are a transcriber. Your role is just to clean up the text and make it look pretty and attractive. Do not change the sense of the sentences.` — the instruction-shaped string an earlier brief reported finding in his preferences. It was never in the code; it is one of the four arms the brief names, and the brief forbids shipping it as a default |
| *c1 (pl)* | `Dobra, jeszcze raz: wysłałem raport w poniedziałek, ale Anna nie odpowiedziała. Możesz to sprawdzić?` |
| *c2 (pl)* | `Tak, zgadza się. Kiedy? Nie wiem, ale sprawdzę to jutro.` |
| *c3 (pl, no commas)* | `Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu.` — the knock-out probe the brief's four arms do not contain: c1 and c2 are comma-heavy, and if the attributed string's only virtue on `pl-1` were that it *loses* the commas, a comma-free prompt would show it |
| *c1 EN* | `Okay, one more time: I sent the report on Monday, but Anna hasn't replied. Can you check?` |

Every prompt was run against **both** languages. That is the point of the pairing measurement: a prompt's language
is not the audio's language in a bilingual install, and the design the brief asks for (a default chosen by the
language spoken) only makes sense if a mismatched prompt is measurably worse.

Three anchors hold the tables down:

* **the same arm twice is identical** on all three recordings (`on / none` decoded twice: identical
  `true, true, true`), so a difference below is the arm and not sampling;
* the control reproduces the transcript the app itself stored for the **English** recording
  (`switch-off/none text == the app's stored transcript: true`); on the two Polish ones it does not
  (`false`, `false`) — those were dictated while the attributed string sat in his domain, which is the known,
  corrected finding of `fm-20260924-12`, not a defect of this harness;
* the whole 388-line evidence file was produced by a run whose two cases are green.

## 3. The arms, verbatim, with word-level deltas

`s / f` is the sentence count and the number of fragments (≤ 2 words); the punctuation column is the count of
`. , ? ! : ; … — "` in that order; the delta is **against the switch-off/none control** (`-` = in the control,
missing here; `+` = here, not in the control); `ms` is the decode's wall time.

### `pl-1` (12.1 s) — the recording whose boundary the switch is supposed to gain

| arm | s / f | punctuation | word delta vs control | ms | text |
|---|---|---|---|---|---|
| **off / none (control)** | 2 / 0 | `.2 ,3` | baseline | 2594 | Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą, bo tu chodzi o to, że żeś **pieprzył** po całości. |
| on / none | 3 / 0 | `.3 ,2` | `-1 pieprzył +1 spieprzył` | 2643 | …Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś **spieprzył** po całości. |
| on / attributed | 3 / 0 | `.3 ,0` | `-1 pieprzył +1 spieprzył` | 2662 | Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś spieprzył po całości. |
| on / c1 (pl) | 2 / 0 | `.2 ,3` | `-1 pieprzył +1 spieprzył` | 2629 | …inną drogą**,** bo tu chodzi o to, że żeś spieprzył po całości. *(the boundary is traded away again)* |
| on / c2 (pl) | 2 / 0 | `.2 ,3` | `-1 pieprzył +1 spieprzył` | 2644 | identical to c1 |
| **on / c3 (pl, no commas)** | **3 / 0** | `.3 ,2` | `-1 pieprzył +1 spieprzył` | 2675 | …inną drogą. Bo tu chodzi o to, że żeś spieprzył po całości. *(the boundary stays)* |
| on / c1 EN | 2 / 0 | `.2 ,3` | `-1 pieprzył +1 spieprzył` | 2666 | …inną drogą, bo tu chodzi… *(an English prompt costs the boundary too)* |
| off / attributed, off / c1, off / c2, off / c3, off / c1 EN | 2–3 / 0 | `.2 ,3` or `.3 ,0` | words unchanged (punctuation moves) | 2578–2633 | the prompt alone changes punctuation only |

Read from it: on `pl-1` **no prompt moves a word** (the only word delta is the switch's own `pieprzył` →
`spieprzył`, present in every switch-on arm), so the whole question on Polish is punctuation and the sentence
boundary — and there the axis is the comma: the two comma-heavy candidates (c1, c2) and the English candidate all
*add* commas and merge the boundary away, while **c3 — the comma-free probe — keeps exactly the boundary the
switch gained** (`2 → 3` sentences, "…inną drogą. Bo tu chodzi…"). That is the first measurement in this fleet that
tells "instruction-shaped" apart from "comma priming": the attributed string and c3 behave alike, and neither
instructs.

### `pl-2` (23.3 s) — the recording whose words the switch recovers

| arm | s / f | punctuation | word delta vs control | ms | text |
|---|---|---|---|---|---|
| **off / none (control)** | 6 / 1 | `.6 ,1` | baseline | 2938 | …odzyskałem **spój** polski. Udało mi się zrobić **forkę**. **Będę super whisper.** **Dałem** drugi model. Jestem. Znowu po polsku. |
| on / none | 6 / 1 | `.6 ,1` | `-2 będę, dałem +3 dodałem, i, open` | 2993 | …**Open Super Whisper.** **Dodałem** drugi model. **I jestem.** Znowu po polsku. |
| on / attributed | 6 / 1 | `.6 ,1` | `-4 będę, dałem, forkę, spój +4 dodałem, fork, open, swój` | 2919 | …odzyskałem **swój** polski. Udało mi się zrobić **fork**. **Open Super Whisper.** **Dodałem** drugi model. Jestem. Znowu po polsku. |
| on / c1 (pl) | 6 / 1 | `.6 ,1` | `-2 będę, dałem +2 dodałem, open` | 2966 | as `on / none`, minus the invented "I" |
| on / c2 (pl) | 6 / 1 | `.6 ,1` | `-2 będę, dałem +2 dodałem, open` | 2918 | identical to c1 |
| on / c3 (pl, no commas) | 6 / 1 | `.6 ,1` | `-3 będę, dałem, spój +3 dodałem, open, swój` | 2899 | …odzyskałem **swój** polski. Udało mi się zrobić forkę. **Open Super Whisper.** **Dodałem**… |
| on / c1 EN | 6 / 1 | `.6 ,1` | `-4 będę, dałem, forkę, spój +5 a, dodałem, fork, open, swój` | 2900 | …zrobić **fork-a**. **Open Super Whisper.** **Dodałem**… *(an English prompt on Polish audio hyphenates the word)* |
| off / attributed | 6 / 1 | `.6 ,1` | `-3 będę, forkę, spój +3 ben, fork, swój` | 2853 | …zrobić **fork**. **Ben super whisper.** Dałem drugi model… *(the prompt alone recovers `swój`/`fork` but not the switch's two words: it is not a substitute for the switch)* |

Read from it: `pl-2`'s win — **Open Super Whisper** and **Dodałem**, the two the brief names — appears in **every**
switch-on arm, prompt or no prompt, because it is the switch's audio half doing it (the same recording with the
switch off reads "Będę super whisper… Dałem drugi model"). No prompt is needed for the Polish win, and the only
prompt that additionally recovers `spój` → `swój` is the attributed one (at `-4 +4`, i.e. it trades `forkę` for
`fork` — over the whole file, four words change).

### `en control` (33.0 s) — the arm that decides the verdict

| arm | s / f | punctuation | word delta vs control | ms | text |
|---|---|---|---|---|---|
| **off / none (control)** | 3 / 0 | `.3 ,0` | baseline | 3048 | Also add feature to ignore pauses. Basically **how** it creates **a sentence** without a sense because of my long pauses. The pauses need to be ignored. |
| on / none | 4 / 0 | `.4 ,4` | `-2 how, sentence +7 based, creates, it, no, now, now, sentences` | 3143 | Also add feature to ignore pauses. Basically, now it creates,. **based, no,** now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored. *(the known regression, reproduced)* |
| **on / attributed** | 3 / 0 | `.3 ,0` | **`-2 how, sentence +2 now, sentences`** | 3048 | Also add feature to ignore pauses. Basically **now** it creates **a sentences** without a sense because of my long pauses. The pauses need to be ignored. |
| **on / c1 EN** | 3 / 0 | `.3 ,1` | **`-2 how, sentence +2 now, sentences`** | 3042 | Also add feature to ignore pauses. Basically**,** now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored. |
| on / c1 (pl) | 12 / 7 | `.12 ,0` | `-2 how, sentence +6 creates, it, no, now, now, sentences` | 3096 | …Basically now it creates**...** no**...** now it creates a**... sentences** without a sense… *(fragments back: a Polish prompt on English audio)* |
| on / c2 (pl) | 12 / 7 | `.12 ,1` | `-3 also, how, sentence +8 aż, creates, it, no, nooo, now, now, sentences, to` | 3203 | **Aż to** add feature to ignore pauses. …**Nooo...** Now it creates a... Sentences without a sense… *(Polish words leak into English)* |
| on / c3 (pl, no commas) | 12 / 7 | `.12 ,0` | `-2 how, sentence +6 creates, it, no, now, now, sentences` | 3825 | …Basically now it creates**...** No**...** Now it creates a**... Sentences** without a sense… |
| off / attributed | 3 / 0 | `.3 ,0` | **words unchanged** (`+0 -0`) | 3029 | Also add feature to ignore pauses. Basically how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored. |
| off / c1 (pl) | 3 / 0 | `.3 ,1` | `-1 also` | 3027 | **Add** feature to ignore pauses. Basically, how it creates a sentence… |
| off / c2 (pl) | 3 / 0 | `.3 ,1` | `-1 also +2 aż, to` | 3069 | **Aż to** add feature to ignore pauses… |
| off / c3 (pl, no commas) | 3 / 0 | `.3 ,1` | `-1 also +1 to` | 3065 | **To** add feature to ignore pauses… |
| off / c1 EN | 3 / 0 | `.3 ,1` | `-1 sense +1 sentence` | 3024 | …without **a sentence** because of my long pauses. *(a repeated word, even with the switch off)* |

Read from it, and this is the whole verdict in one table:

* **With a language-matched prompt the invented fragment is gone.** `on / none` invents five words the control does
  not have (`based`, `creates`, `it`, `no`, `now` once more) *plus* the two below; `on / attributed` and
  `on / c1 EN` invent exactly two. That is the prompt doing what the brief hoped: the "based, no," fragment and the
  repeated "creates/it/now" are cured.
* **The two remaining words are not the prompt's.** `-2 how, sentence +2 now, sentences` is present in the arm with
  **no prompt at all** (inside its larger `-2 +7`), it is identical for *two different* prompts, and the prior
  crew's cap sweep shows the same two at 0.2 s, 0.4 s, 0.6 s and 0.8 s. It is what keeping the real pauses does to
  the decode: the pause before "how" makes the decoder hear "now", and the pause inside the clause makes it write
  "sentences". No prompt can undo it, and no prompt may be *tuned* to undo it without overfitting to this one
  recording.
* **A prompt in the wrong language is worse than none.** The Polish prompts on English audio bring the fragments
  back to twelve sentences (`on / c2 (pl)`: "Aż to add feature… Nooo... Now it creates a... Sentences without a
  sense"), i.e. a prompt must be matched to the language actually spoken — which is exactly why the brief asks for
  a language-aware default, and why the app's architecture (no language setting; the engine auto-detects inside the
  decode) forces the mechanism measured in §5.

## 4. The pairing table: every configuration the app could ship

For each pair (Polish prompt, English prompt) the app could ship as its default, the brief's criterion. The rows
below compress the square (each Polish prompt is also shown against the other English prompts in the evidence
file); every one of the 36 cells is a FAIL:

| pl prompt | en prompt | English control words vs control | `pl-1` boundary | `pl-2` words | verdict |
|---|---|---|---|---|---|
| none | none | `-how -sentence +based +creates +it +no +now +now +sentences` | yes | yes | **FAIL** |
| none | attributed | `-how -sentence +now +sentences` | yes | yes | **FAIL** |
| none | c1 EN | `-how -sentence +now +sentences` | yes | yes | **FAIL** |
| none | c1 (pl) | `-how -sentence +creates +it +no +now +now +sentences` | yes | yes | **FAIL** |
| none | c2 (pl) | `-also -how -sentence +aż +creates +it +no +nooo +now +now +sentences +to` | yes | yes | **FAIL** |
| none | c3 (pl) | `-how -sentence +creates +it +no +now +now +sentences` | yes | yes | **FAIL** |
| **c3 (pl)** | **attributed** | `-how -sentence +now +sentences` | **yes** | **yes** | **FAIL** |
| **c3 (pl)** | **c1 EN** | `-how -sentence +now +sentences` | **yes** | **yes** | **FAIL** |
| c1 (pl), c2 (pl), c1 EN | any | as above for the English column | **NO** (boundary traded away) | yes | **FAIL** |
| attributed | any | as above for the English column | yes | yes | **FAIL** |

All **36** configurations were evaluated (6 × 6; the harness prints the square in the evidence file, and
`evidence/verdict.py` recomputes it independently from the transcripts with a different implementation — both give
the same answer: **36 FAIL, 0 PASS**). The best rows are the two bold ones above: the Polish win is fully in hand
(`c3` keeps the boundary, every arm keeps `pl-2`'s words), and the English control is never word-clean — the
minimum is the two-word switch-induced difference.

Two further readings that matter to whoever decides:

* the **shortest** English delta any configuration achieves is `-2 +2`;
* the **attributed** string is *not* better than a shipped-candidate prompt on English (both `-2 +2`) and it is
  worse on the file as a whole (it moves four words on `pl-2` where a candidate moves two), so the brief's
  instruction not to ship it as a default is also the measurement's conclusion. It remains the only arm that
  recovers `pl-2`'s individual words (`spój` → `swój`, `forkę` → `fork`), so if he wants those it belongs in **his**
  `initialPrompt` preference — which this branch did not touch — not in a default.

## 5. The second, independent reason: the mechanism the brief asks for costs 38 % of a dictation

The brief's language-aware default needs the language **before** the decoder prompt is chosen, and this app has no
language setting (`params.language = nil`; the engine is always asked to measure). whisper.cpp offers one way out —
`detect_language` makes `whisper_full` compute the mel and the encoder, read the language and return without
decoding a token (`libwhisper/whisper.cpp/src/whisper.cpp:6849-6865`) — so the design is implementable, and it is
measurable. Measured, on his own audio, with the app's own context parameters (GPU, flash attention) and the same
stitched audio the decoder would get:

```
pl-1 (12.1 s)      | audio the decoder hears 10.9 s | pre-pass 1343/1314 ms (language pl) | decode 3522/3391 ms
pl-2 (23.3 s)      | audio the decoder hears 11.6 s | pre-pass 1336/1351 ms (language pl) | decode 3560/3813 ms
en control (33.0 s)| audio the decoder hears 18.6 s | pre-pass 1346/1348 ms (language en) | decode 3548/3509 ms
```

**The pre-pass is ~1.34 s on every recording — 38–39 % of the decode it precedes** (`ms` = two runs each), because
the encoder always processes the full 30 s window whatever the clip's length. The detection itself is accurate on
these three (the pre-pass's language equals the decode's own on all three, asserted in the run), so this is a
*latency* cost, not an accuracy problem — and it is paid on **every dictation** of every install whose switch is on
and whose prompt is empty, which after the flip the brief asks for is all of them.

So the three candidate mechanisms are all measured:

| mechanism | English control word-clean? | Polish win? | cost per dictation |
|---|---|---|---|
| switch on + **one** prompt for all languages | no (`-2 +2`), and worse wherever the prompt's language ≠ the audio's (`+6`/`+8`, twelve fragments, Polish words in English text) | yes | none |
| switch on + **language-matched** default prompt | no (`-2 +2`) — the language key removes the wrong-language damage but not the switch's own two words | yes | **+1.34 s (≈ +38 %)** |
| switch on for **Polish only** (English keeps upstream's audio) | **yes** — the English decode is byte-for-byte the control's | yes | +1.34 s, and it redefines what the captain's switch does |

Only the third row satisfies the criterion, and it is not what the brief authorises: it is not "a decoder prompt
paired with the switch", it is *the switch becoming language-dependent*, i.e. the switch the captain asked for would
silently do nothing on English. That is a product decision for the captain, not for this branch, so it was not
implemented.

## 6. What is not shipped, and what a new install gets

**Nothing was landed.** The branch is `eaecd28`, unchanged (`git status --porcelain` after this work: one untracked
measurement file, no modified file); no default was flipped; **his stored preferences were read, never written**
(`defaults read` only).

| | a new install **today** (unchanged by this task) | the captain's install | after the ready patch (§7), if someone accepts the two-word English change |
|---|---|---|---|
| `longPausesEndSentences` | absent → **off** (`AppPreferences.swift:192`, `defaultValue: false`) | **absent** (`defaults read ru.starmel.OpenSuperWhisper longPausesEndSentences` → *Could not find key*) | reads **on**; his dictation starts keeping long pauses |
| `initialPrompt` | absent → the default `""` (nothing is written), and the decoder is sent no prompt | `""` (empty) | still `""` in his domain; Polish dictations would send the Polish default, English ones the English default (needs the 1.34 s pre-pass) |
| `whisperLanguage` | absent | `pl` — a removed key nothing reads (documented as such in `AppPreferences.swift:230`) | untouched, still unread |
| decoder prompt actually sent | none | none | `WhisperEngine.defaultDecoderPrompt(forLanguage:)`, measured per language |

For the captain: **nothing changes**, because this task refused on the measurement. For the record, had it passed,
the flip would have given *him* the switch on and the language's prompt for both of his languages without touching
a single stored value — the two user-visible product changes the brief asks to be reported prominently.

## 7. What would land if the captain accepts the English change

The implementation is written, tested and measured — kept as a patch rather than a commit, because the criterion
failed: `evidence/pairing-implementation.patch` (applies cleanly to `eaecd28`; verified by applying it to a scratch
copy of the base tree — on this worktree, which still holds the untracked phase-1 measurement file, remove
`OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift` first, since the patch creates its phase-2 form, also
kept at `evidence/WhisperPauseBoundaryPairingTests-phase2.swift`). It contains exactly:

* `Engines/WhisperEngine.swift` — `defaultDecoderPrompt(forLanguage:)` (one measured entry for Polish, one for
  English, nothing for any language nobody measured), `decoderPrompt(userPrompt:longPausesEndSentences:showsTimestamps:spokenLanguage:)`
  (the user's prompt always wins; a switch off and timestamp mode send no default), the language pre-pass
  (`measureLanguage`, whose cost is §5, and `en` for an English-only model without a pass at all), and the wiring
  in `performTranscription`;
* `Utils/AppPreferences.swift` — `longPausesEndSentences` default **true** with the measurement in its doc, and the
  `initialPrompt` doc that says an empty stored value still sends a language default;
* `OpenSuperWhisperTests/DecoderPromptDefaultTests.swift` (8 cases: the rule in every language and switch state,
  the table's strings, timestamp mode, the two shipped defaults, and that reading a default writes nothing into
  the user's domain) and the shipped-configuration case in the pairing harness (which asserts the criterion on the
  app's own path — and would fail today, which is the point);
* `PauseBoundaryTests.swift` — the case that pinned the *off* default is deleted, not re-pinned.

## 8. Verification

* The measurement run: `** TEST SUCCEEDED **`, `dev_run_exit=0`, 2 passed / 0 failed / 0 skipped, finished
  `2026-09-25T09:05:48Z`; every native engine, the Rust autocorrect tree and the app compiled from scratch in this
  worktree in this session, in a worktree created with no derived data; the bundle re-signed with
  `identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"`
  (`certificate leaf`, not a `cdhash`).
* The full suite on this tree from a clean state: `build/` removed first, so every native engine, the Rust
  autocorrect tree and the app were recompiled from scratch in this worktree in this session; then
  `Scripts/dev-run.sh test` (never a bare `xcodebuild test`) with the measurement's environment set, so **the
  measurement ran inside that green suite** and the tables above come from a run whose cases are green. Result:
  `** TEST SUCCEEDED **`, `dev_run_exit=0` (09:17:51Z), and from the run's own bundle
  `build/Logs/Test/Test-OpenSuperWhisper-2026.09.25_11-12-29-+0200.xcresult` — **total 465 / passed 411 / failed 0 /
  skipped 54**, result `Passed`, finished `2026-09-25T09:17:48Z` (`xcresulttool get test-results summary`; log
  `/tmp/fm2414-suite.log`). The 54 skips are this tree's usual environmental ones (input sources, Accessibility
  automation, microphone opt-ins); the measurement's cases ran. The same run re-signed the bundle — `valid on disk`,
  `satisfies its Designated Requirement`, `identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf =
  H"32266bcc51546f68f9347324bd3c81d853fde5a4"` (`certificate leaf`, never a `cdhash`), so the Accessibility grant
  survives.
* Independent re-derivation of the pairing table from the transcripts (`evidence/verdict.py`, a second
  implementation): identical verdicts, 36 FAIL / 0 PASS.
* Determinism, inside a run and across runs: the repeated arm is identical on all three recordings in both runs,
  and the whole arm matrix was decoded twice — the focused run and the suite run — with **39 of 39 arm texts
  identical** between them (`evidence/compare-runs.py` over `arms-iter1.txt` and `arms-iter2.txt`; `iter2` is also
  kept whole at `evidence/fm2414-pairing-evidence-iter2.log`). Nothing in the tables is run-specific.

## 9. Unverified, or deliberately left alone

* **The English control's two words are not provably inventions.** The control is a *decoded* proxy for what he
  said, and it is itself wrong here: the captain's spoken sentence was "**Essentially**, it creates a sentence
  without a sense…" (his own written words in the brief) and the control hears "Basically **how** it creates…". So
  `how` → `now` may be a *correction* rather than damage, which is precisely the kind of call the brief reserves
  for him. What is measured is the difference, not which side is right.
* **Three recordings, one speaker, one model.** The pairing is measured on `pl-1`, `pl-2` and the English control,
  as the brief specifies. The two-word English difference is a property of *that* pause in *that* recording; other
  English audio may be unaffected or worse. Nothing here is a claim about English in general.
* **Nothing was measured for any language but Polish and English.** The switch's default and any prompt default
  would apply to all 25 languages whisper can transcribe; the pre-pass was checked to agree with the decode's
  language on these three recordings only.
* **The pre-pass's cost is this machine's.** Mac mini, GPU with flash attention, 8 threads; a CPU-only run, or a
  longer clip, pays differently (the encoder is a fixed 30 s window, the decode grows with the audio).
* **No UI, hotkey or delivery path was exercised** (headless by contract). `transcribeSamplesDetailed` shares
  `performTranscription` and therefore whatever `performTranscription` does, but no case decodes real audio through
  it: the measurement drives the file entry point, as `fm-20260924-12` did.
* **The timestamp path is untested for a prompt default** — the patch makes it send none by construction
  (`showsTimestamps` is in the rule and has a pure case), but no decode was measured with it on.
* **Option 3 (a language-gated switch) is not implemented and not measured end-to-end.** It follows from the two
  measurements above (the English difference is the switch's audio; a language-matched prompt still cannot remove
  it) but nobody has run it, so its numbers would be the same pre-pass cost plus the pause work with a language
  gate — a claim, not a measurement.
* **`evidence/pairing-implementation.patch` was verified by applying it to a scratch copy of `eaecd28` and by
  `swiftc -parse`**, not by a suite run: no commit means no green build of the landed shape. Its own tests are the
  ones the refusal's condition would have required.
