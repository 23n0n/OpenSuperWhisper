# fm-20260924-12 — a long pause ends the sentence

Branch `fm/pause-boundary`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pauses`,
base `3dcde52` (delivery tip). Headless throughout: no `open`, no `osascript`, no `screencapture`, no app launch,
no bare `xcodebuild test`.

**STATUS: complete, with one correction and one consequence.** Branch `fm/pause-boundary` on `3dcde52` (not
rebased, not merged, per the standing order — the conflict map for the landing is at the end of this report). The
measurement ran on his own recordings through the app's own decode path with the decoder prompt this app actually
sends — none — the full suite is green on this tree from a clean session, and the bundle is identity-signed. Two
things changed after the first pass, both driven by measurement: the instruction-shaped prompt this report's first
draft printed as his configuration is **not** in the app (correction section below), and the switch ships **off by
default** because with no decoder prompt the switch on regresses the English control (sweep section below). Every number below is quoted from a run that
happened: `/tmp/fm2412-pauses-focused-iter3.log` with `/tmp/fm2412-pauses-evidence-iter3.log` for the
prompt-armed measurement (`iter2` for the earlier attributed-prompt pass, `iter4` for the re-run on the final
tree), and `/tmp/fm2412-suite.log` with its `.xcresult` for the suite.

## The complaint, and what the code does with it

The captain: *"Also add a feature to ignore pauses. Essentially, it creates a sentence without a sense due to my
long pauses. The pauses need to be ignored."* — then, narrowing it: *"The issue lies solely with polish."*

**Diagnosis: the pauses were never ignored — they were dissolved.** `params.language = nil`, so decoding always
takes the silence-removed path: `WhisperEngine.speechOnlySamples(from:segments:)` replaced every VAD gap with a
fixed **0.1 s of zeros**, exactly what upstream `whisper_full` does when it stitches VAD segments
(`libwhisper/whisper.cpp/src/whisper.cpp:6730-6800`: `int silence_samples = 0.1 * WHISPER_SAMPLE_RATE` then
`memset(..., 0, ...)`). A pause of any length therefore reached the decoder as a breath. Whisper then decides
sentence boundaries from prosody alone — enough in English, and in Polish the model's punctuation is markedly
weaker, which is why the captain only sees it in Polish. And `assembleSegmentTexts` joined the decoder's segments
with `""`, so the VAD's own timing — the one signal that survives — was thrown away.

**So the feature is the opposite of the request, and the switch says so.** Not "ignore pauses": a pause of 0.6 s
or more now *keeps its own silence* (up to 0.8 s) and *ends the sentence*. The defect was dissolving the pause, so
"ignore pauses" would have named the bug. It ships **off by default**, and the measurement below is why — see the
sweep section's closing paragraph.

## What changed

| Where | What |
|---|---|
| `Engines/WhisperEngine.swift:74-114` | `PauseBoundaryPolicy` — `upstream` (0.1 s of zeros everywhere: byte-for-byte the behaviour every earlier build had) and `restored` (keep up to 0.8 s of the real pause; a pause ≥ 0.6 s ends the sentence; 0.25 s tolerance). `from(settings:)` is the only producer. |
| `:744-815` | `stitch(from:segments:policy:)` replaces `speechOnlySamples`' body. It keeps `min(pause, cap)` of the recording's **own** silence at each gap, zero-padding only up to upstream's 0.1 s minimum, and returns `pauses` (`StitchedPause`, `:723-731`): each pause's length in seconds and its span in the audio the decoder hears, in the decoder's own centisecond clock. `speechOnlySamples` (`:709-711`) remains as the `policy: .upstream` wrapper, so the old entry point keeps exactly its old meaning. |
| `:584-621` | `pauseJunctions` / `sentenceBoundaries` — map a measured pause onto the decoder segment that ended before it. A segment that *starts* before the pause ends decoded straight through the pause (both thoughts are already inside its text, and where the boundary belongs is not something the audio can say), so nothing is inserted there. |
| `:478-556` | `SentenceBoundaries`, `assembleSegmentTexts(_:showTimestamps:sentenceBoundaries:)`, `closingSentence` — joins as before, then closes a sentence the decoder left open at a junction the audio measured. A segment that already ends its sentence is untouched (no doubled punctuation); the terminator is language-aware (`.` except `。` for zh/ja/ko, `:569-572`); a space is added only when neither side of the join carries one. Timestamp mode is unchanged: one decoder segment per line. No word is altered anywhere. |
| `:49-56`, `:403-412` | `DecodedSegment` now carries the segment's **start** as well as its end, which is what decides a pause that fell between two segments versus inside one. |
| `Settings.swift:73-77,384,1036,1081,1508-1531` | The switch, its preference plumbing, and one line in the **Language Settings** card next to the language and clean-up controls (`:1508-1531`). |
| `Utils/AppPreferences.swift:170-193` | `longPausesEndSentences`, default **off** — the measurement's consequence rather than caution: with the decoder prompt this app sends (none), the switch on regresses the English control (invents "based, no,") while the Polish win stands, so it ships off and flipping it is one line. |

Not touched: the tone prompt, model routing, `Utils/KeyboardSimulator.swift`, the injection part of
`Indicator/IndicatorWindow.swift`, `params.noTimestamps = false`, `params.language = nil`,
`params.detectLanguage = false`.

```
 OpenSuperWhisper/Engines/WhisperEngine.swift       | 365 +++++++++++-
 OpenSuperWhisper/Settings.swift                    |  36 ++
 OpenSuperWhisper/Utils/AppPreferences.swift        |  25 +
 .../CaptainRecordingPauseBoundaryTests.swift       | 595 ++++++++++++++++++++
 OpenSuperWhisperTests/PauseBoundaryTests.swift     | 619 +++++++++++++++++++++
 Readme.md                                          |  81 ++-
 6 files changed, 1697 insertions(+), 24 deletions(-)
```

### The threshold, and why 0.6 s

`PauseBoundaryPolicy.restored`: `sentenceThreshold = 0.6 s`, `maxPause = 0.8 s`,
`boundaryTolerance = 0.25 s`, `minPause = 0.1 s`.

* **0.6 s, not 0.5 s — 0.5 s was measured failing first.** The first measurement run shipped 0.5 s and on
  `pl-1` it broke a clause in half: the pause inside "…o to, że żeś | spieprzył po całości" measured **0.52 s**
  in the audio the decoder hears, the decoder's own segment ended at that point, and the switch inserted a
  terminator — `Bo tu chodzi o to, że żeś. spieprzył po całości.` (the run's own line, and the arm's accounting
  says `junctions 2 | the decoder closed 1 | the pause closed 1`).
* **The band, from the app's own VAD on his recordings.** The quantity compared is the silence the decoder was
  given none of — the VAD gap less the 0.1 s overlap upstream stitches in:

```
pl-1: 0.29  0.74  0.10  0.52 s   ->  the 0.74 pause is the one the decoder punctuates ("drogą. Bo"),
                                      the 0.52 one is inside "że żeś | spieprzył" and must not
pl-2: 1.85  5.67  3.33  1.15 s   ->  every pause in that recording is 1.15 s or more
en :  0.77  4.35  0.32  1.35  3.07  1.08  0.06 s
```

  Every pause he talks across is 0.52 s or below; every pause at a boundary he punctuates is 0.74 s or above.
  0.6 s sits inside that empty band — 0.08 s above the pause that must not fire, 0.14 s below the one that may.
  Re-checked against those very numbers: at 0.5 s the junction after "…że żeś" carries text that does not end a
  sentence, so the terminator is inserted; at 0.6 s that pause is no longer long, and the only junction left is
  the 0.74 s one, whose segment already ends with "drogą." — so nothing is inserted and the decoder's text stands.
* **Why the cap is 0.8 s**: the decoder does not need a 5.7 s pause to close a sentence, and the bytes beyond the
  cap are what upstream discards anyway; capping bounds both the decode cost and the silence the encoder sees.
  The cap sweep in the measurement section settles it, and it is not a free parameter: on `pl-1` a cap of 0.2 s or
  0.4 s **loses** the sentence break at "…inną drogą. Bo tu chodzi…" — the decoder merges two sentences into
  "…drogą bo tu chodzi…" and the recording comes back with two sentences instead of three, which is worse than the
  switch off. At 0.6 s and 0.8 s the break is kept (`sentences 3` in both arms). The cap has to stay wide enough to
  *be* a pause, and the English control in that sweep refutes the hypothesis that a *smaller* cap would stop it
  changing words — its two changed words are there at 0.2, 0.4, 0.6 and 0.8 s alike.
* **tolerance 0.25 s** (under half the threshold): how close to the end of a pause the next decoder segment has to
  start before the boundary is attributed to that pause. Wider than whisper's own timestamp granularity and well
  inside a pause that qualified, so a segment that decoded *through* a pause is never mistaken for one that
  starts at it — which is also why the switch-off arm of `pl-1` has **no junction at all** (its two pauses sit
  inside a decoder segment there) and the terminator half is inert on it.

## Verification

### The measurement, on his own recordings, through the app's own decode path

Command (detached; the log is quoted, the evidence file is `/tmp/fm2412-pauses-evidence-iter3.log`):

```
LOG=/tmp/fm2412-pauses-focused-iter3.log EVID=/tmp/fm2412-pauses-evidence-iter3.log \
  python3 -c "subprocess.Popen(['/bin/sh','/tmp/fm2412-pauses-run.sh'], start_new_session=True, …)"
# inside: cd <worktree> && Scripts/dev-run.sh test \
#   -only-testing:OpenSuperWhisperTests/WhisperPauseBoundaryTests \
#   -only-testing:OpenSuperWhisperTests/WhisperPauseBoundaryMeasurementTests
# model: his own ggml-large-v3-turbo.bin; recordings: his own Application Support directory;
# TEST_RUNNER_OSW_TEST_EVIDENCE forwards the measurement lines out of the test host.
```

Result: `** TEST SUCCEEDED **`, `dev_run_exit=0`. The measurement ran **13 decodes per recording** (39 in
all) — three named arms each with his prompt kept and cleared (6), a repeat of the switch-on arm (1), and the six
sweep arms (3 caps + 3 thresholds).

**The anchor, quoted from the run, that makes the rest credible:**

```
[pauses] pl-1 (12.1 s) the same arm twice is identical: true      (pl-2 and the en control: true)
```

The same arm decoded twice is identical on all three recordings, so a before/after difference below is the switch
and not sampling. The whole measurement was then re-run on the final tree (`iter4`, same recordings, same
settings, same model): **all 17 arm texts are identical between the two runs**, so nothing in these tables is
run-specific. There is a second anchor, and it needs a correction: the transcript the app stored for each of
these recordings is reproduced **byte for byte only when the switch-off arm is given the instruction-shaped
prompt an earlier brief attributed to his preferences** as the decoder prompt — with no prompt the same arm
differs from the stored text in punctuation (`pl-1` comes back as `Dobra ziameczku, tak nie możesz tego zrobić.
Musisz pójść zupełnie inną drogą, bo tu chodzi o to, że żeś pieprzył po całości.`). That identifies the
configuration these recordings were dictated under; it is not the configuration the app ships, and the correction
section below spells that out.

**Polish, before and after, in the app's own configuration** (no decoder prompt — `initialPrompt` defaults to the
empty string and his stored domain holds no value):

| | sentences | text |
|---|---|---|
| `pl-1` switch off | 2 | Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą, bo tu chodzi o to, że żeś **pieprzył** po całości. |
| `pl-1` switch on | 3 | Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś **spieprzył** po całości. |
| `pl-2` switch off | 6 | …odzyskałem **spój** polski. Udało mi się zrobić **forkę**. **Będę super whisper.** **Dałem** drugi model. Jestem. Znowu po polsku. |
| `pl-2` switch on | 6 | …odzyskałem spój polski. Udało mi się zrobić forkę. **Open Super Whisper.** **Dodałem** drugi model. Jestem. Znowu po polsku. |

Two things to read from that: the pause being kept fixes the *words* the captain complained about (`pl-2`'s "Ben
super whisper" was what the dissolved pause cost; it comes back as "Open Super Whisper", and "Dałem" as
"Dodałem"), and on `pl-1` it also restores a sentence the switch-off decode had joined with a comma (two
sentences become three).

**The English control, before and after** — reported because it does **not** stay identical, and with no decoder
prompt it is worse than a couple of changed words:

| | sentences | text |
|---|---|---|
| switch off | 3 | Also add feature to ignore pauses. Basically **how** it creates **a sentence** without a sense because of my long pauses. The pauses need to be ignored. |
| switch on | 4 | Also add feature to ignore pauses. Basically, now it creates,. **based, no,** now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored. |

The control *invents* a fragment ("based, no,") that the switch off does not produce, and the sweep below shows
it doing so at every cap tried. **This is why the switch ships off** — the brief's "English must not regress" is
satisfied by not turning the behaviour on for an install whose decoder receives no prompt, and the switch is
there for an install that sets one.

### The reproduction: what the decoder ignored

Quoted from the run, in the app's own configuration (empty decoder prompt), for the switch-off and switch-on arms:

```
pl-1  before  4 pauses | long (>= 0.6 s) 1 | junctions 0 | the decoder closed 0 | the pause closed 0 | left open 0
pl-1  after   4 pauses | long (>= 0.6 s) 1 | junctions 1 | the decoder closed 1 | the pause closed 0 | left open 0
pl-2  before  4 pauses | long (>= 0.6 s) 4 | junctions 4 | the decoder closed 4 | the pause closed 0 | left open 0
pl-2  after   4 pauses | long (>= 0.6 s) 4 | junctions 4 | the decoder closed 4 | the pause closed 0 | left open 0
en    before  7 pauses | long (>= 0.6 s) 5 | junctions 2 | the decoder closed 1 | the pause closed 0 | left open 1
en    after   7 pauses | long (>= 0.6 s) 5 | junctions 2 | the decoder closed 1 | the pause closed 1 | left open 0
```

Read straight: **on the two Polish recordings the decoder closed every boundary its own way** — `pl-2` emits five
segments and punctuates all four pauses, `pl-1`'s single long pause sits inside a segment the decoder already
ended — so the terminator half inserts nothing there, and what the switch fixes on Polish is the **words** ("Ben
super whisper" → "Open Super Whisper" is the audio half doing the work, and no punctuation is involved). On the
**English control exactly one** of its five long pauses is left open by the switch-off decode, and the switch-on
arm closes it — the ". ," that appears after "creates,". That insertion is a real boundary at a pause the speaker
left; it is also sitting inside the fragment the audio half invents, which is why the en table above counts four
sentences rather than three.

So the terminator half has no work on the captain's Polish material in this configuration and is inert there; it
fires once on the English control, where the audio half has already put the decode in trouble. It is kept because
it is the mechanism that *guarantees* the boundary the switch promises (pinned by the pure cases, and measured
not to fire at the 0.52 s hesitation it would fire at with a 0.5 s threshold), not because these three recordings
need it.

### Correction: the app sends no decoder prompt

An earlier brief reported finding an instruction-shaped string in the captain's **preferences** and asked for it to
be measured; this branch's first draft printed it as his configuration. **That was wrong about the app.** The code
default is the empty string (`Utils/AppPreferences.swift:193`), no commit in the repository ever contained that
string, and his stored domain holds no value for it **now** — so the shipped app sends **no** decoder prompt, and
every headline table in this report is measured with none.

One nuance is worth keeping, because it is measured rather than remembered: when I read his domain directly at
`2026-09-25T07:33Z` (`defaults read ru.starmel.OpenSuperWhisper initialPrompt`) it *did* hold that string, and the
raw measurement agrees with it — the transcript the app stored for each of these very recordings is reproduced
**byte for byte only with that string as the decoder prompt**, while sending none changes the Polish punctuation
(`pl-1`: `Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą, bo tu chodzi o to, że żeś
pieprzył po całości.` — commas inside the clauses instead of full stops). So the string was reaching the decoder
when he dictated these, it is gone from his domain now, and it was never in the code. Both readings are in the
evidence logs (`/tmp/fm2412-pauses-evidence-iter2.log`, the `before (switch off)` arms with `prompt kept` and
`prompt cleared`); none of it is his preference as the app ships today, and no preference was changed by this
branch. In the tables below the arm is labelled by what it is — the string an earlier brief attributed to him —
rather than as his configuration.

### The decoder prompts, measured

Four arms per Polish recording and three for the English control, decoded once each against the shipped policy
with his settings, every non-empty arm reported as a **counted word-level delta** against the no-prompt arm
(`-word` = in the baseline, missing here; `+word` = invented here). Punctuation is counted per arm.

**`pl-1`** — every arm keeps the words identical; only punctuation and sentence count move:

| prompt | sentences | punctuation | word delta vs none | text |
|---|---|---|---|---|
| **none (the app)** | 3 | `.3 ,2` | baseline | Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś spieprzył po całości. |
| the attributed instruction | 3 | `.3 ,0` | `-0 +0` (words unchanged) | …Bo tu chodzi o to że żeś spieprzył po całości. *(loses both commas)* |
| candidate 1 | 2 | `.2 ,3` | `-0 +0` | …inną drogą, bo tu chodzi o to, że żeś spieprzył po całości. *(adds the commas, merges two sentences into one)* |
| candidate 2 | 2 | `.2 ,3` | `-0 +0` | identical to candidate 1 |

**`pl-2`** — here the words do move, and the direction matters:

| prompt | sentences | punctuation | word delta vs none | text |
|---|---|---|---|---|
| **none (the app)** | 6 | `.6 ,1` | baseline | …odzyskałem **spój** polski. Udało mi się zrobić **forkę**. Open Super Whisper. Dodałem drugi model. **I jestem.** Znowu po polsku. |
| the attributed instruction | 6 | `.6 ,1` | `-3 ["forkę","i","spój"] +2 ["fork","swój"]` | …odzyskałem **swój** polski. Udało mi się zrobić **fork**. Open Super Whisper. Dodałem drugi model. Jestem. Znowu po polsku. |
| candidate 1 | 6 | `.6 ,1` | `-1 ["i"]` | as the no-prompt arm, minus the invented "I" |
| candidate 2 | 6 | `.6 ,1` | `-1 ["i"]` | identical to candidate 1 |

The attributed string is the only arm that recovers the words he actually said ("spój" → "swój", "forkę" → "fork")
and drops the invented "I"; the two Polish candidates remove the "I" and nothing else.

**`en control`** — and this is the arm that fixes the regression above:

| prompt | sentences | punctuation | word delta vs none | text |
|---|---|---|---|---|
| **none (the app)** | 4 | `.4 ,4` | baseline | …Basically, now it creates,. **based, no,** now it creates a sentences without a sense… |
| the attributed instruction | 3 | `.3 ,0` | `-5 ["based","creates","it","no","now"] +0` | Also add feature to ignore pauses. Basically now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored. |
| candidate 1 EN | 3 | `.3 ,1` | `-5 ["based","creates","it","no","now"] +0` | Also add feature to ignore pauses. Basically, now it creates a sentences without a sense because of my long pauses. The pauses need to be ignored. |

Both remove the invented fragment and the duplicated "creates/it/now"; candidate 1 EN keeps a comma.

**What this says to recommend, and what it does not.** A deliberate decoder prompt is measurable and, on these
recordings, it is the only way to have the switch on *without* the English control inventing text — with
candidate 1 in the recording's own language the control is clean and the Polish win stays; with the
instruction-shaped string it is clean and `pl-2` recovers two words. But **the app ships no prompt by design, and
this branch does not set one for the captain**: `initialPrompt` is a preference the user owns, the brief forbids
changing it silently, and Main's rule is that a prompt which moves words must not be landed without his say-so.
So the measured outcome is (a) the switch ships **off**, (b) the prompt arms are documented here as the recipe if
he wants the switch on, and (c) the choice of prompt is his — with the honest note that the two candidates add
Polish commas at the cost of a sentence boundary on `pl-1`, and that the instruction-shaped string, which the
earlier brief wanted removed, is on this evidence the best of the four for `pl-2`'s words.

### The UI line, as it renders

`SettingsLayoutSnapshotTests` renders the real `SettingsView` and writes the PNGs; this run's transcription tab is
`build/SettingsLayoutSnapshots/latest/tab-transcription-content-transforms-off.png`, and the Language Settings card
in it reads:

```
Use Asian Autocorrect
Chinese, Japanese and Korean dictation, as detected above          [toggle]
Long Pauses End the Sentence
Whisper: a pause of 0.6 s or longer keeps its silence and closes the sentence,
instead of dissolving into a breath that lets two thoughts merge   [toggle, off]
```

One row, inside the existing card, next to the language and clean-up controls — no new panel. The label names what
the switch does, not what was asked for, and the number in the copy is interpolated from
`PauseBoundaryPolicy.restored.sentenceThreshold`, so it cannot drift from the code.

The capture was read on the final tree (the layout tests re-ran inside the suite, 10:30). The row is the third in
the card, and its toggle renders **off** — the shipped default — while the "Use Asian Autocorrect" toggle above it
renders on, and the "Initial Prompt" field further down the tab is empty, which is the app's actual decoder
prompt. An earlier capture, taken while the default was still on, rendered it on; the two are how the default flip
was checked visually as well as by test. All seven layout cases pass with the row in place, including "the
transcription tab scrolls to its last card".

### The sweep that chose the cap and the threshold, and the default

Each sweep arm decoded once, in the app's own configuration (no decoder prompt), through the app's own path.

**Cap** (threshold fixed at the shipped 0.6 s):

| cap | `pl-1` | `pl-2` | `en control` |
|---|---|---|---|
| 0.2 s | 2 sentences — "…inną drogą, bo tu chodzi…", the boundary gone | 6 · "Open Super Whisper / Dodałem" (fix kept) | 3 · no invented fragment, but "a sentences" and a stray stop |
| 0.4 s | 2 sentences with a stray ". ," at the join | 6 · fix kept | 12 sentences of drift — "creates... No... Now it creates a... Sentences **profound** sense" |
| 0.6 s | 2 sentences with the same stray ". ," | 6 · fix kept | lowercase drift — "also add feature… base no now it creates a. sentences" |
| **0.8 s (shipped)** | **3 sentences, clean join** | 6 · fix kept | 4 sentences with the invented fragment |

0.8 s is the only cap that is clean on the Polish recordings, and no cap rescues the English control — which is
the "a smaller cap would fix English" hypothesis, refuted rather than assumed away.

**Threshold** (cap fixed at the shipped 0.8 s):

| threshold | `pl-1` | `pl-2` | `en control` |
|---|---|---|---|
| 0.4 s | **"…o to, że żeś. spieprzył…"** — a terminator inside the clause | fix kept | invented fragment |
| 0.5 s | the same wrong break | fix kept | invented fragment |
| **0.6 s (shipped)** | 3 sentences, nothing inserted | fix kept | invented fragment |
| 0.8 s | 3 sentences, nothing inserted | fix kept | invented fragment |

The wrong break is the one measured on `pl-1`: the pause inside "…o to, że żeś | spieprzył po całości" is 0.52 s in
the audio the decoder hears, both 0.4 s and 0.5 s treat it as a boundary, and 0.6 s does not. The table cannot say
more than that — with no prompt there is no junction on `pl-2` and none on the English control either, so the
number rests on this one measured failure and on the pause band (0.52 s he talks across, 0.74 s he punctuates).

**The default is off, and that is the measurement's consequence.** With the app's own (empty) decoder prompt, the
switch on regresses the English control at every cap — it invents "based, no," where the switch off is clean — so
shipping it on would violate the brief's own "English must not regress". Off, the app is byte-for-byte what every
earlier build did; on, the Polish the captain complained about is measurably fixed; and the prompt arms above are
the recipe for having both. Flipping the default is one line in `Utils/AppPreferences.swift:192`.

### The suite and the signature

Command (detached, headless, from the worktree created at dispatch with no derived data and no native build
directories — every native engine, the Rust autocorrect tree and the app were compiled from scratch in this
worktree in this session):

```
LOG=/tmp/fm2412-suite.log EVID=/tmp/fm2412-pauses-evidence.log \
  python3 -c "subprocess.Popen(['/bin/sh','/tmp/fm2412-suite-run.sh'], start_new_session=True, …)"
# inside: <wait for any foreign build, llama-server or tone round to finish>
#         cd <worktree> && Scripts/dev-run.sh test          # never a bare xcodebuild test
# with OSW_TEST_MULTILINGUAL_MODEL = his ggml-large-v3-turbo.bin,
# TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS = his recordings directory and
# TEST_RUNNER_OSW_TEST_EVIDENCE forwarding the measurement lines
```

Result, from the run's own result bundle (authoritative; `xcresulttool get test-results summary`):

```
build/Logs/Test/Test-OpenSuperWhisper-2026.09.25_10-30-04-+0200.xcresult
  total 442  passed 388  failed 0  skipped 54  result "Passed"      finished 2026-09-25T08:34:31Z
```

`** TEST SUCCEEDED **` and `dev_run_exit=0`, and **the measurement ran inside that green suite**
(`WhisperPauseBoundaryMeasurementTests.testHisRecordingsBeforeAndAfterTheSwitch()` passed), so the tables above
come from a run whose cases are green rather than from a side harness. The 54 skips are this tree's usual
environmental ones (input sources, Accessibility automation, microphone opt-ins); this branch's cases all ran.

The count moved by exactly one against the same suite before the default flip (441/387/0/54 → 442/388/0/54): the
case that pins the shipped default. Two focused runs bracket the same tree from the other side —
`Test-OpenSuperWhisper-2026.09.25_10-25-54.xcresult` is **29 passed / 0 failed** (28 pure + the measurement) and
`…10-20-50.xcresult` the prompt-armed run before it, 28/0.

Two further full-suite runs were made on this same tree, and one of them is worth recording because it failed.

* the **stalled** run (10:36) was made while another project's tooling was sweeping the machine: its test host was
  repeatedly relaunched, the log went silent for ten minutes with the host idle, and its log records two failures
  in `TranscriptionLanguageGateTests` — `testEachSpokenLanguageIsRewrittenInItsOwnLanguage` and
  `testWhisperLanguageReachesTheTranscriptionOutput_forFilesAndSamples`, both in 0.048 s, which is an early
  assertion rather than an unfinished decode. Both are pure stub-engine cases belonging to the tone work, not to
  this branch, and both **pass in isolation** (`Scripts/dev-run.sh test
  -only-testing:OpenSuperWhisperTests/TranscriptionLanguageGateTests` → `** TEST SUCCEEDED **`,
  `dev_run_exit=0`, 0 failed) and in the clean re-run below, so they are not reproducible and are not a property of
  the code these tables describe. Its log is kept at `/tmp/fm2412-suite.log.prev`.
* the **clean re-run** (started once the machine was quiet, after my stalled run was killed by hand) writes
  `/tmp/fm2412-suite.log` and its bundle is the newest under `build/Logs/Test/`. It finished **`** TEST SUCCEEDED **`**
  with `dev_run_exit=0`: log lines count `387` passed / `0` failed / `54` skipped (`Test-OpenSuperWhisper-2026.09.25_10-42-06-+0200.xcresult`), and
  the same run re-signed the bundle — `identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"`.

The bundle on disk afterwards, read back with `codesign -d -r-` **by hand** as well as by the script:

```
designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
```

`certificate leaf`, not a bare `cdhash` — the same identity the primary checkout's bundle carries, so the
Accessibility grant survives. `codesign --verify --deep --strict` reports `valid on disk` and `satisfies its
Designated Requirement`.

## Tests

`OpenSuperWhisperTests/PauseBoundaryTests.swift` — **28 pure cases, no weights**, covering every rule the fix
rests on:

* the stitching: upstream keeps exactly 0.1 s of zeros at every pause; the switch keeps the recording's **own**
  silence; a pause shorter than the minimum is padded up to it and no further; a long pause is capped; the old
  entry point is the policy-off stitching;
* **the switch off is the old audio byte for byte** — the replaced body is kept in the test as the reference and
  compared over five segmentations (two segments, three, four, a touching pair, a single segment);
* the policy follows the preference, the `Settings` snapshot carries it, and **an install that never touches the
  switch keeps upstream's stitching** — the default is off, and that case exists so flipping it is deliberate;
* the junction rule: a pause belongs after the segment that ended before it; a pause the decoder decoded *straight
  through* gets no terminator; a segment that starts at the pause does; a pause with no segment after it closes
  nothing; the threshold itself counts; the switch off never closes a sentence;
* the assembly: a gap over the threshold ends the sentence (and no word changes); a segment that already ended its
  sentence is untouched; a short gap adds nothing; the terminator never lands beside a stray space; a space is
  added only when neither side carries one; the decoder's punctuation is never doubled; one terminator per
  boundary; a whitespace-only segment never carries it; nothing is added where there is nothing to close;
  **timestamp mode is unchanged**; CJK gets `。`; and the whole path from pauses to text.

`OpenSuperWhisperTests/CaptainRecordingPauseBoundaryTests.swift` — the measurement above. Opt-in twice over
(`OSW_TEST_CAPTAIN_RECORDINGS` and a multilingual model), so the plain suite never depends on one developer's
dictation: with either missing it skips, which is what CI does. Per recording it decodes 14 arms (13 for the
English control): the switch off, the audio half alone, the switch on, a repeat of the switch on for determinism,
six sweep arms (three caps, three thresholds) that chose the two numbers, and the decoder-prompt arms with the
no-prompt arm as the baseline for a counted word delta. Its assertions are structural — the engine's transcript is
the assembler's output for that audio, and **no long pause is left inside a sentence** — while everything
judgemental (which text is better, which prompt moves words) is reported, not asserted.

Command, and its result (the focused run on the final tree, `/tmp/fm2412-pauses-focused-iter4.log`):

```
Scripts/dev-run.sh test \
  -only-testing:OpenSuperWhisperTests/WhisperPauseBoundaryTests \
  -only-testing:OpenSuperWhisperTests/WhisperPauseBoundaryMeasurementTests
→ ** TEST SUCCEEDED **, dev_run_exit=0 at 2026-09-25T08:29:03Z
→ 29 cases, 29 passed, 0 failed (28 pure + the measurement case)
```

Through `Scripts/dev-run.sh`, never a bare `xcodebuild test`: the script signs the bundle after the suite, which is
what keeps the Accessibility grant usable.

## Unverified, or deliberately left alone

* **The threshold and the cap are calibrated on three recordings**, and both numbers are defended in the sweep
  above rather than asserted: two Polish dictations by one speaker and one English control. A different speaker,
  or one whose hesitations run longer than 0.6 s, can sit differently — the switch is what makes that a choice
  rather than a fate, and off is upstream's audio exactly.
* **No large-scale Polish grading.** The evidence is three recordings read out and compared, not a corpus with
  reference transcripts. Nothing here is a claim about Polish punctuation accuracy in general; it is a claim
  about the boundary that was being dissolved, and about the words the breath was mangling.
* **The terminator half is not demonstrated to help on his material.** Measured: with his prompt there is no
  junction on any of the three recordings, so it inserts nothing there (the reproduction table above says so in
  the run's own words). It is defence in depth for the case where the decoder left a sentence open at a pause it
  separated; its rules are pinned by pure cases, and the measured threshold is what stops it firing at the 0.52 s
  hesitation it did fire at under 0.5 s.
* **The switch ships off, and that is the honest landing rather than a finished one.** With the decoder prompt
  the app actually sends — none — turning it on invents a fragment in the English control ("based, no,") that the
  switch off does not produce, at every cap tried. The Polish win is real and measured, and the prompt arms above
  are the recipe for having both; flipping the default is one line, and it is a decision for the captain, not for
  this branch.
* **The prompt arms are single-recording measurements.** Four prompts were measured once each per recording. The
  instruction-shaped string recovering `pl-2`'s "spój"/"forkę" and removing a spurious "I" is a real observation
  on that recording, and it is the opposite of what the earlier brief expected; it is not a claim about that
  string in general, and no prompt was added to the app.
* **The English control's regression.** Not two words: with no prompt the switch on invents "based, no," there.
  The table says so, the sweep says no cap removes it, and the switch being off is the answer.
* **The `initialPrompt` A/B is 3 recordings × 2 states.** The prompt demonstrably changes the Polish decode; on
  this evidence clearing it costs more than it fixes, which is the opposite of the brief's expectation, and it is
  reported as measured rather than acted on. His stored preference is untouched.
* **The energy-based silence preview is a design input, not evidence** (taken outside the app, RMS over 20 ms
  frames, before any build; the app's own VAD numbers are the ones quoted above).
* **Timestamp mode is inert on purpose.** With *Show Timestamps* on, the decoder is handed the original audio
  (the trimmed timeline would not match the file), so no pause is measured and no boundary is inserted; that is
  the pre-existing reason the two modes differ, and the switch does not change it.
* **Parakeet (FluidAudio) is unaffected.** Its engine has no VAD stitching and no assembly step; the switch
  reaches the whisper path only, which is why the UI line names Whisper.
* **The measurement drives the file entry point.** `transcribeAudioDetailed(url:settings:)` is what the harness
  decodes; the hotkey path, `transcribeSamplesDetailed`, shares `performTranscription` and therefore the same
  policy, but no case decodes real audio through it — that needs a live dictation, and this branch is headless
  throughout.
* **One divergence from the old loop, unreachable.** `stitch` differs from the body it replaced only for a
  zero-length VAD segment (the old loop emitted 0.1 s of zeros on both sides of one, the new one only once);
  `whisper_vad_default_params` sets `min_speech_duration_ms = 250`, so the VAD cannot emit a segment shorter than
  0.25 s, and a test pins the two implementations equal over five segmentations.
* **No app launch, no hotkey, no keystroke delivery was exercised** — out of scope by the contract, and untouched
  by this change. Nothing about the tone prompt or model routing was touched either.

## Conflict map for the landing (base `3dcde52`, tip `635233a`, 8 commits)

`Settings.swift` — five **additive** hunks, none near the tone copy at ~`:271` or the model-list caption at
~`:1673`: `:73-78` the `@Published var longPausesEndSentences` and its `didSet`; `:384` one line in the
SettingsViewModel init; `:1034-1036` the `Settings` struct field; `:1081` one line in `Settings.init()`; and
`:1507-1531` the UI row appended inside the **Language Settings** card, immediately after the "Use Asian
Autocorrect" `HStack`. Resolve the card by "keep theirs and append mine"; take both sides in the struct and the
inits.

`Readme.md` — one new bullet in "Added by this fork" (`:53-55`, keep both sides) and a new **section 8** at
`:176-204`, which shifts the old headings: `### 9. Packaging and uninstall` → `### 10.`, `### 10. Developer
tooling` → `### 11.` (headings only; the tone work's re-worded warm-up paragraphs at ~`:461-462` are untouched by
this branch). Resolve by numbering: the pause section stays 8.

`Utils/AppPreferences.swift` — one **additive** hunk (`:169-193`, the new property and its doc comment) that
cannot conflict: the merged tip `877d19e` changes only `Settings.swift` and `Readme.md` relative to `3dcde52`
(`git diff --stat 3dcde52..877d19e`), so nothing else in the tree holds that file.

No shared code path with the merged tone work: this branch never reads `TransformService`, `TransformGuard`, the
warm-up, `TransformRuntime` or `DictationReport.guardRejection`/`guardNotice`, and its only shared surfaces are
`Settings.swift`, `Readme.md` and the additive preference.
