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

---

## IMPLEMENTATION — option (a): the pause fix everywhere, keyed to the language spoken

Landed on branch `fm/pause-implementation`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pauseimpl`, base `d960bb7` (the
delivery tip, one merge ahead of the refusal's `eaecd28`; `Engines/WhisperEngine.swift` and `Utils/AppPreferences.swift`
are byte-identical between the two, which is why the preserved patch still targeted it). Headless throughout: no app
launch, no `osascript`, no `screencapture`, no bare `xcodebuild test`, no subagents, no model file moved or copied,
and **nothing written to the captain's stored preferences** — every run was gated on a free machine and detached with
`subprocess.Popen(..., start_new_session=True)`; logs `/tmp/fm2416-*`.

### 1. What the decision became, in code

* `Utils/AppPreferences.swift:210` — `@UserDefault(key: "longPausesEndSentences", defaultValue: true)`, so the switch
  the captain chose to ship **on** is on for every install that never touched it (`defaults read
  ru.starmel.OpenSuperWhisper longPausesEndSentences` → *Could not find key*, i.e. his install included).
* `Engines/WhisperEngine.swift` — `defaultDecoderPrompt(forLanguage:)` with **two** measured entries (`pl`, `en`;
  nothing for any other language, which sends no prompt, byte for byte what this app always did), and the rule
  `decoderPrompt(userPrompt:longPausesEndSentences:showsTimestamps:spokenLanguage:)`:
  * a prompt the user set always wins — any language, either switch state, no second-guessing;
  * the switch off sends no default, so off is upstream's audio and upstream's (empty) prompt;
  * timestamp mode sends no default (the decoder is handed untrimmed audio and no pause is measured there);
  * otherwise the default for the language the engine measured, or nothing if that language has no entry.
* `Engines/WhisperEngine.swift` — `measureLanguage(of:nThreads:)`, the detect-only pre-pass (`params.detectLanguage`,
  mel + encoder, no token, `whisper.cpp:6861`), run **only** in the one configuration that needs it:
  `settings.initialPrompt.isEmpty && pausePolicy.closesSentence && !settings.showTimestamps`. An English-only model
  pays nothing for it (`context.isMultilingual` false → `en` by construction, like `SpeechModelLanguageGate`), and its
  decoding state is freed before `prepareForRecording()` builds the transcription's own, so the pass cannot reach the
  transcript (asserted: the shipped text and the same prompt written out by hand are equal).
* `Settings.swift` — the switch's caption and the Initial Prompt caption state the cost (below).

### 2. The preserved ingredients had one thing wrong, and the measurement says which

**First, what the preserved ingredients could not have done.** `evidence/pairing-implementation.patch` — the file the
launch brief said does not exist, and which is in fact there — cannot compile, on two independent counts, both
checked against a scratch copy of the base tree (`/tmp/fm2416-scratch`, `patch -p1` exit 0):

* its `AppPreferences.swift` hunk removes the `@UserDefault(... defaultValue: false)` line and adds
  `@UserDefault(... defaultValue: true)` **plus** a second `var longPausesEndSentences: Bool`, leaving the
  declaration twice (lines 193 and 194 of the patched file) — which Swift rejects (`invalid redeclaration`, the same
  error a two-line snippet shows);
* its `DecoderPromptDefaultTests.swift` calls `WhisperEngine.decoderPrompt(userPrompt:longPausesEndSentences:spokenLanguage:)`
  in three places (lines 71, 75, 80) while its own engine declares that function with a fourth parameter,
  `showsTimestamps:` — the exact error this branch's first build reported (`missing argument for parameter
  'showsTimestamps' in call`). The crew's `swiftc -parse` check could not see either, because `-parse` only parses.

Both were repaired here, which is what "build from the preserved sources and commit the result" turns out to mean.

**Then the substantive one.** `evidence/fm2414-WhisperEngine-wired.swift` shipped **candidate 1** (the comma-heavy
Polish string) as `polishDefaultDecoderPrompt`. In the refusing crew's **own** table that string is the one that costs
the win it is there to buy:

```
[pair] pl-1 (12.1 s) | c1 (pl) | sentences 2 | punctuation .2 ,3 | words -1 +1 | win-words:NO(drogą.) boundary:NO(2->2)
[pair] pl-1 (12.1 s) | c3 (pl, no commas) | sentences 3 | punctuation .3 ,2 | words -1 +1 | win-words:yes boundary:yes(2->3)
```

The full rows it comes from, verbatim (the refusing crew's `evidence/fm2414-pairing-evidence-iter1.log`):

```
[pair] pl-1 (12.1 s) | on / c1 (pl) | 2629 ms
[pair]   sentences 2 | fragments (<=2 words) 0 | punctuation .2 ,3 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -1 ["pieprzył"] +1 ["spieprzył"] | unchanged false
[pair]   text: Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą, bo tu chodzi o to, że żeś spieprzył po całości.
[pair] pl-1 (12.1 s) | on / c3 (pl, no commas) | 2675 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,2 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -1 ["pieprzył"] +1 ["spieprzył"] | unchanged false
[pair]   text: Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś spieprzył po całości.
[pair] pl-2 (23.3 s) | on / c3 (pl, no commas) | 2899 ms
[pair]   sentences 6 | fragments (<=2 words) 1 | punctuation .6 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -3 ["będę", "dałem", "spój"] +3 ["dodałem", "open", "swój"] | unchanged false
[pair]   text: Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić forkę. Open Super Whisper. Dodałem drugi model. Jestem. Znowu po polsku.
[pair] en control (33.0 s) | on / c1 EN | 3042 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -2 ["how", "sentence"] +2 ["now", "sentences"] | unchanged false
[pair]   text: Also add feature to ignore pauses. Basically, now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored.
```

With the switch on, the comma-heavy Polish prompts (c1, c2) and the English one prime the decoder into joining
`pl-1`'s clauses with a comma — "…inną drogą**,** bo tu chodzi…" — which is exactly the sentence boundary the switch
exists to gain, and the criterion the captain's condition 3 pins is *"Polish win present"*. So the landed Polish
default is the **comma-free** candidate, the arm the same table shows keeping the boundary (`2 → 3`) *and* `pl-2`'s
"Open Super Whisper" and "Dodałem" (`words -3 +3`), and the English default is candidate 1 EN, the arm whose English
residue is exactly the accepted `-how -sentence +now +sentences`. Both are ordinary dictation, no instruction, and the
shipped-configuration case in `WhisperPauseBoundaryPairingTests` asserts all of it.

```
    static let polishDefaultDecoderPrompt =
        "Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu."

    static let englishDefaultDecoderPrompt =
        "Okay, one more time: I sent the report on Monday, but Anna hasn't replied. Can you check?"
```

### 3. The draft comment was false and is corrected (condition 2)

The preserved draft (`evidence/fm2414-appprefs-switch.txt`) claimed the switch-on state "leaves the English control
word-for-word what the switch off gives". The crew's own verdict falsifies it — `-how -sentence +now +sentences`, in
the no-prompt arm too, identical across two different prompts. What landed instead says the change out loud, with the
date and the numbers, and points at the test that pins it. Verbatim, before → after:

```
-DRAFT: "…and leaves the English control word-for-word what the switch off gives."
+LANDED: "…and what is left is the switch's own audio half: it is present in the arm that sends no prompt at all and
+         is identical across prompts, so **no prompt removes it**. The captain was shown that with the numbers and
+         accepted it on **2026-09-25** — option (a), "pause fix everywhere, English takes a 2-word change",
+         `fleet/data/fm-20260925-14` — and the shipped configuration is asserted against exactly that delta in
+         `WhisperPauseBoundaryPairingTests`, so widening it fails the suite instead of landing quietly."
```

The same standard was applied to every other declaration that the measurement falsifies, because a comment that
contradicts the measurement it cites is worse than none:

* `DecoderPromptDefaultTests.testANewInstallGetsTheSwitchOn` said the switch on "leaves the English control clean" →
  now says what it costs and cites `acceptedEnglishChange`;
* `WhisperPauseBoundaryPairingTests`' header said the harness exists to decide whether to ship the switch, and its
  criterion case said "nothing invented, nothing lost" → both now state the refusal, the accepted two-word change and
  what is pinned;
* `CaptainRecordingPauseBoundaryTests` said "the shipped app sends none" / "the empty prompt is today's app" → now
  says that the *stored* value ships empty while a switch-on empty value sends the language default, which is why its
  own empty-prompt arms read as they do;
* Readme §8 said the switch ships off and that the English counterpart of candidate 1 "comes back clean … nothing
  invented" → both replaced (condition 4).

### 4. What a new install gets, and what his domain would change to (condition 5)

Nothing was written to `ru.starmel.OpenSuperWhisper`; the domain was read, never set (`defaults read` only).

| key | a new install | the captain's domain (read, not written) | what his dictation does after this change |
|---|---|---|---|
| `longPausesEndSentences` | absent → **on** (the new default) | **absent** → *Could not find key* → on | long pauses are kept; his Polish boundary and words come back |
| `initialPrompt` | absent → `""` → the language's default is sent | `""` (stored empty, which the engine treats as not set) | Polish dictations send the Polish default, English ones the English default, other languages send none |
| `whisperLanguage` | absent | `pl` — a removed key nothing reads | untouched, still unread |
| decoder prompt actually sent | the language's entry, or none | the language's entry, or none | +1 language pre-pass (≈1.34 s) per dictation whose switch is on and prompt is empty |

### 5. Verification

* **Focused run** of the three changed classes, in this worktree, with the captain's own model, settings and
  recordings exported (`/tmp/fm2416-focused3.log`, kept as `evidence/fm2416-focused3.log`): `DecoderPromptDefaultTests`
  8 cases, `WhisperPauseBoundaryTests` 27, `WhisperPauseBoundaryPairingTests` 3 — the arm matrix, the pre-pass cost,
  and the shipped configuration. `** TEST SUCCEEDED **`, `dev_run_exit=0` at 2026-09-25T09:48:07Z; the run's own bundle
  `Test-OpenSuperWhisper-2026.09.25_11-44-37-+0200.xcresult` reports **total 38 / passed 38 / failed 0 / skipped 0**, result `Passed`, and the criterion case
  `testTheShippedConfigurationKeepsThePolishWinAndOnlyTheAcceptedEnglishChange()` is among the passed ones.
* **The shipped configuration's own evidence** (from that run's evidence file, verbatim — the arm the app now runs
  is `shipped (no stored prompt, switch on)`, diffed word by word against the switch-off/none control):

```
[pair] pl-1 (12.1 s) | off / none (control) | 2572 ms
[pair]   sentences 2 | fragments (<=2 words) 0 | punctuation .2 ,3 ?0 !0 :0 ;0 …0 —0 "0
[pair]   text: Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą, bo tu chodzi o to, że żeś pieprzył po całości.
[pair] pl-1 (12.1 s) | shipped (no stored prompt, switch on) | 3641 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,2 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -1 ["pieprzył"] +1 ["spieprzył"] | unchanged false
[pair]   text: Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś spieprzył po całości.
[pair] pl-1 (12.1 s) shipped | the engine measured pl | the table's prompt for it: Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu.
[pair] pl-1 (12.1 s) | shipped: the same prompt, written out | 2630 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,2 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -1 ["pieprzył"] +1 ["spieprzył"] | unchanged false
[pair]   text: Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś spieprzył po całości.
[pair] pl-2 (23.3 s) | off / none (control) | 2972 ms
[pair]   sentences 6 | fragments (<=2 words) 1 | punctuation .6 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   text: Dobra wiadomość jest taka, że odzyskałem spój polski. Udało mi się zrobić forkę. Będę super whisper. Dałem drugi model. Jestem. Znowu po polsku.
[pair] pl-2 (23.3 s) | shipped (no stored prompt, switch on) | 4027 ms
[pair]   sentences 6 | fragments (<=2 words) 1 | punctuation .6 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -3 ["będę", "dałem", "spój"] +3 ["dodałem", "open", "swój"] | unchanged false
[pair]   text: Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić forkę. Open Super Whisper. Dodałem drugi model. Jestem. Znowu po polsku.
[pair] pl-2 (23.3 s) shipped | the engine measured pl | the table's prompt for it: Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu.
[pair] pl-2 (23.3 s) | shipped: the same prompt, written out | 3029 ms
[pair]   sentences 6 | fragments (<=2 words) 1 | punctuation .6 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -3 ["będę", "dałem", "spój"] +3 ["dodałem", "open", "swój"] | unchanged false
[pair]   text: Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić forkę. Open Super Whisper. Dodałem drugi model. Jestem. Znowu po polsku.
[pair] en control (33.0 s) | off / none (control) | 3202 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,0 ?0 !0 :0 ;0 …0 —0 "0
[pair]   text: Also add feature to ignore pauses. Basically how it creates a sentence without a sense because of my long pauses. The pauses need to be ignored.
[pair] en control (33.0 s) | shipped (no stored prompt, switch on) | 4284 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -2 ["how", "sentence"] +2 ["now", "sentences"] | unchanged false
[pair]   text: Also add feature to ignore pauses. Basically, now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored.
[pair] en control (33.0 s) shipped | the engine measured en | the table's prompt for it: Okay, one more time: I sent the report on Monday, but Anna hasn't replied. Can you check?
[pair] en control (33.0 s) | shipped: the same prompt, written out | 3210 ms
[pair]   sentences 3 | fragments (<=2 words) 0 | punctuation .3 ,1 ?0 !0 :0 ;0 …0 —0 "0
[pair]   word delta vs the switch-off/none control: -2 ["how", "sentence"] +2 ["now", "sentences"] | unchanged false
[pair]   text: Also add feature to ignore pauses. Basically, now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored.
```

* **Who ran the clean full suite.** The first clean full suite of this change was run by this crew, in this worktree,
  from a clean state (`build/` removed first, both native engines, the Rust autocorrect tree and the app recompiled
  from scratch in this session; `Scripts/dev-run.sh test`, never a bare `xcodebuild test`), with the captain's
  recordings and a multilingual model exported so **the criterion case ran inside it**:
  `Test-OpenSuperWhisper-2026.09.25_11-53-24-+0200.xcresult` reports **total 473 / passed 418 / failed 1 / skipped
  54** — its single failure is the capture harness the next subsection is about. After that repair this crew verified
  the harness scoped (7/7, below) and **handed the branch over unmerged**: the acceptance run for the whole tip is
  **Main's** — one clean full suite on the merged tip (the delivery tip was `e8ea391` at handover), covering this work
  and the transform-guard rule that landed beside it — and it is attributed to Main, not to this crew, and is not
  presented here as this crew's execution.
* **The bundle is identity-signed**, not ad-hoc: `codesign -d -r-` reports `designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"` — a certificate requirement, not
  `cdhash H"…"`; `codesign --verify --deep --strict` reports satisfies its Designated Requirement, valid on disk, and the leaf is H"32266bcc51546f68f9347324bd3c81d853fde5a4". The bundle id is `ru.starmel.OpenSuperWhisper.dev`, because this is a crew worktree (the checkout whose app
  is tested keeps the shipped id). `spctl -a -vv` *rejects* the bundle, as it always does for this fork: the
  identity is a locally created self-signed one and nothing is notarized, which is exactly what the Designated
  Requirement above exists to survive — the Accessibility grant is matched against the certificate, not a cdhash.
* **The pre-pass perturbs nothing, and the pass is repeatable**: the criterion case requires the shipped text to
  equal the same audio decoded with the language's prompt written out by hand (the pre-pass's only job is choosing
  the prompt), and the pre-pass case asserts the detected language equals the decode's own on all three recordings.
  Inside the arm matrix the repeated arm is byte-identical on all three recordings in this run too —
  `pl-1: true`, `pl-2: true`, `en control: true` (`the same arm twice is identical`) — and the English control's
  switch-off/none text is still the transcript the app itself stored for that recording (`true`), which is what makes
  these numbers this app's own path rather than a harness's idea of it.
* **Nothing was written to his preferences.** `defaults read ru.starmel.OpenSuperWhisper` before and after every run
  gives the same values — `longPausesEndSentences` *absent*, `initialPrompt` `""`, `whisperLanguage` `pl` — and no code
  path in this change writes either key; `DecoderPromptDefaultTests` asserts that reading the prompt does not create
  the key.

#### The one red case in the first clean suite was the capture harness, not the feature

The first clean full suite (before the harness repair below) came back **473 total / 418 passed / 1 failed / 54
skipped**, and the single failure was `SettingsLayoutSnapshotTests.testTranscriptionTabScrollsToItsLastCard`:

```
tab-transcription-scroll-bottom: cards are less than 4.0 pt apart (gaps [1, 1]); cards drawn into each other leave
no page background between them
[snapshot] tab-transcription-scroll-bottom 518x468: bg=(30, 30, 30) bands=[71-202, 204-467] gaps=[1, 1]
```

Three things say that is a misclassified capture rather than cards drawn into each other:

* the detected "background" is **(30, 30, 30)** — the *card* colour (`controlBackgroundColor` at 0.3 opacity over
  black), so the row the detector sampled as page background was inside a card;
* every other capture of that same tab in the same run has gaps of exactly 20 pt (`tab-transcription-520x560`,
  `tab-transcription-520x900`, `tab-transcription-content-*`), and so does the *top* capture of this very case;
* the refusing crew's own **green** run left the same capture as garbage —
  `bg=(9, 9, 9) bands=[23-96, 108-115, 133-152, 173-181, 203-211, 223-264, 281-300, 320-329, 452-467]
  gaps=[22, 11, 17, 20, 21, 11, 16, 19, 24, 24, 24, 9, 19]` — nine bands where the tab has three cards. It passed by
  luck: every gap happened to be ≥ 4. My longer Settings caption changed the scroll geometry, and the same
  misclassified capture this time landed with 1 pt gaps.

The harness is the cause, and its own code says why: the detector read the page background from **row 8 at the probe
column** (40 px in), which is page background only in a capture of the *top* of a tab — in a capture scrolled to the
bottom, row 8 is inside a card, so the "background" comes back as the card colour `(30, 30, 30)`, every gap reads as a
card and every card as a gap. That is exactly what the failing capture's numbers are, and the pixel decode of that PNG
confirms it: the page background is `(0, 0, 0)` in the padding column at *every* row, the card colour is `(30, 30, 30)`,
and the genuine gaps are 20 pt (`y 133-152`, `y 281-300`) with the 16 pt page padding at `y 452-467`.

The repair is the background sample, and nothing else: it is now taken from the tab's own left page padding (2 pt in,
inside the 16 pt padding) at three heights, with a fallback to the old probe-column sample if those three do not agree
(so a capture whose padding column is not page behaves as before). **The asserted invariant is untouched** — cards
still have to be at least 4 pt apart, the probe column is still 20 pt in, and the assertion itself is unchanged — so
this makes the check honest rather than making it pass. Two earlier attempts are worth recording because they were
wrong and the scoped run proved it: a scroll that waits until the reported bottom offset stops moving, and a capture
accepted only once the raster stops changing, left the failing capture **byte-identical** (`bg=(30,30,30)
bands=[71-202, 204-467] gaps=[1, 1]` both times), which is what ruled the "mid-draw raster" reading out and sent me to
the pixels. Both were reverted; the harness diff is one hunk.

The transcription tab has **seven cards** (`tab-transcription-content-*`: bands `[16-333, 354-514, 535-692, 713-1636,
1657-1839, 1860-1987, 2008-2158]`, gaps of exactly 20 pt, total 2175 px at 1x), and the scrolled-bottom capture at
518x468 shows the last three of them with 20 pt gaps and the 16 pt page padding under the stack.

Scoped verification, `Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/SettingsLayoutSnapshotTests` in this
worktree: **7 tests, 7 passed, 0 failed, 0 skipped**, `** TEST SUCCEEDED **`, `dev_run_exit=0` at
2026-09-25T10:09:53Z, and the capture that was red now reads
`[snapshot] tab-transcription-scroll-bottom 518x468: bg=(0, 0, 0) bands=[0-132, 153-280, 301-451] gaps=[20, 20]` —
the page background and the 20 pt gaps the pixels actually contain.

### 6. The criterion test (condition 3)

`OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift` —
`testTheShippedConfigurationKeepsThePolishWinAndOnlyTheAcceptedEnglishChange`. It decodes the app's own configuration
(new-install defaults: no stored prompt, switch on) and asserts three things: `pl-1` gains the pause's boundary
(sentences `2 → 3`) *and* reads "drogą."; `pl-2` carries `Open Super Whisper` and `Dodałem`; and the English control's
word delta against the switch-off/none control is **exactly** the accepted one:

```swift
    private static let acceptedEnglishChange = (
        removed: ["how", "sentence"],
        added: ["now", "sentences"]
    )
    …
    XCTAssertEqual(delta.removed, Self.acceptedEnglishChange.removed, …)
    XCTAssertEqual(delta.added, Self.acceptedEnglishChange.added, …)
```

A change that widens the English damage now fails the suite instead of being reported; a change that narrows it fails
too, on purpose, so the accepted number stays the one the captain was shown. The same case also asserts that the
shipped path is the table's arm (the same audio with the language's prompt written out by hand must give the same
text), which is the evidence that the pre-pass changes nothing about the transcription it precedes.

### 7. The same caveat, in the same words (condition 4)

`Utils/AppPreferences.swift` (the switch's doc), `Readme.md` §8 and `Settings.swift` (the switch's caption) carry one
sentence, word for word — checked mechanically (`/tmp/fm2416-caveat-check.py` pulls it out of the Swift comment, the
Readme blockquote and the Settings caption, normalises line wrapping and Swift escapes, and compares): **634
characters, identical in all three**. The Settings copy renders its two quoted examples with typographic quotes
(`\u{201C}…\u{201D}`) where the comment and the Readme use straight ones, which is the only difference between the
three, and the numbers in it are the measurement's (`+1.34 s` against a `3.5 s` decode, `≈ 38 %`).

> With no prompt of your own the decoder prompt is chosen by the language of the dictation, and that costs one extra
> detect-only language pass over the audio before each dictation — measured +1.34 s against a 3.5 s decode, ≈ 38 % —
> paid only while this switch is on and no prompt is set; and on pause-heavy English speech the switch changes two
> words against the switch off ("Basically now it creates a sentences" where the switch off says "Basically how it
> creates a sentence"), a change the captain accepted on 2026-09-25 with the measurement in front of him, because no
> prompt removes it and the Polish fix rides on the same silence.

### 8. Verbatim diffs

`Engines/WhisperEngine.swift (the pre-pass, the table, the rule)`

```diff
diff --git a/OpenSuperWhisper/Engines/WhisperEngine.swift b/OpenSuperWhisper/Engines/WhisperEngine.swift
index 6bea679..e994fc9 100644
--- a/OpenSuperWhisper/Engines/WhisperEngine.swift
+++ b/OpenSuperWhisper/Engines/WhisperEngine.swift
@@ -324,12 +324,31 @@ class WhisperEngine: TranscriptionEngine {
         let samples = stitched.samples
         
         let nThreads = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))
-        
-        let initialPromptTokenCount = settings.initialPrompt.isEmpty
+
+        // The decoder prompt this transcription sends. The user's own is one
+        // string and always wins; when they have set none and the switch is on,
+        // it is the default its language has (`Self.decoderPrompt`) — which is
+        // why the language is measured here, before the decoder is handed
+        // anything, and only when the prompt is actually going to be the
+        // table's: a switch off stays upstream's audio byte for byte.
+        let spokenLanguage = settings.initialPrompt.isEmpty
+            && pausePolicy.closesSentence
+            && !settings.showTimestamps
+            ? try measureLanguage(of: samples, nThreads: nThreads)
+            : nil
+        var effectiveSettings = settings
+        effectiveSettings.initialPrompt = Self.decoderPrompt(
+            userPrompt: settings.initialPrompt,
+            longPausesEndSentences: pausePolicy.closesSentence,
+            showsTimestamps: settings.showTimestamps,
+            spokenLanguage: spokenLanguage
+        )
+
+        let initialPromptTokenCount = effectiveSettings.initialPrompt.isEmpty
             ? 0
-            : context.tokenCount(text: settings.initialPrompt)
+            : context.tokenCount(text: effectiveSettings.initialPrompt)
         var params = Self.makeFullParams(
-            settings: settings,
+            settings: effectiveSettings,
             nThreads: nThreads,
             modelTextContext: context.nTextCtx,
             initialPromptTokenCount: initialPromptTokenCount
@@ -454,6 +473,46 @@ class WhisperEngine: TranscriptionEngine {
         )
     }
 
+    /// The language of the audio, measured **before** the decoder is given
+    /// anything.
+    ///
+    /// `whisper_full` normally learns the language inside the transcription, and
+    /// that answer arrives after the decoder has already been conditioned on its
+    /// prompt. whisper.cpp will instead read the language off the encoder and
+    /// return without decoding a single token when `detectLanguage` is set
+    /// (`libwhisper/whisper.cpp/src/whisper.cpp:6861`: `if (params.detect_language)
+    /// { return 0; }`), which is the only way to know the language *before* the
+    /// prompt is written. The price is one encoder pass over the audio the
+    /// decoder would have encoded anyway, measured on the captain's own
+    /// recordings in `WhisperPauseBoundaryPairingTests`
+    /// (`testTheCostOfALanguagePrePass`).
+    ///
+    /// An English-only model needs no pass at all: it cannot be multilingual, so
+    /// the language is `en` by construction — the same inference
+    /// `SpeechModelLanguageGate` makes. The decoding state is left free either
+    /// way, and `prepareForRecording()` builds the fresh one the transcription
+    /// itself uses, so nothing of this pass reaches the transcript.
+    private func measureLanguage(of samples: [Float], nThreads: Int) throws -> String? {
+        guard let context else { return nil }
+        guard context.isMultilingual else { return "en" }
+        defer { context.freeState() }
+        guard context.initState() else { throw TranscriptionError.contextInitializationFailed }
+
+        var params = WhisperFullParams()
+        params.strategy = .greedy
+        params.nThreads = Int32(nThreads)
+        // Detection only: whisper computes the mel, encodes, reads the language
+        // and returns. Nothing in this pass is transcribed, and `noTimestamps`
+        // stays at the engine's own setting so the mel and the encoder are the
+        // same shape they will be in the transcription.
+        params.detectLanguage = true
+        var cParams = params.toC()
+        try Task.checkCancellation()
+        guard context.full(samples: samples, params: &cParams) else { return nil }
+        try Task.checkCancellation()
+        return Self.reportedLanguage(context: context)
+    }
+
     /// The language of the utterance that was just decoded, measured inside the
     /// `whisper_full` call above.
     ///
@@ -563,6 +622,78 @@ class WhisperEngine: TranscriptionEngine {
         return false
     }
 
+    // MARK: - The decoder prompt
+
+    /// The decoder prompt a language gets when the user has set none.
+    ///
+    /// `initialPrompt` is one string and it belongs to the user; this is the
+    /// *default* that stands in for it, and it is chosen **by the language that
+    /// was spoken**, because a prompt that suits one language is wrong for
+    /// another: the switch's English side needs one at all (with no prompt the
+    /// switch on invents a fragment in the English control that the switch off
+    /// does not produce), and a Polish prompt on English audio pulls the decode
+    /// the wrong way.
+    ///
+    /// Only languages measured on the captain's own recordings have an entry. A
+    /// language with no entry gets **no** prompt, which is byte for byte what
+    /// this app sent before the table existed. The two entries and the reason
+    /// they are these two strings and not others are in
+    /// `WhisperPauseBoundaryPairingTests` and `fleet/data/fm-20260925-14/report.md`.
+    static func defaultDecoderPrompt(forLanguage language: String?) -> String {
+        switch language {
+        case "pl": return polishDefaultDecoderPrompt
+        case "en": return englishDefaultDecoderPrompt
+        default: return ""
+        }
+    }
+
+    /// Polish dictation with full stops and a question mark and **no commas**, in
+    /// his own register.
+    ///
+    /// Which Polish string this is was measured, not picked for looks: the
+    /// comma-heavy candidates and the English one all prime the decoder into
+    /// joining `pl-1`'s two clauses with a comma — "…inną drogą**,** bo tu
+    /// chodzi…" — which **trades away the very sentence boundary the switch exists
+    /// to gain** (`pl-1`: `win-words:NO(drogą.) boundary:NO(2->2)`), while this
+    /// one keeps it ("…inną drogą. Bo tu chodzi…", `boundary:yes(2->3)`) and keeps
+    /// `pl-2`'s "Open Super Whisper" and "Dodałem" as well. The tables are in
+    /// `WhisperPauseBoundaryPairingTests` and `fleet/data/fm-20260925-14/report.md`.
+    static let polishDefaultDecoderPrompt =
+        "Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu."
+
+    /// The English counterpart, for English audio and for an English-only model:
+    /// the same shape of ordinary dictation, and the arm whose English result is
+    /// the `-how -sentence +now +sentences` the captain accepted on 2026-09-25.
+    static let englishDefaultDecoderPrompt =
+        "Okay, one more time: I sent the report on Monday, but Anna hasn't replied. Can you check?"
+
+    /// The decoder prompt one transcription sends.
+    ///
+    /// The rule, in full, and the reason each clause is there:
+    ///
+    /// * **The user's own prompt always wins, in any language and on any
+    ///   switch.** A value the user set is a decision, and this app must not
+    ///   second-guess it — not with the table above, not with the language.
+    /// * **A switch off sends no default.** Off is upstream's audio byte for
+    ///   byte, and the prompt exists to serve the switch; without this clause an
+    ///   install that never turned the switch on would get a file that changed
+    ///   for no measured reason.
+    /// * **A switch on with no prompt of their own sends the default for the
+    ///   language spoken**, or nothing at all when that language has no entry.
+    /// * **Timestamp mode sends no default either.** With *Show Timestamps* on,
+    ///   the decoder is handed the untrimmed audio and no pause is measured
+    ///   (`performTranscription`), so the switch has nothing to serve there and a
+    ///   prompt would be a decode change with no measured benefit attached.
+    static func decoderPrompt(
+        userPrompt: String,
+        longPausesEndSentences: Bool,
+        showsTimestamps: Bool,
+        spokenLanguage: String?
+    ) -> String {
+        guard userPrompt.isEmpty, longPausesEndSentences, !showsTimestamps else { return userPrompt }
+        return defaultDecoderPrompt(forLanguage: spokenLanguage)
+    }
+
     /// The terminator the spoken language writes. Chinese, Japanese and Korean
     /// end a sentence with `。`; every other language whisper can transcribe
     /// uses `.`, and a language the engine could not measure gets `.` too.
```

`Utils/AppPreferences.swift (the switch default and its doc, the initialPrompt doc)`

```diff
diff --git a/OpenSuperWhisper/Utils/AppPreferences.swift b/OpenSuperWhisper/Utils/AppPreferences.swift
index d82f42b..4dd82c7 100644
--- a/OpenSuperWhisper/Utils/AppPreferences.swift
+++ b/OpenSuperWhisper/Utils/AppPreferences.swift
@@ -177,19 +177,37 @@ final class AppPreferences {
     /// segments is kept as real silence (up to `maxPause`) and closes the
     /// sentence in the assembled text when the decoder did not close it.
     ///
-    /// **Off by default, and that is a measurement rather than caution.** On his
-    /// own recordings the switch-on state fixes the Polish the complaint is about
-    /// (`pl-2`: "Ben super whisper" → "Open Super Whisper", "Dałem" → "Dodałem";
-    /// `pl-1`: "pieprzył" → "spieprzył"), but with the decoder prompt this app
-    /// sends — none: `initialPrompt` defaults to the empty string — it also makes
-    /// the English control hallucinate a fragment that the switch off does not
-    /// produce ("Basically, now it creates,. based, no, now it creates a
-    /// sentences…"), at every silence cap tried. Handing the decoder a deliberate
-    /// prompt removes that hallucination and keeps the Polish win (measured:
-    /// `WhisperPauseBoundaryMeasurementTests`), but that is the captain's
-    /// preference to set, not this branch's to set for him — so the switch ships
-    /// off, and flipping it is this one line.
-    @UserDefault(key: "longPausesEndSentences", defaultValue: false)
+    /// **On by default, and the English audio pays a measured two-word change for
+    /// it.** The switch fixes the Polish the complaint is about (`pl-1` gains its
+    /// sentence boundary and its verb; `pl-2` reads "Open Super Whisper" and
+    /// "Dodałem" where the switch off garbles both). With the decoder prompt this
+    /// app used to send — none — it did worse than that: the English control
+    /// invented a fragment ("based, no,") at every silence cap tried. The prompt
+    /// now sent for the language spoken removes that invention, and what is left
+    /// is the switch's own audio half: it is present in the arm that sends no
+    /// prompt at all and is identical across prompts, so **no prompt removes it**.
+    /// The captain was shown that with the numbers and accepted it on
+    /// **2026-09-25** — option (a), "pause fix everywhere, English takes a 2-word
+    /// change", `fleet/data/fm-20260925-14` — and the shipped configuration is
+    /// asserted against exactly that delta in `WhisperPauseBoundaryPairingTests`,
+    /// so widening it fails the suite instead of landing quietly. It is measured
+    /// on three recordings by one speaker, so it is a property of that pause and
+    /// not a claim about English in general.
+    ///
+    /// With no prompt of your own the decoder prompt is chosen by the language of
+    /// the dictation, and that costs one extra detect-only language pass over the
+    /// audio before each dictation — measured +1.34 s against a 3.5 s decode,
+    /// ≈ 38 % — paid only while this switch is on and no prompt is set; and on
+    /// pause-heavy English speech the switch changes two words against the switch
+    /// off ("Basically now it creates a sentences" where the switch off says
+    /// "Basically how it creates a sentence"), a change the captain accepted on
+    /// 2026-09-25 with the measurement in front of him, because no prompt removes
+    /// it and the Polish fix rides on the same silence.
+    ///
+    /// Off remains byte-for-byte the behaviour every earlier build had, and
+    /// flipping it back is this one line. The tables are in
+    /// `WhisperPauseBoundaryPairingTests` and `fleet/data/fm-20260925-14/report.md`.
+    @UserDefault(key: "longPausesEndSentences", defaultValue: true)
     var longPausesEndSentences: Bool
     
     @UserDefault(key: "temperature", defaultValue: 0.0)
@@ -198,6 +216,14 @@ final class AppPreferences {
     @UserDefault(key: "noSpeechThreshold", defaultValue: 0.6)
     var noSpeechThreshold: Double
     
+    /// The decoder context the user has set, or the empty string for none.
+    ///
+    /// Empty does **not** mean the decoder receives no prompt: when the switch
+    /// above is on, an install that has never set one sends the default its
+    /// language has (`WhisperEngine.decoderPrompt` — one measured entry for
+    /// Polish, one for English, nothing for a language nobody measured). A value
+    /// the user sets always wins over it, in any language, and this app never
+    /// writes one for them.
     @UserDefault(key: "initialPrompt", defaultValue: "")
     var initialPrompt: String
```

`Settings.swift, the pause tests (the deleted off-default pin), CaptainRecordingPauseBoundaryTests`

```diff
diff --git a/OpenSuperWhisper/Settings.swift b/OpenSuperWhisper/Settings.swift
index de0aece..38ca9dc 100644
--- a/OpenSuperWhisper/Settings.swift
+++ b/OpenSuperWhisper/Settings.swift
@@ -1516,6 +1516,12 @@ struct SettingsView: View {
                         // pause was never the problem — replacing it with a 0.1
                         // second breath is what made a sentence out of nothing,
                         // and the label says what the switch does instead.
+                        //
+                        // The second paragraph is the cost of the decision, in
+                        // the same words as `AppPreferences.longPausesEndSentences`
+                        // and Readme §8: the switch ships on, and the captain
+                        // accepted this much English change on 2026-09-25 rather
+                        // than a switch that does nothing on English.
                         HStack {
                             VStack(alignment: .leading, spacing: 2) {
                                 Text("Long Pauses End the Sentence")
@@ -1524,7 +1530,18 @@ struct SettingsView: View {
                                     "Whisper: a pause of "
                                         + "\(WhisperEngine.PauseBoundaryPolicy.restored.sentenceThreshold) s or longer "
                                         + "keeps its silence and closes the sentence, instead of dissolving "
-                                        + "into a breath that lets two thoughts merge"
+                                        + "into a breath that lets two thoughts merge. "
+                                        + "With no prompt of your own the decoder prompt is chosen by the "
+                                        + "language of the dictation, and that costs one extra detect-only "
+                                        + "language pass over the audio before each dictation — measured "
+                                        + "+1.34 s against a 3.5 s decode, \u{2248} 38 % — paid only while this "
+                                        + "switch is on and no prompt is set; and on pause-heavy English "
+                                        + "speech the switch changes two words against the switch off "
+                                        + "(\u{201C}Basically now it creates a sentences\u{201D} where the switch "
+                                        + "off says \u{201C}Basically how it creates a sentence\u{201D}), a "
+                                        + "change the captain accepted on 2026-09-25 with the measurement "
+                                        + "in front of him, because no prompt removes it and the Polish "
+                                        + "fix rides on the same silence."
                                 )
                                 .font(.caption)
                                 .foregroundColor(.secondary)
@@ -1815,9 +1832,12 @@ struct SettingsView: View {
                                     .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                             )
                         
-                        Text("Optional text to guide the model's transcription")
+                        Text("Optional text to guide the model's transcription. Leave it empty and the app "
+                            + "sends a short default written for the language it hears (Polish or English — "
+                            + "nothing for any other language), whenever Long Pauses End the Sentence is on.")
                             .font(.caption)
                             .foregroundColor(.secondary)
+                            .fixedSize(horizontal: false, vertical: true)
                     }
                 }
                 .padding()
diff --git a/OpenSuperWhisperTests/CaptainRecordingPauseBoundaryTests.swift b/OpenSuperWhisperTests/CaptainRecordingPauseBoundaryTests.swift
index 31b27db..6406c2c 100644
--- a/OpenSuperWhisperTests/CaptainRecordingPauseBoundaryTests.swift
+++ b/OpenSuperWhisperTests/CaptainRecordingPauseBoundaryTests.swift
@@ -62,9 +62,14 @@ final class WhisperPauseBoundaryMeasurementTests: XCTestCase {
     ///
     /// whisper's `initialPrompt` is decoder *context*, not a system prompt: it
     /// primes style and punctuation, so a useful one has to look like the text
-    /// wanted back. **The shipped app sends none** — `AppPreferences`'s default
-    /// is the empty string and his stored domain holds no value — so the empty
-    /// arm is today's app and every other arm here is a hypothetical setting.
+    /// wanted back. **The stored value ships empty** — `AppPreferences`'s default
+    /// is the empty string and his stored domain holds no value — but that is not
+    /// the same as the decoder being sent nothing: with the switch on, an empty
+    /// stored prompt means the `WhisperEngine.decoderPrompt` default for the
+    /// language the engine measures. This harness passes the policy *and* the
+    /// prompt in, so its empty-prompt arms below the switch-off ones measure
+    /// upstream's audio with no prompt at all, and the ones above them measure the
+    /// switch paired with the shipped language default.
     private struct PromptArm {
         let label: String
         let prompt: String
@@ -181,7 +186,9 @@ final class WhisperPauseBoundaryMeasurementTests: XCTestCase {
     /// His settings, as they reach the decoder: greedy, temperature 0, no-speech
     /// 0.6, blank suppression on, no timestamps. The pause policy and the decoder
     /// prompt are the arm, not the preference, so one process measures all of
-    /// them; the shipped app sends the empty prompt.
+    /// them; the stored prompt ships empty, which with the switch on means the
+    /// engine's own default for the language it measures (`WhisperEngine.decoderPrompt`)
+    /// and with the switch off means no prompt at all.
     private func captainSettings(initialPrompt: String) -> Settings {
         var settings = Settings()
         settings.showTimestamps = false
@@ -329,7 +336,9 @@ final class WhisperPauseBoundaryMeasurementTests: XCTestCase {
             let segments = try XCTUnwrap(vad.speechSegments(in: samples))
             reportPauses(recording: recording, samples: samples, segments: segments)
 
-            // Today's app: no decoder prompt (`initialPrompt` is empty).
+            // `initialPrompt` empty, as it ships: with the switch off that is
+            // upstream's audio and no prompt at all, and with the switch on it is
+            // the engine's own default for the language it measures.
             var switchOffText: String?
             var switchOnText: String?
             for arm in Self.arms {
@@ -361,8 +370,9 @@ final class WhisperPauseBoundaryMeasurementTests: XCTestCase {
                 )
             }
 
-            // The decoder prompts: the shipped app sends none, so the empty arm
-            // is the baseline every other arm is diffed against, word by word.
+            // The decoder prompts: the empty-prompt arm is the baseline every
+            // other arm is diffed against, word by word. With the switch on it is
+            // the engine's language default; the explicit arms below override it.
             let promptArms = recording.isEnglish ? Self.englishPromptArms : Self.polishPromptArms
             var baseline: String?
             for arm in promptArms {
diff --git a/OpenSuperWhisperTests/PauseBoundaryTests.swift b/OpenSuperWhisperTests/PauseBoundaryTests.swift
index 058d605..1e71c6c 100644
--- a/OpenSuperWhisperTests/PauseBoundaryTests.swift
+++ b/OpenSuperWhisperTests/PauseBoundaryTests.swift
@@ -233,36 +233,6 @@ final class WhisperPauseBoundaryTests: XCTestCase {
         XCTAssertTrue(Settings().longPausesEndSentences)
     }
 
-    /// An install that never touches the switch keeps upstream's stitching.
-    ///
-    /// The default is a measurement, not a shrug (see `PauseBoundaryPolicy`):
-    /// with the decoder prompt this app sends — none — turning the switch on
-    /// regresses the English control, so it ships off. This case is here so that
-    /// flipping it is a deliberate act with the reason in front of the reader.
-    func testAnInstallThatNeverTouchesTheSwitchKeepsUpstreamStitching() {
-        let suite = AppPreferences.defaults
-        let key = "longPausesEndSentences"
-        let saved = suite.object(forKey: key)
-        suite.removeObject(forKey: key)
-        defer {
-            if let saved {
-                suite.set(saved, forKey: key)
-            } else {
-                suite.removeObject(forKey: key)
-            }
-        }
-
-        XCTAssertFalse(Settings().longPausesEndSentences, "the shipped default is off")
-        XCTAssertFalse(
-            WhisperEngine.PauseBoundaryPolicy.from(settings: Settings()).closesSentence,
-            "…and the policy it produces is upstream's stitching, unchanged"
-        )
-        XCTAssertEqual(
-            WhisperEngine.PauseBoundaryPolicy.from(settings: Settings()),
-            .upstream
-        )
-    }
-
     // MARK: - Where the boundary lands
 
     func testAPauseBelongsAfterTheSegmentThatEndedBeforeIt() {
```

`OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift — the capture-harness repair, one hunk`

```diff
diff --git a/OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift b/OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift
index a82c1cd..f4ba027 100644
--- a/OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift
+++ b/OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift
@@ -504,8 +504,23 @@ final class SettingsLayoutSnapshotTests: XCTestCase {
     -> (bands: [Band], gaps: [Int], background: (Int, Int, Int), pixels: [UInt8]) {
         let pixels = try bitmap(image)
         let x = min(Self.probeColumn, image.width - 1)
-        // 4 pt below the top is page background: above the first card's padding.
-        let background = color(pixels, image, x, min(8, image.height - 1))
+        // The page background is sampled from the tab's own left page padding,
+        // and at three heights. Row 8 at the probe column — what this used to
+        // read — is page only in a capture of the *top* of a tab: in one scrolled
+        // to the bottom it is inside a card, so the "background" comes back as the
+        // card colour and then every gap in the image reads as a card and every
+        // card as a gap. That is how a correct tab was reported as cards drawn
+        // into each other ("gaps [1, 1]", background (30, 30, 30) — the card
+        // colour) once a longer caption moved the scroll geometry. The padding
+        // column is page for the whole height of a tab capture at any scroll
+        // offset; the three heights are there so a capture whose padding column is
+        // not page still falls back to the probe column's row 8.
+        let paddingColumn = max(0, Int(Self.pagePadding) / 4)
+        let paddingSamples = [min(8, image.height - 1), image.height / 2, max(0, image.height - 8)]
+            .map { color(pixels, image, paddingColumn, $0) }
+        let background = paddingSamples.dropFirst().allSatisfy { distance($0, paddingSamples[0]) <= 2 }
+            ? paddingSamples[0]
+            : color(pixels, image, x, min(8, image.height - 1))
         func isBackground(_ y: Int) -> Bool {
             distance(color(pixels, image, x, y), background) <= 3
         }
```

`Readme.md`

```diff
diff --git a/Readme.md b/Readme.md
index 2da56f3..3c42ec2 100644
--- a/Readme.md
+++ b/Readme.md
@@ -194,9 +194,22 @@ enough in English and is not enough in Polish, where the model's punctuation is
 
 **The switch is named for what it does, not for what was asked.** One line in **Settings → Transcription →
 Language Settings**: **Long Pauses End the Sentence** — "a pause of 0.6 s or longer keeps its silence and closes the
-sentence, instead of dissolving into a breath that lets two thoughts merge". Off is byte-for-byte the behaviour
-every earlier build had, and it ships **off by default** — not out of caution, but because the measurement below
-says the switch-on state regresses the English control while this app sends no decoder prompt.
+sentence, instead of dissolving into a breath that lets two thoughts merge". It ships **on by default**, paired with
+a decoder prompt chosen by the language of the dictation, and the price of that pairing is stated in the switch's own
+Settings copy and here in the same words rather than hidden:
+
+> With no prompt of your own the decoder prompt is chosen by the language of the dictation, and that costs one extra
+> detect-only language pass over the audio before each dictation — measured +1.34 s against a 3.5 s decode, ≈ 38 % —
+> paid only while this switch is on and no prompt is set; and on pause-heavy English speech the switch changes two
+> words against the switch off ("Basically now it creates a sentences" where the switch off says "Basically how it
+> creates a sentence"), a change the captain accepted on 2026-09-25 with the measurement in front of him, because no
+> prompt removes it and the Polish fix rides on the same silence.
+
+That is the captain's decision of **2026-09-25** taken on the measurement below — option (a), "pause fix everywhere,
+English takes a 2-word change" — and the shipped configuration is asserted against exactly it, Polish win present and
+no wider English delta, in `WhisperPauseBoundaryPairingTests`. Off is byte-for-byte the behaviour every earlier build
+had; a prompt set by hand always wins over the default, whatever the language; and a language nobody measured gets
+**no** prompt, which is what this app sent before the table existed.
 
 What it does, in the decoder's terms:
 
@@ -212,13 +225,14 @@ What it does, in the decoder's terms:
 
 **What the measurement said, including the parts that argue against it.** Measured on his own two Polish
 recordings and an English control, through this app's own decode path, with his settings and the decoder prompt
-this app actually sends — **none**.
+this app sent at the time — **none** (the pairing measurement reported further down is what changed that).
 
 * The same arm decoded twice is identical on all three recordings, so a before/after difference is the switch and
   not sampling. The transcripts the app stored for those recordings are reproduced **byte for byte by the
   switch-off arm with the instruction-shaped prompt an earlier brief attributed to his preferences** as the
   decoder prompt — which is evidence that *that* string was reaching the decoder when he dictated them, not of
-  anything the app ships: `initialPrompt` defaults to the empty string and his stored domain holds no value. (On
+  anything the app ships: `initialPrompt` defaults to the empty string and his stored domain holds no value. (The
+  decoder prompt a dictation *sends* is the language default described above, never a stored value; on
   `pl-2` the switch off with that string reads "Ben super whisper… Dałem drugi model"; with no prompt, "Będę super
   whisper… Dałem drugi model".)
 * The pause being kept is what fixes the Polish: `pl-2` comes back "**Open Super Whisper**" and "**Dodałem** drugi
@@ -229,17 +243,41 @@ this app actually sends — **none**.
 * **With no decoder prompt the English control regresses** — and not by two words, by inventing a fragment:
   "Basically, now it creates,. **based, no,** now it creates a sentences…" where the switch off is clean, **at
   every silence cap tried** (0.2 s, 0.4 s, 0.6 s, 0.8 s; 0.4 s and 0.6 s are worse still — "profound sense",
-  lowercase drift). That is why the switch ships off.
-* **A deliberate decoder prompt removes that regression and keeps the Polish win.** Four prompts were measured on
-  the same recordings with the same sampling — none, the instruction-shaped string the brief attributed to him,
-  and two candidates written as ordinary Polish dictation with full punctuation and no instruction — and each is
-  reported as a **counted word-level delta** against the no-prompt arm, because a prompt that fixes punctuation by
-  moving words is not a win. With the English counterpart of candidate 1 the control comes back clean ("Basically,
-  now it creates a sentences…", nothing invented); on `pl-2` the instruction-shaped string is the only arm that
-  recovers the words he said ("spój" → "swój", "forkę" → "fork", and it drops a spurious "I"); on `pl-1` every arm
-  keeps the words identical and only punctuation moves, where the two candidates add the commas but trade away a
-  sentence boundary. The app ships none of them: that is the captain's setting to choose, and this branch does not
-  set it for him.
+  lowercase drift). A deliberate decoder prompt is what removes that fragment; the switch does not ship without one.
+* **A deliberate decoder prompt removes that regression, and the switch now ships with one.** Four prompts were
+  measured on the same recordings with the same sampling — none, the instruction-shaped string the brief attributed
+  to him, and two candidates written as ordinary Polish dictation with full punctuation and no instruction — and each
+  is reported as a **counted word-level delta** against the no-prompt arm, because a prompt that fixes punctuation by
+  moving words is not a win. With a prompt in the language of the audio the invented fragment is gone; the
+  instruction-shaped string is not better on English than the shipped candidate (both `-2 +2`) and moves four words
+  instead of two on `pl-2`, so it is deliberately not a default — if he wants its individual recoveries ("spój" →
+  "swój", "forkę" → "fork", and it drops a spurious "I"), they belong in his own `initialPrompt`, which this fork
+  never writes for him.
+* **The prompt and the switch were then measured together, in both languages, and the answer is why there are two
+  strings and not one.** Crossing every prompt with every language on his own three recordings
+  (`WhisperPauseBoundaryPairingTests`; tables in `fleet/data/fm-20260925-14/report.md`) shows a prompt that suits one
+  language is damage in the other: a Polish prompt on English audio brings the fragments back and splits the control
+  into twelve pieces (`-how -sentence +creates +it +no +now +now +sentences`, seven of them two words or shorter, and
+  with the second Polish candidate Polish words leak into the English text — "Aż to add feature… Nooo…"), an English
+  prompt on Polish audio costs `pl-1` its boundary and hyphenates `pl-2`'s word ("fork-a"). So the default is keyed to
+  the language the engine measures, and the Polish entry is the **comma-free** candidate: the comma-heavy ones prime
+  the decoder into joining `pl-1`'s clauses with a comma and **trade away the sentence boundary the switch exists to
+  gain** ("…inną drogą**,** bo tu chodzi…", two sentences — the switch-off count), while the comma-free one keeps it
+  ("…inną drogą. Bo tu chodzi…", three) and keeps `pl-2`'s "Open Super Whisper" and "Dodałem". The English entry is
+  the arm whose residue is the two words below.
+* **No prompt fixes the English audio half, and that was the captain's call to make.** With the switch on, the English
+  control is never word-identical to the switch off — not with any of the six prompts, not with none: the shortest
+  difference is `-how -sentence +now +sentences`, and it is there in the arm that sends no prompt at all, identical
+  across two different prompts and unmoved by the cap (`0.2…0.8 s`). It is what keeping the real pause does to the
+  decode, so the choice was the switch with those two words or no switch. He took the switch on **2026-09-25**, and
+  the criterion test asserts exactly that delta, so a future change that quietly widens it fails the suite.
+* **What the pairing costs.** The language has to be known *before* the prompt is chosen, which this app's engine can
+  only do with whisper.cpp's detect-only pass (`detect_language`: mel + encoder, no token). Measured on his own audio
+  with the app's own context parameters, that pass is **1343/1314 ms** against a **3522/3391 ms** decode on `pl-1`,
+  **1336/1351 ms** against **3560/3813 ms** on `pl-2` and **1346/1348 ms** against **3548/3509 ms** on the English
+  control — about **38 %** of every dictation whose switch is on and whose prompt is empty, because the encoder always
+  processes the fixed 30 s window. It was accurate on all three (the pre-pass's language equals the decode's own), and
+  an English-only model pays nothing: it cannot be multilingual, so it is `en` by construction.
 * **The threshold was 0.5 s and the measurement removed it.** On `pl-1` a pause the VAD measured at 0.52 s falls
   inside "…o to, że żeś | spieprzył po całości", and 0.5 s closed the sentence there — "że żeś. spieprzył" (the
   same wrong break appears at 0.4 s). On the app's own numbers every pause he talks across is 0.52 s or below and
@@ -288,10 +326,15 @@ that builds with the debug dylib disabled, signs, and can run the unit suite *an
 `Scripts/build-native.sh` builds the two vendored engines in the one order that works (llama.cpp installs the
 single ggml package that whisper.cpp then links against). Crew worktrees build under a different bundle id, and
 each test process gets its own preference store, so parallel development cannot poison the app someone is using.
-The suite on the merged tip is **420 tests: 367 passing, 0 failing, 53 skipped**, where the skips are all
-environmental: 50 gated on this machine's input sources or on Accessibility automation, 2 behind
-`OSW_TEST_TURBO_MODEL` and 1 behind a microphone opt-in. That 50 is why the daily delivery path is the least
-covered part of the suite.
+The suite on this tree is **473 tests** — the captain's-recording measurement cases among them, which is why it is
+larger than CI's: they skip wherever his recordings or a multilingual model are absent. Its last full run here stood
+at **418 passing, 1 failing, 54 skipped**, the failure being the Settings snapshot capture harness described in
+`fleet/data/fm-20260925-14/report.md` (its detector read the page background from a row that is inside a card in a
+capture scrolled to the bottom); that harness is repaired and was verified green on its own afterwards
+(`SettingsLayoutSnapshotTests`, 7/7). The clean full suite on the merged tip is the fleet's record, not this
+paragraph's. The rest of the skips are environmental: 50 gated on this machine's input sources or on Accessibility
+automation, 2 behind `OSW_TEST_TURBO_MODEL` and 1 behind a microphone opt-in. That 50 is why the daily delivery path
+is the least covered part of the suite.
 
 ### What is unchanged
```

`OpenSuperWhisperTests/DecoderPromptDefaultTests.swift` — new file, verbatim

```swift
import XCTest

@testable import OpenSuperWhisper

/// The two defaults the pairing measurement changed: the switch, and the decoder
/// prompt that is chosen by the language spoken.
///
/// These are the cases that make flipping a default a deliberate act. The
/// measurement they rest on is `WhisperPauseBoundaryPairingTests` (his own
/// recordings, the app's own decode path) and its tables are in
/// `fleet/data/fm-20260925-14/report.md`.
final class DecoderPromptDefaultTests: XCTestCase {

    // MARK: - The rule

    /// A prompt the user set is a decision, and nothing overrides it.
    func testTheUsersOwnPromptWinsInEveryLanguageAndOnEitherSwitch() {
        let theirs = "Zażółć gęślą jaźń."
        XCTAssertEqual(
            WhisperEngine.decoderPrompt(
                userPrompt: theirs,
                longPausesEndSentences: true,
                showsTimestamps: false,
                spokenLanguage: "pl"
            ),
            theirs
        )
        XCTAssertEqual(
            WhisperEngine.decoderPrompt(
                userPrompt: theirs,
                longPausesEndSentences: false,
                showsTimestamps: false,
                spokenLanguage: "en"
            ),
            theirs
        )
        XCTAssertEqual(
            WhisperEngine.decoderPrompt(
                userPrompt: theirs,
                longPausesEndSentences: true,
                showsTimestamps: false,
                spokenLanguage: nil
            ),
            theirs,
            "a language the engine could not measure must not replace what the user set"
        )
    }

    /// With the switch off the app is upstream byte for byte: no default prompt
    /// may reach the decoder. Without this, an install that never turned the
    /// switch on would get a file that changed for no measured reason.
    func testTheSwitchOffSendsNoDefaultEvenWithNoPromptOfTheUsersOwn() {
        for language in ["pl", "en", "de", nil] as [String?] {
            XCTAssertEqual(
                WhisperEngine.decoderPrompt(
                    userPrompt: "",
                    longPausesEndSentences: false,
                    showsTimestamps: false,
                    spokenLanguage: language
                ),
                "",
                "language \(language ?? "none")"
            )
        }
    }

    /// The default is chosen by the language spoken: the two measured languages
    /// get the two measured prompts, and nothing else gets anything.
    func testTheDefaultIsTheOneItsLanguageHas() {
        XCTAssertEqual(
            WhisperEngine.decoderPrompt(
                userPrompt: "", longPausesEndSentences: true, showsTimestamps: false, spokenLanguage: "pl"
            ),
            WhisperEngine.polishDefaultDecoderPrompt
        )
        XCTAssertEqual(
            WhisperEngine.decoderPrompt(
                userPrompt: "", longPausesEndSentences: true, showsTimestamps: false, spokenLanguage: "en"
            ),
            WhisperEngine.englishDefaultDecoderPrompt
        )
        for language in ["de", "fr", "es", "zh", "auto", "", "PL", "polish", nil] as [String?] {
            XCTAssertEqual(
                WhisperEngine.decoderPrompt(
                    userPrompt: "", longPausesEndSentences: true, showsTimestamps: false, spokenLanguage: language
                ),
                "",
                "unmeasured language \(language ?? "none") must send no prompt"
            )
        }
    }

    /// The table is the measurement's, not a preference: each entry is ordinary
    /// dictation in that language, with no instruction in it. The
    /// instruction-shaped string the earlier brief attributed to his preferences
    /// is deliberately absent — this project documented that shape as a
    /// hallucination trigger, and the brief forbids shipping it as a default.
    func testTheDefaultsAreDictationAndNotInstruction() {
        let defaults = [
            "pl": WhisperEngine.polishDefaultDecoderPrompt,
            "en": WhisperEngine.englishDefaultDecoderPrompt,
        ]
        for (language, prompt) in defaults {
            XCTAssertFalse(prompt.isEmpty, language)
            XCTAssertFalse(
                prompt.lowercased().contains("you are") || prompt.lowercased().contains("your role"),
                "\(language): an instruction is not a decoder prompt — \(prompt)"
            )
            XCTAssertFalse(
                prompt.lowercased().contains("transcri") || prompt.lowercased().contains("do not change"),
                "\(language): meta-commentary leaked into the default — \(prompt)"
            )
        }
        XCTAssertEqual(
            WhisperEngine.defaultDecoderPrompt(forLanguage: "pl"),
            "Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu."
        )
        XCTAssertEqual(
            WhisperEngine.defaultDecoderPrompt(forLanguage: "en"),
            "Okay, one more time: I sent the report on Monday, but Anna hasn't replied. Can you check?"
        )
    }

    // MARK: - The switch, as it ships

    /// A new install gets the switch **on**, and that is the captain's decision
    /// on a measurement rather than a preference: paired with the language-aware
    /// default prompt the switch keeps the Polish win, and what it costs the
    /// English control is exactly the two words he accepted on 2026-09-25
    /// (`WhisperPauseBoundaryPairingTests.acceptedEnglishChange`); off it leaves
    /// the Polish complaint in place.
    func testANewInstallGetsTheSwitchOn() {
        let suite = AppPreferences.defaults
        let key = "longPausesEndSentences"
        let saved = suite.object(forKey: key)
        suite.removeObject(forKey: key)
        defer {
            if let saved {
                suite.set(saved, forKey: key)
            } else {
                suite.removeObject(forKey: key)
            }
        }

        XCTAssertTrue(Settings().longPausesEndSentences, "the shipped default is on")
        XCTAssertEqual(
            WhisperEngine.PauseBoundaryPolicy.from(settings: Settings()),
            .restored,
            "…and the policy it produces is the fix"
        )
    }

    /// A new install gets **no** stored prompt: the language-aware default is a
    /// default, not a value written into anyone's preferences. The captain's own
    /// domain is never touched by the app for it.
    func testANewInstallGetsNoStoredPrompt() {
        let suite = AppPreferences.defaults
        let key = "initialPrompt"
        let saved = suite.object(forKey: key)
        suite.removeObject(forKey: key)
        defer {
            if let saved {
                suite.set(saved, forKey: key)
            } else {
                suite.removeObject(forKey: key)
            }
        }

        XCTAssertEqual(AppPreferences.shared.initialPrompt, "", "the stored prompt stays empty")
        XCTAssertEqual(Settings().initialPrompt, "", "…and the dictation reads that empty value")
        XCTAssertEqual(
            WhisperEngine.decoderPrompt(
                userPrompt: Settings().initialPrompt,
                longPausesEndSentences: Settings().longPausesEndSentences,
                showsTimestamps: false,
                spokenLanguage: "pl"
            ),
            WhisperEngine.polishDefaultDecoderPrompt,
            "the prompt a new install actually sends comes from the table, not from its domain"
        )
    }

    /// Reading the value must not write it: a default that stores itself would
    /// take the captain's own install from "never opened Settings" to "has a
    /// preference", and then his Settings field would show text he never typed.
    func testReadingThePromptDoesNotWriteItIntoTheDomain() {
        let suite = AppPreferences.defaults
        let key = "initialPrompt"
        let saved = suite.object(forKey: key)
        suite.removeObject(forKey: key)
        defer {
            if let saved {
                suite.set(saved, forKey: key)
            } else {
                suite.removeObject(forKey: key)
            }
        }

        _ = Settings().initialPrompt
        _ = AppPreferences.shared.initialPrompt
        XCTAssertNil(
            suite.object(forKey: key),
            "nothing may have been written to the user's preferences"
        )
    }

    /// Timestamp mode hands the decoder the untrimmed audio and measures no pause,
    /// so the switch has nothing to serve there: no default prompt is sent, and
    /// the mode is byte for byte what it always was.
    func testTimestampModeSendsNoDefault() {
        for language in ["pl", "en"] {
            XCTAssertEqual(
                WhisperEngine.decoderPrompt(
                    userPrompt: "",
                    longPausesEndSentences: true,
                    showsTimestamps: true,
                    spokenLanguage: language
                ),
                "",
                "language \(language)"
            )
        }
    }
}
```

`OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift` — new file, verbatim

```swift
import Foundation
import XCTest

@testable import OpenSuperWhisper

/// fm-20260925-14: does a deliberate decoder prompt **pair** with "long pauses
/// end the sentence"?
///
/// This harness answered that question on the captain's own recordings and got
/// **refused with evidence**: with the switch on the English control is never
/// word-identical to the switch-off/none control, and the shortest difference any
/// prompt reaches is two words (`-how -sentence +now +sentences`), present in the
/// arm that sends no prompt at all. The captain was given the measurement and
/// chose **option (a)** — "pause fix everywhere, English takes a 2-word change" —
/// accepted on **2026-09-25** with those numbers in front of him. So the switch
/// ships on with a decoder prompt chosen by the language spoken (the detect-only
/// pre-pass), and the change this file now pins is the accepted one rather than a
/// clean English control: the criterion case at the bottom asserts the two-word
/// English delta exactly, so a future change that quietly widens it fails.
///
/// The measurement itself is unchanged: the switch on with a deliberate decoder
/// prompt as the arm, and the **switch-off/none** arm — the app as it shipped
/// before this decision — as the baseline every arm is diffed against, word by
/// word. A prompt that fixes the punctuation by changing the words is not a win,
/// so the deltas are words, not marks.
///
/// Opt-in twice over, exactly like the pause measurement: `OSW_TEST_CAPTAIN_RECORDINGS`
/// has to name the directory and a multilingual model has to be available. With
/// either missing the cases skip, which is the state CI runs in.
///
/// The arms, per recording:
///
/// * `off / none` — the control: today's app. Everything else is a delta against it.
/// * `on / none`, `on / attributed`, `on / c1 (pl)`, `on / c2 (pl)`,
///   `on / c3 (pl, no commas)`, `on / c1 EN` — the switch on with each prompt.
/// * `off / attributed`, `off / c1 (pl)`, `off / c1 EN` — the prompt on its own,
///   so a change can be attributed to the prompt rather than the switch.
/// * `on / none`, decoded twice, as the determinism anchor.
///
/// **On the shipped engine an empty stored prompt is not "no prompt".** With the
/// switch on and no prompt of the user's own, `performTranscription` measures the
/// language and sends the default that language has, so the `none` column of a
/// switch-**on** arm in these tables *is* that default (Polish: `c3 (pl)`;
/// English: `c1 EN`), and the arms differ only in what reached the decoder. The
/// switch-**off** control is unaffected — off sends no prompt at all — which is
/// why it is still the baseline every arm is diffed against.
///
/// Everything judgemental (which prompt is better, how wide an arm's English
/// delta is) is **reported**, not asserted; the assertions are the structural
/// ones — the engine's transcript is the assembler's output and no long pause is
/// left inside a sentence on an `on` arm — plus the one configuration the app
/// actually ships, whose accepted English delta is pinned exactly.
final class WhisperPauseBoundaryPairingTests: XCTestCase {

    // MARK: - His recordings

    private struct CaptainRecording {
        let label: String
        let fileName: String
        /// The Polish win the brief states, exactly: what has to survive for a
        /// pairing to pass on this recording. `nil` on the English control, whose
        /// criterion is the accepted two-word change instead — see
        /// `acceptedEnglishChange`.
        let win: Win?
        /// The transcript the app itself stored for it — the check that this
        /// harness really is the app's own decode path.
        let storedTranscript: String
    }

    /// The words the brief requires a pairing to keep.
    private struct Win {
        /// Substrings that must appear. Case-sensitive on purpose: `Dodałem` is
        /// the word the dissolved pause cost, and `dałem` is the word it left.
        let mustContain: [String]
        /// The arm has to read one more sentence than the switch-off/none
        /// control: `pl-1` gains the boundary at the long pause.
        let mustGainASentence: Bool
    }

    private static let recordings = [
        CaptainRecording(
            label: "pl-1 (12.1 s)",
            fileName: "5C68BFAC-5EC8-45CC-8239-3B5659272C1A.wav",
            win: Win(mustContain: ["drogą."], mustGainASentence: true),
            storedTranscript: "Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. "
                + "Bo tu chodzi o to że żeś pieprzył po całości."
        ),
        CaptainRecording(
            label: "pl-2 (23.3 s)",
            fileName: "B2EA9010-97C9-40AB-A7A2-746323A45297.wav",
            win: Win(mustContain: ["Open Super Whisper", "Dodałem"], mustGainASentence: false),
            storedTranscript: "Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. "
                + "Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku."
        ),
        CaptainRecording(
            label: "en control (33.0 s)",
            fileName: "D92A0B10-EB8D-4D47-80B9-A9F3A88C112F.wav",
            win: nil,
            storedTranscript: "Also add feature to ignore pauses. Basically how it creates a sentence without "
                + "a sense because of my long pauses. The pauses need to be ignored."
        ),
    ]

    // MARK: - The decoder prompts, as arms

    private struct PromptArm {
        let label: String
        let prompt: String
    }

    /// The instruction-shaped string the earlier brief reported finding in his
    /// preferences. It is **not** in the app (no commit ever contained it, the
    /// code default is the empty string) and this brief forbids shipping it as a
    /// default however well it scores, because it is exactly the shape this
    /// project documented as a hallucination trigger. It is measured here
    /// because it is one of the four arms the brief names.
    private static let attributedPrompt =
        "You are a transcriber. Your role is just to clean up the text and make it look pretty and attractive. "
        + "Do not change the sense of the sentences."

    /// Ordinary Polish dictation with full punctuation, a proper noun, a comma, a
    /// colon and a question mark — no instruction and no meta-commentary.
    private static let candidateOne = "Dobra, jeszcze raz: wysłałem raport w poniedziałek, ale Anna nie "
        + "odpowiedziała. Możesz to sprawdzić?"
    private static let candidateTwo = "Tak, zgadza się. Kiedy? Nie wiem, ale sprawdzę to jutro."

    /// The English counterpart of candidate one, for the English control.
    private static let candidateOneEnglish = "Okay, one more time: I sent the report on Monday, but Anna hasn't "
        + "replied. Can you check?"

    /// **The knock-out probe for the comma hypothesis.** Candidate 1 and 2 are
    /// comma-heavy, and on `pl-1` both *add* commas and merge the boundary the
    /// switch had gained. The attributed string does the opposite — it loses the
    /// commas — so if the attributed arm is the only one that keeps `pl-1`'s
    /// boundary, the cause may be comma priming rather than instruction. This
    /// prompt is text-shaped Polish dictation with full stops and questions and
    /// **no commas at all**, so the two explanations can be told apart.
    private static let candidateThree = "Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? "
        + "Nie ma problemu."

    private static let promptArms: [PromptArm] = [
        PromptArm(label: "none (the shipped default)", prompt: ""),
        PromptArm(label: "attributed (instruction-shaped)", prompt: attributedPrompt),
        PromptArm(label: "c1 (pl)", prompt: candidateOne),
        PromptArm(label: "c2 (pl)", prompt: candidateTwo),
        PromptArm(label: "c3 (pl, no commas)", prompt: candidateThree),
        PromptArm(label: "c1 EN", prompt: candidateOneEnglish),
    ]

    /// The key every arm is diffed against: today's app, byte for byte the audio
    /// every earlier build decoded.
    private static let controlLabel = "off / none (control)"

    /// The English change the captain accepted on **2026-09-25** with the
    /// measurement in front of him — option (a), "pause fix everywhere, English
    /// takes a 2-word change".
    ///
    /// With the switch on the English control reads "Basically **now** it creates
    /// **a sentences**" where the switch off reads "Basically **how** it creates
    /// **a sentence**". The change is the switch's own audio half rather than the
    /// prompt's: it is there in the arm that sends no prompt at all, it is
    /// identical for two different prompts, and none of the six prompts moves it —
    /// which is exactly why the choice was this and not a cleaner control. The
    /// shipped configuration is asserted against **exactly** these two words, so a
    /// future change that widens the English damage fails the suite instead of
    /// passing it quietly.
    private static let acceptedEnglishChange = (
        removed: ["how", "sentence"],
        added: ["now", "sentences"]
    )

    /// The policies. The control is upstream's audio (`maxPause: 0`, the 0.1 s of
    /// zeros) with the shipped threshold and tolerance kept so the *junctions*
    /// are measurable on it too — the same construction the pause measurement
    /// used, so these tables and its tables are directly comparable.
    private static let controlPolicy = WhisperEngine.PauseBoundaryPolicy(
        maxPause: WhisperEngine.PauseBoundaryPolicy.upstream.maxPause,
        minPause: WhisperEngine.PauseBoundaryPolicy.upstream.minPause,
        sentenceThreshold: WhisperEngine.PauseBoundaryPolicy.restored.sentenceThreshold,
        boundaryTolerance: WhisperEngine.PauseBoundaryPolicy.restored.boundaryTolerance,
        closesSentence: false
    )

    private static let switchOnPolicy = WhisperEngine.PauseBoundaryPolicy.restored

    // MARK: - Fixtures

    private func recordingsDirectory() throws -> URL {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["OSW_TEST_CAPTAIN_RECORDINGS"], !path.isEmpty else {
            throw XCTSkip(
                "OSW_TEST_CAPTAIN_RECORDINGS is not set: the captain's recordings are not on this machine"
            )
        }
        let directory = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw XCTSkip("OSW_TEST_CAPTAIN_RECORDINGS points at no directory: \(path)")
        }
        return directory
    }

    /// His settings, as they reach the decoder. The pause policy and the decoder
    /// prompt are the arm, not the preference, so one process measures all of
    /// them.
    private func captainSettings(initialPrompt: String, longPausesEndSentences: Bool) -> Settings {
        var settings = Settings()
        settings.showTimestamps = false
        settings.temperature = 0
        settings.noSpeechThreshold = 0.6
        settings.suppressBlankAudio = true
        settings.useBeamSearch = false
        settings.initialPrompt = initialPrompt
        settings.longPausesEndSentences = longPausesEndSentences
        return settings
    }

    /// Whisper's own cleaning, as `performTranscription` applies it.
    private func cleaned(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[MUSIC]", with: "")
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sentences(_ text: String) -> [String] {
        let terminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if terminators.contains(character) {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { result.append(sentence) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { result.append(tail) }
        return result
    }

    private func wordCount(_ sentence: String) -> Int {
        sentence.split(whereSeparator: { $0.isWhitespace }).count
    }

    private func punctuationCounts(_ text: String) -> String {
        let marks: [Character] = [".", ",", "?", "!", ":", ";", "…", "—", "\""]
        return marks
            .map { mark in "\(mark)\(text.filter { $0 == mark }.count)" }
            .joined(separator: " ")
    }

    /// The words in `text` that are not in `baseline` and the ones that are,
    /// counted so a repeated word counts once per repetition. Punctuation and
    /// case are ignored: this is about which *words* an arm moved.
    private func wordDelta(baseline: String, text: String) -> (removed: [String], added: [String]) {
        func words(_ value: String) -> [String] {
            value.lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
        }

        var counts: [String: Int] = [:]
        for word in words(baseline) { counts[word, default: 0] += 1 }
        for word in words(text) { counts[word, default: 0] -= 1 }

        let removed = counts.filter { $0.value > 0 }.sorted { $0.key < $1.key }
            .flatMap { Array(repeating: $0.key, count: $0.value) }
        let added = counts.filter { $0.value < 0 }.sorted { $0.key < $1.key }
            .flatMap { Array(repeating: $0.key, count: -$0.value) }
        return (removed, added)
    }

    private func wordsEqual(_ lhs: String, _ rhs: String) -> Bool {
        let delta = wordDelta(baseline: lhs, text: rhs)
        return delta.removed.isEmpty && delta.added.isEmpty
    }

    /// How many long pauses the transcript ran straight through, using the
    /// engine's own junction rule rather than a copy of it.
    private func junctionsLeftOpen(
        in assembly: String,
        texts: [String],
        starts: [Int64],
        endCentiseconds: [Int64],
        pauses: [WhisperEngine.StitchedPause],
        policy: WhisperEngine.PauseBoundaryPolicy,
        terminator: String
    ) -> Int {
        let junctions = WhisperEngine.pauseJunctions(
            decodedStartsCentiseconds: starts,
            decodedEndCentiseconds: endCentiseconds,
            pauses: pauses,
            threshold: policy.sentenceThreshold,
            tolerance: policy.boundaryTolerance
        )
        var open = 0
        for index in junctions {
            let upTo = cleaned(
                WhisperEngine.assembleSegmentTexts(Array(texts[0...index]), showTimestamps: false)
            )
            guard assembly.hasPrefix(upTo) else {
                open += 1
                continue
            }
            let after = assembly.dropFirst(upTo.count)
            if !(WhisperEngine.endsSentence(upTo) || after.hasPrefix(terminator)) {
                open += 1
            }
        }
        return open
    }

    // MARK: - The measurement

    private struct ArmResult {
        let arm: String
        let prompt: String
        let text: String
        let sentences: Int
        let milliseconds: Int
        /// The language this arm's own decode measured — what the shipped path's
        /// pre-pass is compared against.
        let languageAtDecode: String?
    }

    func testTheSwitchPairedWithADecoderPrompt() async throws {
        let directory = try recordingsDirectory()
        let modelURL = try TestFixtures.multilingualModel()
        let vadModelPath = try XCTUnwrap(
            WhisperEngine.vadModelPath,
            "Silero VAD model must be bundled with the app"
        )

        let engine = WhisperEngine(modelPath: modelURL.path)
        try await engine.initialize()
        let vad = try XCTUnwrap(MyWhisperVadContext(modelPath: vadModelPath))

        TestFixtures.report("[pair] ============================================================")
        TestFixtures.report("[pair] model \(modelURL.path)")
        TestFixtures.report("[pair] vad \(vadModelPath)")
        TestFixtures.report(
            "[pair] the control is the switch off with no prompt: upstream's 0.1 s of zeros at every pause. "
                + "Every arm below is diffed against it, word by word."
        )
        TestFixtures.report(
            "[pair] on a switch-on arm an empty stored prompt sends the engine's own default for the language it "
                + "measures (pl: '\(WhisperEngine.defaultDecoderPrompt(forLanguage: "pl"))'; "
                + "en: '\(WhisperEngine.defaultDecoderPrompt(forLanguage: "en"))') — the `none` rows of this "
                + "run's tables are that default, and the switch-off control above sends nothing at all."
        )

        // What each (recording, on-arm) produced, for the verdict table at the end.
        var onTexts: [String: [String: String]] = [:]
        var controlSentences: [String: Int] = [:]
        var controlTexts: [String: String] = [:]

        for recording in Self.recordings {
            let audioURL = directory.appendingPathComponent(recording.fileName)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw XCTSkip("\(recording.fileName) is not in \(directory.path)")
            }

            let converted = try await engine.convertAudioToPCM(fileURL: audioURL)
            let samples = try XCTUnwrap(converted, "\(recording.fileName) did not convert to PCM")
            let segments = try XCTUnwrap(vad.speechSegments(in: samples))
            reportPauses(recording: recording, samples: samples, segments: segments)

            var results: [ArmResult] = []

            // 1. The control: today's app, byte for byte.
            let control = try await measure(
                engine: engine,
                audioURL: audioURL,
                policy: Self.controlPolicy,
                arm: Self.controlLabel,
                prompt: "",
                recording: recording,
                samples: samples,
                segments: segments,
                baseline: nil,
            )
            controlTexts[recording.label] = control.text
            controlSentences[recording.label] = control.sentences
            results.append(control)
            TestFixtures.report(
                "[pair] \(recording.label) switch-off/none text == the app's stored transcript: "
                    + "\(control.text == recording.storedTranscript)"
            )

            // 2. The switch on with each prompt.
            var on: [String: String] = [:]
            for arm in Self.promptArms {
                let result = try await measure(
                    engine: engine,
                    audioURL: audioURL,
                    policy: Self.switchOnPolicy,
                    arm: "on / \(arm.label)",
                    prompt: arm.prompt,
                    recording: recording,
                    samples: samples,
                    segments: segments,
                    baseline: control.text,
                )
                on[arm.label] = result.text
                results.append(result)
            }
            onTexts[recording.label] = on

            // 3. The prompt on its own, switch off: so a change on an `on` arm
            //    can be attributed to the prompt rather than to the switch.
            for arm in Self.promptArms where !arm.prompt.isEmpty {
                results.append(
                    try await measure(
                        engine: engine,
                        audioURL: audioURL,
                        policy: Self.controlPolicy,
                        arm: "off / \(arm.label)",
                        prompt: arm.prompt,
                        recording: recording,
                        samples: samples,
                        segments: segments,
                        baseline: control.text,
                    )
                )
            }

            // 4. The determinism anchor: whisper is seeded by its own parameters,
            //    so the same arm twice has to be the same text, or a difference
            //    above is sampling rather than the arm.
            let repeatResult = try await measure(
                engine: engine,
                audioURL: audioURL,
                policy: Self.switchOnPolicy,
                arm: "on / none (repeated)",
                prompt: "",
                recording: recording,
                samples: samples,
                segments: segments,
                baseline: control.text,
            )
            results.append(repeatResult)
            let switchOnNone = on["none (the shipped default)"] ?? ""
            TestFixtures.report(
                "[pair] \(recording.label) the same arm twice is identical: "
                    + "\(repeatResult.text == switchOnNone)"
            )

            // 5. The arm under test, reported as one line per recording so the
            //    verdict can be read without the tables.
            reportVerdict(
                recording: recording,
                control: control.text,
                controlSentences: control.sentences,
                on: on
            )

            TestFixtures.report(
                "[pair] \(recording.label) arms decoded: \(results.count) | "
                    + "slowest \(results.map(\.milliseconds).max() ?? 0) ms"
            )
        }

        // The pairing table: every (Polish prompt, English prompt) configuration
        // the app could ship, judged on the brief's own criterion.
        reportConfigurationTable(onTexts: onTexts, controlTexts: controlTexts, controls: controlSentences)
    }

    /// The Polish win and the English cleanliness, per recording, in one place.
    private func reportVerdict(
        recording: CaptainRecording,
        control: String,
        controlSentences: Int,
        on: [String: String]
    ) {
        TestFixtures.report("[pair] ------------------------------------------------------------")
        for (label, text) in on.sorted(by: { $0.key < $1.key }) {
            let delta = wordDelta(baseline: control, text: text)
            let read = sentences(text)
            var flags: [String] = []
            if let win = recording.win {
                let missing = win.mustContain.filter { !text.contains($0) }
                flags.append(missing.isEmpty ? "win-words:yes" : "win-words:NO(\(missing.joined(separator: ",")))")
                if win.mustGainASentence {
                    flags.append(
                        read.count > controlSentences
                            ? "boundary:yes(\(controlSentences)->\(read.count))"
                            : "boundary:NO(\(controlSentences)->\(read.count))"
                    )
                }
            } else {
                let clean = delta.removed.isEmpty && delta.added.isEmpty
                flags.append(clean ? "english-clean:yes" : "english-clean:NO")
            }
            TestFixtures.report(
                "[pair] \(recording.label) | \(label) | sentences \(read.count) | "
                    + "punctuation \(punctuationCounts(text)) | words -\(delta.removed.count) +\(delta.added.count) "
                    + "| \(flags.joined(separator: " "))"
            )
        }
        TestFixtures.report("[pair] ------------------------------------------------------------")
    }

    /// The decision table the brief asks for: for every pair of (Polish prompt,
    /// English prompt) that could ship, does the English control stay clean **and**
    /// the Polish win survive?
    private func reportConfigurationTable(
        onTexts: [String: [String: String]],
        controlTexts: [String: String],
        controls: [String: Int]
    ) {
        let polishLabels = ["none (the shipped default)", "attributed (instruction-shaped)", "c1 (pl)",
                            "c2 (pl)", "c3 (pl, no commas)", "c1 EN"]
        let englishLabels = ["none (the shipped default)", "attributed (instruction-shaped)", "c1 (pl)",
                             "c2 (pl)", "c3 (pl, no commas)", "c1 EN"]
        let englishControl = Self.recordings.first { $0.win == nil }!
        let polishRecordings = Self.recordings.filter { $0.win != nil }

        TestFixtures.report("[pair] ===================== THE PAIRING TABLE =====================")
        TestFixtures.report(
            "[pair] pl prompt × en prompt | english control words vs control | pl-1 boundary | pl-2 words | verdict"
        )
        for polishLabel in polishLabels {
            for englishLabel in englishLabels {
                let englishText = onTexts[englishControl.label]?[englishLabel] ?? ""
                let englishControlText = controlTexts[englishControl.label] ?? ""
                let englishDelta = wordDelta(baseline: englishControlText, text: englishText)
                let englishClean = englishDelta.removed.isEmpty && englishDelta.added.isEmpty

                var polishPass = true
                var columns: [String] = []
                for recording in polishRecordings {
                    guard let win = recording.win else { continue }
                    let text = onTexts[recording.label]?[polishLabel] ?? ""
                    let missing = win.mustContain.filter { !text.contains($0) }
                    let gained = !win.mustGainASentence
                        || sentences(text).count > (controls[recording.label] ?? 0)
                    let passed = missing.isEmpty && gained
                    polishPass = polishPass && passed
                    columns.append(passed ? "yes" : "NO")
                }

                TestFixtures.report(
                    "[pair] \(polishLabel) × \(englishLabel) | "
                        + "\(englishClean ? "clean" : "NO -\(englishDelta.removed.count) +\(englishDelta.added.count)") | "
                        + columns.joined(separator: " | ") + " | "
                        + (englishClean && polishPass ? "PASS" : "FAIL")
                )
            }
        }
        TestFixtures.report("[pair] ============================================================")
    }

    // MARK: - One arm

    @discardableResult
    private func measure(
        engine: WhisperEngine,
        audioURL: URL,
        policy: WhisperEngine.PauseBoundaryPolicy,
        arm: String,
        prompt: String,
        recording: CaptainRecording,
        samples: [Float],
        segments: [WhisperVadSegment],
        baseline: String?
    ) async throws -> ArmResult {
        let stitched = WhisperEngine.stitch(from: samples, segments: segments, policy: policy)
        let started = Date()
        let detailed = try await engine.transcribeAudioDetailed(
            url: audioURL,
            settings: captainSettings(
                initialPrompt: prompt,
                longPausesEndSentences: policy.closesSentence
            ),
            pausePolicy: policy
        )
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        let text = cleaned(detailed.text)
        let texts = detailed.segments.map(\.text)
        let starts = detailed.segments.map(\.startTimeCentiseconds)
        let ends = detailed.segments.map(\.endTimeCentiseconds)
        let terminator = WhisperEngine.sentenceTerminator(forLanguage: detailed.language)
        let boundaries = WhisperEngine.sentenceBoundaries(
            decodedStartsCentiseconds: starts,
            decodedEndCentiseconds: ends,
            pauses: stitched.pauses,
            policy: policy,
            terminator: terminator
        )
        let runOn = cleaned(WhisperEngine.assembleSegmentTexts(texts, showTimestamps: false))
        let withBoundaries = cleaned(
            WhisperEngine.assembleSegmentTexts(texts, showTimestamps: false, sentenceBoundaries: boundaries)
        )
        let read = sentences(text)
        let junctions = WhisperEngine.pauseJunctions(
            decodedStartsCentiseconds: starts,
            decodedEndCentiseconds: ends,
            pauses: stitched.pauses,
            threshold: policy.sentenceThreshold,
            tolerance: policy.boundaryTolerance
        )
        let ignoredByTheDecoder = junctionsLeftOpen(
            in: runOn,
            texts: texts,
            starts: starts,
            endCentiseconds: ends,
            pauses: stitched.pauses,
            policy: policy,
            terminator: terminator
        )
        let stillOpen = junctionsLeftOpen(
            in: withBoundaries,
            texts: texts,
            starts: starts,
            endCentiseconds: ends,
            pauses: stitched.pauses,
            policy: policy,
            terminator: terminator
        )

        TestFixtures.report("[pair] \(recording.label) | \(arm) | \(milliseconds) ms")
        TestFixtures.report(
            "[pair]   language \(detailed.language ?? "unknown") | decoder segments \(texts.count) | "
                + "pauses measured \(stitched.pauses.count) | long "
                + "\(stitched.pauses.filter { $0.seconds >= policy.sentenceThreshold }.count) | junctions "
                + "\(junctions.count) | the decoder closed \(junctions.count - ignoredByTheDecoder) | "
                + "the pause closed \(ignoredByTheDecoder - stillOpen) | left open \(stillOpen)"
        )
        TestFixtures.report(
            "[pair]   sentences \(read.count) | fragments (<=2 words) "
                + "\(read.filter { wordCount($0) <= 2 }.count) | punctuation \(punctuationCounts(text))"
        )
        if let baseline {
            let delta = wordDelta(baseline: baseline, text: text)
            TestFixtures.report(
                "[pair]   word delta vs the switch-off/none control: -\(delta.removed.count) \(delta.removed) "
                    + "+\(delta.added.count) \(delta.added) | unchanged "
                    + "\(delta.removed.isEmpty && delta.added.isEmpty)"
            )
        }
        TestFixtures.report("[pair]   text: \(text)")
        for (index, segment) in texts.enumerated() {
            TestFixtures.report("[pair]   seg \(index) \(starts[index])->\(ends[index])cs: \(segment)")
        }

        if policy.closesSentence {
            XCTAssertEqual(
                withBoundaries,
                text,
                "\(recording.label) | \(arm): the engine's transcript is not the assembler's output for this audio"
            )
            XCTAssertEqual(
                stillOpen,
                0,
                "\(recording.label) | \(arm): a long pause is still inside a sentence in the transcript"
            )
        } else {
            XCTAssertEqual(
                runOn,
                text,
                "\(recording.label) | \(arm): nothing may be added to the decoder's own text on this arm"
            )
        }

        return ArmResult(
            arm: arm,
            prompt: prompt,
            text: text,
            sentences: read.count,
            milliseconds: milliseconds,
            languageAtDecode: detailed.language
        )
    }

    private func reportPauses(
        recording: CaptainRecording,
        samples: [Float],
        segments: [WhisperVadSegment]
    ) {
        TestFixtures.report("[pair] ============================================================")
        TestFixtures.report(
            "[pair] \(recording.label) | \(recording.fileName) | "
                + "\(samples.count) samples (\(Double(samples.count) / 16000) s) | VAD segments \(segments.count)"
        )
        for index in 1..<max(1, segments.count) {
            let vadGapCs = segments[index].startCs - segments[index - 1].endCs
            let decoderVisible = Double(
                Int(segments[index].startCs) * 160 - (Int(segments[index - 1].endCs) * 160 + 1600)
            ) / 16000
            TestFixtures.report(
                "[pair]   gap \(index): VAD \(vadGapCs) cs (\(Double(vadGapCs) / 100) s) | "
                    + "decoder-visible under the switch \(String(format: "%.2f", decoderVisible)) s"
            )
        }
    }

    // MARK: - What a language pre-pass would cost

    /// The price of the honest design, measured.
    ///
    /// A decoder prompt chosen by the language *spoken* has to know the language
    /// before the prompt is handed to the decoder, and this engine's only
    /// language signal — `whisper_full`'s own auto-detection — arrives during a
    /// decode. whisper.cpp offers exactly one way out: with `detect_language`
    /// set, `whisper_full` computes the mel and the encoder, reads the language
    /// off the encoder output and returns without decoding a token
    /// (`libwhisper/whisper.cpp/src/whisper.cpp:6849-6865`). That is a real pass
    /// over the audio, so it is measured here — same model, same context
    /// parameters (`useGPU`, flash attention), same stitched audio, same
    /// threads as a transcription — against the full decode of that same audio.
    ///
    /// Everything about this case is reported, nothing asserted beyond the
    /// pre-pass succeeding and agreeing with the engine: whether the price is
    /// worth paying is a product decision, and this is the number it turns on.
    func testTheCostOfALanguagePrePass() async throws {
        let directory = try recordingsDirectory()
        let modelURL = try TestFixtures.multilingualModel()
        let vadModelPath = try XCTUnwrap(WhisperEngine.vadModelPath, "Silero VAD model must be bundled")

        // A context configured exactly as `WhisperEngine.initialize()` configures
        // the app's own, with no decoding state of its own.
        let params = WhisperContextParams()
        guard let context = MyWhisperContext.initFromFileNoState(path: modelURL.path, params: params) else {
            XCTFail("the model did not load: \(modelURL.path)")
            return
        }
        guard let vad = MyWhisperVadContext(modelPath: vadModelPath) else {
            XCTFail("the VAD model did not load")
            return
        }
        let converter = WhisperEngine(modelPath: modelURL.path)
        let nThreads = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 8))

        TestFixtures.report("[pair] ============ the cost of a language pre-pass ============")
        TestFixtures.report("[pair] model \(modelURL.path) | threads \(nThreads) | detect = mel + encoder, no token")

        for recording in Self.recordings {
            let audioURL = directory.appendingPathComponent(recording.fileName)
            guard FileManager.default.fileExists(atPath: audioURL.path) else { continue }
            let converted = try await converter.convertAudioToPCM(fileURL: audioURL)
            let samples = try XCTUnwrap(converted, "\(recording.fileName) did not convert to PCM")
            let segments = try XCTUnwrap(vad.speechSegments(in: samples))
            let stitched = WhisperEngine.stitch(from: samples, segments: segments, policy: Self.switchOnPolicy)

            let settings = captainSettings(initialPrompt: "", longPausesEndSentences: true)
            var detectMs: [Int] = []
            var detectedLanguage: String?
            var fullMs: [Int] = []
            var fullLanguage: String?

            for _ in 0..<2 {
                guard context.initState() else {
                    XCTFail("a fresh decoding state could not be created")
                    return
                }
                var detect = WhisperEngine.makeFullParams(
                    settings: settings,
                    nThreads: nThreads,
                    modelTextContext: context.nTextCtx,
                    initialPromptTokenCount: 0
                )
                detect.detectLanguage = true
                detect.initialPrompt = nil
                var cDetect = detect.toC()
                let startedDetect = Date()
                let detected = context.full(samples: stitched.samples, params: &cDetect)
                let detectMilliseconds = Int(Date().timeIntervalSince(startedDetect) * 1000)
                let language = context.fullLangId >= 0
                    ? MyWhisperContext.langStr(id: context.fullLangId)
                    : nil
                XCTAssertTrue(detected, "\(recording.label): the detection pass failed")
                detectMs.append(detectMilliseconds)
                detectedLanguage = language

                guard context.initState() else {
                    XCTFail("a fresh decoding state could not be created")
                    return
                }
                var full = WhisperEngine.makeFullParams(
                    settings: settings,
                    nThreads: nThreads,
                    modelTextContext: context.nTextCtx,
                    initialPromptTokenCount: 0
                )
                var cFull = full.toC()
                let startedFull = Date()
                let decoded = context.full(samples: stitched.samples, params: &cFull)
                let fullMilliseconds = Int(Date().timeIntervalSince(startedFull) * 1000)
                XCTAssertTrue(decoded, "\(recording.label): the full decode failed")
                fullMs.append(fullMilliseconds)
                fullLanguage = context.fullLangId >= 0 ? MyWhisperContext.langStr(id: context.fullLangId) : nil
            }

            let detectBest = detectMs.min() ?? 0
            let fullBest = fullMs.min() ?? 0
            TestFixtures.report(
                "[pair] \(recording.label) | audio the decoder hears "
                    + "\(String(format: "%.1f", Double(stitched.samples.count) / 16000)) s | "
                    + "language pre-pass \(detectMs) ms (language \(detectedLanguage ?? "unknown")) | "
                    + "full decode \(fullMs) ms (language \(fullLanguage ?? "unknown")) | "
                    + "pre-pass is \(fullBest > 0 ? String(format: "%.0f", 100.0 * Double(detectBest) / Double(fullBest)) : "?")% "
                    + "of a decode (\((detectBest + fullBest)) ms together vs \(fullBest) ms)"
            )
            XCTAssertEqual(
                detectedLanguage,
                fullLanguage,
                "\(recording.label): the pre-pass measured a different language than the decode"
            )
        }
        TestFixtures.report("[pair] ============================================================")
    }

    // MARK: - The shipped configuration

    /// The configuration the app now ships, asserted: the Polish win, and the
    /// **accepted** English change and nothing wider.
    ///
    /// Everything else in this class measures arms; this case measures the app:
    /// `initialPrompt` empty (a new install, and the captain's domain) with the
    /// switch on (a new install) is the configuration a dictation now runs in, so
    /// the prompt the decoder is handed comes from `WhisperEngine.decoderPrompt`
    /// and the language is the engine's own measurement of the utterance — the
    /// pre-pass — not a value this test names.
    ///
    /// Three things are asserted, and the third is what keeps the accepted damage
    /// from widening quietly:
    ///
    /// * the Polish win: `pl-1` reads one sentence more than the control *and* ends
    ///   the sentence at the pause, and `pl-2` carries `Open Super Whisper` and
    ///   `Dodałem`;
    /// * the shipped path is the arm the table names: the same audio decoded with
    ///   the language's prompt written out by hand must give the same text, which
    ///   is also the evidence that the language pre-pass changes nothing about the
    ///   transcription it precedes;
    /// * the English control's words are the switch-off control's words **plus and
    ///   minus exactly the two the captain accepted on 2026-09-25**
    ///   (`acceptedEnglishChange`) — not "clean", which no prompt achieves, and not
    ///   open-ended, which is how a regression would slip through.
    func testTheShippedConfigurationKeepsThePolishWinAndOnlyTheAcceptedEnglishChange() async throws {
        let directory = try recordingsDirectory()
        let modelURL = try TestFixtures.multilingualModel()
        let vadModelPath = try XCTUnwrap(WhisperEngine.vadModelPath, "Silero VAD model must be bundled")

        let engine = WhisperEngine(modelPath: modelURL.path)
        try await engine.initialize()
        let vad = try XCTUnwrap(MyWhisperVadContext(modelPath: vadModelPath))

        TestFixtures.report("[pair] ================= the shipped configuration =================")
        for recording in Self.recordings {
            let audioURL = directory.appendingPathComponent(recording.fileName)
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                throw XCTSkip("\(recording.fileName) is not in \(directory.path)")
            }
            let converted = try await engine.convertAudioToPCM(fileURL: audioURL)
            let samples = try XCTUnwrap(converted, "\(recording.fileName) did not convert to PCM")
            let segments = try XCTUnwrap(vad.speechSegments(in: samples))

            // 1. The control: the switch off, which sends no prompt at all.
            let control = try await measure(
                engine: engine,
                audioURL: audioURL,
                policy: Self.controlPolicy,
                arm: Self.controlLabel,
                prompt: "",
                recording: recording,
                samples: samples,
                segments: segments,
                baseline: nil
            )

            // 2. The shipped configuration: no stored prompt, the switch on, and
            //    the language measured by the engine itself.
            let shipped = try await measure(
                engine: engine,
                audioURL: audioURL,
                policy: Self.switchOnPolicy,
                arm: "shipped (no stored prompt, switch on)",
                prompt: "",
                recording: recording,
                samples: samples,
                segments: segments,
                baseline: control.text
            )

            // 3. The same audio with the language's prompt written out by hand,
            //    which the table has to reproduce.
            let language = shipped.languageAtDecode
            let namedPrompt = WhisperEngine.defaultDecoderPrompt(forLanguage: language)
            TestFixtures.report(
                "[pair] \(recording.label) shipped | the engine measured \(language ?? "unknown") | "
                    + "the table's prompt for it: \(namedPrompt.isEmpty ? "none" : namedPrompt)"
            )
            let named = try await measure(
                engine: engine,
                audioURL: audioURL,
                policy: Self.switchOnPolicy,
                arm: "shipped: the same prompt, written out",
                prompt: namedPrompt,
                recording: recording,
                samples: samples,
                segments: segments,
                baseline: control.text
            )
            XCTAssertEqual(
                shipped.text,
                named.text,
                "\(recording.label): the shipped path did not send the prompt its language names"
            )

            // 4. The criterion itself: the Polish win, and in English exactly the
            //    change the captain accepted — no more, and no less.
            if let win = recording.win {
                let missing = win.mustContain.filter { !shipped.text.contains($0) }
                XCTAssertTrue(
                    missing.isEmpty,
                    "\(recording.label): the shipped configuration lost \(missing) — \(shipped.text)"
                )
                if win.mustGainASentence {
                    XCTAssertGreaterThan(
                        shipped.sentences,
                        control.sentences,
                        "\(recording.label): the shipped configuration did not gain the pause's boundary"
                    )
                }
            } else {
                let delta = wordDelta(baseline: control.text, text: shipped.text)
                XCTAssertEqual(
                    delta.removed,
                    Self.acceptedEnglishChange.removed,
                    "\(recording.label): the switch on lost different words than the captain accepted on "
                        + "2026-09-25 — \(shipped.text)"
                )
                XCTAssertEqual(
                    delta.added,
                    Self.acceptedEnglishChange.added,
                    "\(recording.label): the switch on invented different words than the captain accepted on "
                        + "2026-09-25 — \(shipped.text)"
                )
            }
        }
        TestFixtures.report("[pair] ============================================================")
    }
}
```

The switch's doc comment, the draft that carried the false claim against the landed text (condition 2)

```diff
--- evidence/fm2414-appprefs-switch.txt (the draft)
+++ landed OpenSuperWhisper/Utils/AppPreferences.swift
@@ -8,17 +8,35 @@
     /// segments is kept as real silence (up to `maxPause`) and closes the
     /// sentence in the assembled text when the decoder did not close it.
     ///
-    /// **On by default, because the pairing was measured.** The switch on its own
-    /// fixes the Polish the complaint is about — but with the decoder prompt this
-    /// app used to send, none, it also made the English control invent a fragment
-    /// ("based, no,") that the switch off does not produce, so it shipped off.
-    /// It ships on now that a deliberate prompt is sent for the language spoken
-    /// (`WhisperEngine.decoderPrompt`): on the captain's own recordings, through
-    /// this app's own decode path, the switch on with that default keeps `pl-1`'s
-    /// sentence boundary and `pl-2`'s "Open Super Whisper"/"Dodałem", and leaves
-    /// the English control word-for-word what the switch off gives. Off remains
-    /// byte-for-byte the behaviour every earlier build had, and flipping it back
-    /// is this one line. The tables are in `WhisperPauseBoundaryPairingTests` and
-    /// `fleet/data/fm-20260925-14/report.md`.
+    /// **On by default, and the English audio pays a measured two-word change for
+    /// it.** The switch fixes the Polish the complaint is about (`pl-1` gains its
+    /// sentence boundary and its verb; `pl-2` reads "Open Super Whisper" and
+    /// "Dodałem" where the switch off garbles both). With the decoder prompt this
+    /// app used to send — none — it did worse than that: the English control
+    /// invented a fragment ("based, no,") at every silence cap tried. The prompt
+    /// now sent for the language spoken removes that invention, and what is left
+    /// is the switch's own audio half: it is present in the arm that sends no
+    /// prompt at all and is identical across prompts, so **no prompt removes it**.
+    /// The captain was shown that with the numbers and accepted it on
+    /// **2026-09-25** — option (a), "pause fix everywhere, English takes a 2-word
+    /// change", `fleet/data/fm-20260925-14` — and the shipped configuration is
+    /// asserted against exactly that delta in `WhisperPauseBoundaryPairingTests`,
+    /// so widening it fails the suite instead of landing quietly. It is measured
+    /// on three recordings by one speaker, so it is a property of that pause and
+    /// not a claim about English in general.
+    ///
+    /// With no prompt of your own the decoder prompt is chosen by the language of
+    /// the dictation, and that costs one extra detect-only language pass over the
+    /// audio before each dictation — measured +1.34 s against a 3.5 s decode,
+    /// ≈ 38 % — paid only while this switch is on and no prompt is set; and on
+    /// pause-heavy English speech the switch changes two words against the switch
+    /// off ("Basically now it creates a sentences" where the switch off says
+    /// "Basically how it creates a sentence"), a change the captain accepted on
+    /// 2026-09-25 with the measurement in front of him, because no prompt removes
+    /// it and the Polish fix rides on the same silence.
+    ///
+    /// Off remains byte-for-byte the behaviour every earlier build had, and
+    /// flipping it back is this one line. The tables are in
+    /// `WhisperPauseBoundaryPairingTests` and `fleet/data/fm-20260925-14/report.md`.
     @UserDefault(key: "longPausesEndSentences", defaultValue: true)
     var longPausesEndSentences: Bool
```

### 9. What remains unverified

* **The pre-pass's accuracy was asserted on three recordings and nothing else.** On `pl-1`, `pl-2` and the English
  control the detect-only pass measured the same language the decode later reported (asserted in
  `testTheCostOfALanguagePrePass`), and the three recordings are the whole of the evidence: no other language, no
  noisy or quiet audio, no utterance that mixes two languages, no long clip.
* **The two-word English change is a property of *that* pause in *that* recording.** Three recordings, one speaker,
  one model. Other English audio may be unaffected or worse. The control is also itself a wrong decode of his speech
  (the captain said "Essentially…", the switch-off decode hears "Basically **how**…"), so `how → now` may be a
  correction rather than damage — what is measured is the difference, not which side is right, and that judgement was
  his to make.
* **The cost is this machine's and this audio's.** +1.34 s against a 3.5 s decode, measured on a Mac mini with the
  GPU, flash attention and 8 threads; a CPU-only install, or a clip whose decode is longer (the encoder is a fixed
  30 s window, the decode grows with the audio), pays a different fraction.
* **No language but Polish and English was measured.** Every other language gets no prompt, which is byte for byte
  the prompt behaviour this app always had — but the *audio* half of the switch applies to all 25 languages whisper
  can transcribe, and nothing here measured what keeping long pauses does to, say, German.
* **The criterion test skips wherever the captain's recordings or a multilingual model are absent** — which is CI, and
  any other machine. The accepted delta is pinned in the test, but it is enforced only where his fixtures are; the
  suite's other cases cover the rule, not the audio.
* **Timestamp mode sends no default by construction, not by measurement.** `showsTimestamps` is a clause of
  `decoderPrompt` and has a pure case; no decode was measured with *Show Timestamps* on.
* **The PCM entry point is not exercised with real audio.** `transcribeSamplesDetailed` shares `performTranscription`
  and therefore the pre-pass and the prompt rule, but no case decodes real audio through it (the same gap
  `fm-20260924-12` recorded).
* **The UI copy was not seen.** Settings' new caption is verified by the build, by `SettingsLayoutSnapshotTests`
  (card bands, gaps and margins still hold with the longer caption) and by the compiler; no app was launched and no
  screenshot taken, which is the contract here.
* **The flip was not tested against the other crews' branches.** This tree is `d960bb7` plus this change; the tone and
  translation work that merged after `eaecd28` is untouched by it, but no sibling branch ran with the switch defaulting
  on.
* **The suite counts are this tree's, with his fixtures opted in.** They include the three opt-in measurement cases
  (`WhisperPauseBoundaryPairingTests`) and the older `WhisperPauseBoundaryMeasurementTests` for the same reason; a
  machine without those files sees the same tree minus those cases.
* **The clean full suite on the merged tip is Main's run, not this crew's**, and the Readme says so where it quotes
  test counts: no green full suite was measured by this crew after the capture-harness repair — the repair was
  verified scoped (`SettingsLayoutSnapshotTests`, 7/7) and the branch was handed over unmerged on purpose.
