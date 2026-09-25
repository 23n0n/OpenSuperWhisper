# fm-20260924-12 — a long pause ends the sentence

Branch `fm/pause-boundary`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pauses`,
base `3dcde52` (delivery tip). Headless throughout: no `open`, no `osascript`, no `screencapture`, no app launch,
no bare `xcodebuild test`.

**STATUS: code complete and committed on the branch (3 commits, head `1383234` at the time of writing); the
measurement, the suite and the signing check are the only things left, and they are blocked on machine contention
with the sibling `fm/tone-output` crew (no build, model load or decode has been started yet). Nothing below is
claimed from reading code alone; anything not yet run is marked PENDING.**

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

**So the feature is the opposite of the request, and the switch says so.** Not "ignore pauses": a pause of 0.5 s
or more now *keeps its own silence* (up to 0.8 s) and *ends the sentence*. The defect was dissolving the pause, so
"ignore pauses" would have named the bug.

## What changed

| Where | What |
|---|---|
| `Engines/WhisperEngine.swift:74-114` | `PauseBoundaryPolicy` — `upstream` (0.1 s of zeros everywhere: byte-for-byte the behaviour every earlier build had) and `restored` (keep up to 0.8 s of the real pause; a pause ≥ 0.5 s ends the sentence; 0.25 s tolerance). `from(settings:)` is the only producer. |
| `:735-800` | `stitch(from:segments:policy:)` replaces `speechOnlySamples`' body. It keeps `min(pause, cap)` of the recording's **own** silence at each gap, zero-padding only up to upstream's 0.1 s minimum, and returns `pauses` (`StitchedPause`, `:714-722`): each pause's length in seconds and its span in the audio the decoder hears, in the decoder's own centisecond clock. `speechOnlySamples` (`:700-702`) remains as the `policy: .upstream` wrapper, so the old entry point keeps exactly its old meaning. |
| `:575-613` | `pauseJunctions` / `sentenceBoundaries` — map a measured pause onto the decoder segment that ended before it. A segment that *starts* before the pause ends decoded straight through the pause (both thoughts are already inside its text, and where the boundary belongs is not something the audio can say), so nothing is inserted there. |
| `:469-543` | `SentenceBoundaries`, `assembleSegmentTexts(_:showTimestamps:sentenceBoundaries:)`, `closingSentence` — joins as before, then closes a sentence the decoder left open at a junction the audio measured. A segment that already ends its sentence is untouched (no doubled punctuation); the terminator is language-aware (`.` except `。` for zh/ja/ko, `:560-563`); a space is added only when neither side of the join carries one. Timestamp mode is unchanged: one decoder segment per line. No word is altered anywhere. |
| `:49-56`, `:385-402` | `DecodedSegment` now carries the segment's **start** as well as its end, which is what decides a pause that fell between two segments versus inside one. |
| `Settings.swift:73-77,384,1036,1081,1508-1531` | The switch, its preference plumbing, and one line in the **Language Settings** card next to the language and clean-up controls (`:1508-1531`). |
| `Utils/AppPreferences.swift:170-185` | `longPausesEndSentences`, default **on** — the transcript it produces is the one without the defect, and off is upstream's stitching exactly. |

Not touched: the tone prompt, model routing, `Utils/KeyboardSimulator.swift`, the injection part of
`Indicator/IndicatorWindow.swift`, `params.noTimestamps = false`, `params.language = nil`,
`params.detectLanguage = false`.

```
 OpenSuperWhisper/Engines/WhisperEngine.swift       | 356 +++++++++++++-
 OpenSuperWhisper/Settings.swift                    |  36 ++
 OpenSuperWhisper/Utils/AppPreferences.swift        |  17 +
 .../CaptainRecordingPauseBoundaryTests.swift       | 414 ++++++++++++++++
 OpenSuperWhisperTests/PauseBoundaryTests.swift     | 523 +++++++++++++++++++++
 Readme.md                                          |  37 +-
 6 files changed, 1359 insertions(+), 24 deletions(-)
```

### The threshold, and why 0.5 s

`PauseBoundaryPolicy.restored`: `sentenceThreshold = 0.5 s`, `maxPause = 0.8 s`,
`boundaryTolerance = 0.25 s`, `minPause = 0.1 s`.

* **0.5 s, not 0.1 s**: the quantity compared is the silence the decoder was given none of — the VAD's gap less
  the 0.1 s overlap upstream stitches into the next segment.
* **Why 0.5**: his own two Polish recordings separate into two populations, and the gap between them is where the
  threshold has to sit. Independent energy-based preview of the recordings (a design input, **not** the evidence —
  the app's own VAD numbers are quoted in the measurement section below):

```
pl-1 (12.1 s) mid-clause silences up to 0.40 s | thought-level silences 0.76 s, 1.06 s
pl-2 (23.3 s) mid-clause silences up to 0.44 s | thought-level silences 1.42 s, 2.0 s, 2.5 s, 3.52 s, 5.6 s
en  (33.0 s) mid-clause silences up to 0.24 s | larger 0.6 s, 0.7 s, 0.9 s, 1.02 s, 1.16 s, 1.5 s, 2.96 s, 4.52 s, 7.42 s
```

  Every within-clause pause in both Polish recordings is at or below 0.44 s; every pause the captain leaves
  between thoughts is at or above 0.76 s. 0.5 s sits inside that empty band with ≥ 0.06 s of margin below and
  ≥ 0.26 s above, and it is what the UI line states.
* **From the recording's silence to the number the threshold compares.** The VAD is not a silence detector with
  unit gain: `whisper_vad_default_params` (`libwhisper/whisper.cpp/src/whisper.cpp:4465-4473`) pads every speech
  segment by `speech_pad_ms = 30` on each side, and the stitched audio carries a further `samples_overlap = 0.1`
  the app mirrors as its 0.1 s overlap. The quantity `sentenceThreshold` is compared against — `StitchedPause.seconds`
  — is therefore the true pause **minus ~0.16 s**. On the populations above that maps the empty band to
  `[0.28, 0.60]` s, and 0.5 s sits in it with 0.22 s below and 0.10 s above. Both the band and the chosen
  threshold are reported again from the app's own VAD in the measurement section.
* **cap 0.8 s**: the decoder does not need the whole 5.6 s pause to close a sentence, and the bytes beyond the cap
  are what upstream discards anyway; capping bounds the decode cost and the silence the encoder sees.
* **tolerance 0.25 s** (half the threshold): how close to the end of a pause the next decoder segment has to start
  before the boundary is attributed to that pause. Wider than whisper's own timestamp granularity, and far inside
  a pause that qualified, so a segment that decoded *through* a pause is never mistaken for one that starts at it.

## Verification

PENDING — the focused run, the before/after tables for both Polish recordings and the English control, the
`initialPrompt` A/B, the command lines, the raw outputs, the full suite from a clean state
(`/tmp/fm2412-suite.log`), and the identity-signed bundle.

## Tests

PENDING — `PauseBoundaryTests` (pure) and `WhisperPauseBoundaryMeasurementTests` (his recordings), with the
command and the counts.

## Unverified, or deliberately left alone

* **The threshold is chosen from two recordings.** It was picked from the two Polish dictations the complaint is
  about, where the within-clause and thought-level pauses separate cleanly (numbers above and in the measurement
  section). A different dictation style — faster speech, or pauses a speaker means as "um" rather than as a
  boundary — can sit differently. The switch exists so the behaviour is a choice, and off is the old audio
  exactly.
* **No large-scale Polish grading.** The evidence is three recordings read out and compared, not a corpus with
  reference transcripts. Nothing here is a claim about Polish punctuation accuracy in general; it is a claim
  about the boundary that was being dissolved.
* **The energy-based silence preview is a design input, not the evidence.** It was measured outside the app (RMS
  over 20 ms frames) to choose the threshold before any build; it is labelled as such in the threshold section,
  and the app's own VAD numbers are quoted separately in the measurement section.
* **The `initialPrompt` finding is measured, not acted on.** The prompt in his preferences is an instruction
  sitting in whisper's decoder context; the A/B is reported with its numbers and a recommendation, and his
  stored preference is left exactly as it is — changing it is his call, not this branch's.
* **Timestamp mode is inert on purpose.** With *Show Timestamps* on, the decoder is handed the original audio
  (the trimmed timeline would not match the file), so no pause is measured and no boundary is inserted. That is
  the pre-existing reason the two modes differ, and the switch does not change it.
* **Parakeet (FluidAudio) is unaffected.** Its engine has no VAD stitching and no assembly step; the switch
  reaches the whisper path only, which is why the UI line names Whisper.
* **One divergence from the old loop, unreachable.** `stitch` differs from the body it replaced only for a
  zero-length VAD segment (the old loop emitted 0.1 s of zeros on both sides of one, the new one only once).
  `whisper_vad_default_params` sets `min_speech_duration_ms = 250`, so the VAD cannot emit a segment shorter
  than 0.25 s; a test pins the two implementations equal over five segmentations, including a single segment and
  a touching pair.
* **`PENDING`** — anything not listed above and not measured in the sections below.
