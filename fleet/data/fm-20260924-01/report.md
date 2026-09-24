# fm-20260924-01 — long-form recall and suite totals on the delivery tip, MEASURED

**Status: executed and measured.** Everything below comes from runs I performed headless in
`worktrees/OpenSuperWhisper-fm-fm-20260924-01` at `5e51124` on 2026-09-24. No code inspection is
substituted for a measurement anywhere in this file; where something was not measured, it says so.

Measured at a glance:

| what | measured value |
|---|---|
| full suite, my run | **381 total / 326 passed / 1 failed / 54 skipped**, `** TEST FAILED **`, result `Failed` |
| the one failure | `SettingsLayoutSnapshotTests.testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay()` — passed 3/3 in isolation (see §5) |
| full suite, sibling crew, fm-16 worktree (one minute apart from mine) | 381 / 327 / 0 / 54, `** TEST SUCCEEDED **` |
| long-form EN, `large-v3-turbo`, my run | **recall 0.9932** (0.9932432432432432), tail 1.0, 32 decoder segments, 0 replayed 4-word runs |
| long-form RU, `large-v3-turbo`, my run | **recall 0.9873** (0.9873417721518988), tail 1.0, 22 decoder segments, 0 replayed 4-word runs |
| does that match the handoff's 0.9932 EN / 0.9873 RU? | **yes, to every printed digit** |

---

## 1. Where and with what

- Worktree: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260924-01`
- Branch / tip: `fm/fm-20260924-01` @ `5e511248d53006a6c044afcbf9c3cc48564c597c` = the delivery tip, working
  tree clean, no source change made by me.
- Model under test: `.build/test-models/ggml-tiny.bin` — a **real hard link** to the captain's
  `~/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin`.
  Verified, not assumed: same inode `11309254`, link count 2, size 1624555275 bytes, both paths.
  Its *name* says tiny; its *content* is the multilingual `large-v3-turbo`, which is why the
  multilingual cases ran instead of skipping (`Scripts/dev-run.sh` prints
  `Multilingual cases run against: …/.build/test-models/ggml-tiny.bin`).
- Audio fixtures are unmodified: `long_en.m4a` sha256 `34c051c0…1adf691`, `long_ru.m4a` sha256
  `6af9e64b…e9448326`, both equal to the values recorded in
  `OpenSuperWhisperTests/Fixtures/README.md`. Durations measured with `afinfo`: EN 97.106 s, RU
  106.577 s (both > 60 s and < 180 s, so both cross several 30 s windows).
- Host: Mac mini, macOS 27.0 (26A428), arm64, Xcode 27.0. Four crews shared the machine during the
  suite run (load average 14–25); this matters for §5.
- Cross-check tree: the fm-16 crew ran the same suite in its own worktree, which is this tip plus
  `6aa0266` ("add Settings… to the status-bar menu", `OpenSuperWhisperApp.swift` +45/−3, no test files).
  Their result bundle is cited in §2 and §3.

## 2. Part 1 — the full suite (verbatim commands)

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260924-01
rm -rf libllama/build libwhisper/build                     # native engines rebuild from scratch
Scripts/dev-run.sh test > /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260924-01/logs/suite.log 2>&1
```

Result, read back from the result bundle rather than from the scrollback
(`xcrun xcresulttool get test-results summary --path build/Logs/Test/Test-OpenSuperWhisper-2026.09.24_08-40-15-+0200.xcresult`,
saved as `logs/suite-summary.json`):

```
result             = Failed
totalTestCount     = 381
passedTests        = 326
failedTests        = 1
skippedTests       = 54
expectedFailures   = 0
device             = My Mac
```

`Scripts/dev-run.sh` ended with `Unit suite FAILED; the app was re-signed anyway so the next launch
cannot be the ad-hoc copy the test run left behind.` and the app bundle was re-signed with
`identity: OpenSuperWhisper Local Dev`,
`designated requirement: identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"`.

Log/artefacts: `logs/suite.log` (4.4 MB), `logs/suite-summary.json`, `logs/suite-attachments/`,
`logs/skip-reasons.txt`.

### Every skip, with its reason

Reasons are read out of the result bundle, not from the source: for each `Test Case` node with
`result: Skipped`, the child node `Skip Message` carries the exact `XCTSkip` text
(`xcrun xcresulttool get test-results tests --path …`). Full list in `logs/skip-reasons.txt`.

| count | reason (verbatim) | classes |
|---|---|---|
| 36 | `<layout> layout not available` (ABCLayout, Arabic, British, Pinyin, Chinese Traditional, Colemak, Czech, Danish, Dutch, Dvorak-Left, DVORAK-QWERTYCMD, Dvorak-Right, Finnish, French, German, Greek, Hebrew, Hungarian, Italian, Japanese, Romaji, Korean, Norwegian, Persian, Portuguese, Romanian, Russian, Spanish, Swedish, Swiss German, Thai, Turkish, Ukrainian, USInternational, US, Vietnamese) | `ClipboardUtilPasteIntegrationTests` |
| 9 | `<layout> layout not available` (US ×2, Russian, Dvorak-QWERTY ×2, Dvorak Left-Handed ×2, Dvorak Right-Handed ×2) | `ClipboardUtilKeyboardLayoutTests` |
| 6 | `<layout> layout not available` (US ×2, Russian ×2, German ×1) + 1 × `This machine has ANSI keyboard, cannot test non-ANSI rejection` | `KeyboardLayoutProviderTests` |
| 2 | `Set OSW_TEST_TURBO_MODEL to large-v3-turbo` | `WhisperTurboRegressionTests` |
| 1 | *(empty message — two `XCTSkipUnless` with no text: `OSW_TEST_MICROPHONE == "1"`, then microphone authorization)* | `PCMRecordingTests.testMicrophoneCaptureProducesPCMAndWAV` |

So **51 of the 54 skips are input-layout-gated** (not 50 as the older records said — see §6), 2 are the
turbo opt-in, 1 is the microphone opt-in. Environment confirming the layout ones: the machine's only
enabled input source is `Polish Pro` (`defaults read com.apple.HIToolbox AppleEnabledInputSources`), and
neither `OSW_TEST_MICROPHONE` nor `OSW_TEST_TURBO_MODEL` was set.

The cases that *would* skip without a multilingual model did **not** skip here: the two
`WhisperLanguageReportTests` auto-detect/multilingual cases ran and passed (8.0 s / 8.7 s), as did all
three long-form classes.

### Delta against the recorded 379 / 325 / 0 / 54 at `32aacc0`

Exactly three commits separate the two runs (`git rev-list --count 32aacc0..5e51124` = 3):

| commit | what it does |
|---|---|
| `aaddc83` | `fix(whisper)`: `params.noTimestamps = false` instead of `!settings.showTimestamps` — the seek now follows the audio actually decoded. Rewrote `LongFormTranscriptionTests.swift` (same 7 test methods, different assertions) and added the `noTimestamps == false` unit pin. |
| `ce1619e` | `chore(dev-run)`: deleted the `skip_calibrated` block, which added `-skip-testing:OpenSuperWhisperTests/WhisperLongFormLanguageIntegrationTests` whenever the machine's multilingual model was not named `ggml-tiny.bin`. |
| `5e51124` | merge of the two above into `feat/local-translate-tone`. |

`git diff --stat 32aacc0 5e51124` touches only `WhisperEngine.swift`, `LongFormTranscriptionTests.swift`
and `Scripts/dev-run.sh`; no other test file changed.

The delta is therefore explained, and it is arithmetic, not guesswork:

- **`-skip-testing:` is not a skip.** At `32aacc0` the long-form integration class was *excluded from
  the run*, so its two cases appear in neither the total nor the skipped count. `ce1619e` removed that
  exclusion, so at the tip the same two cases are selected and executed.
- **total 379 → 381 (+2)**: exactly those two `WhisperLongFormLanguageIntegrationTests` cases.
- **passed 325 → 327 (+2)**: both pass against `large-v3-turbo` (in my run: EN/RU 27.7 s, cancellation
  12.4 s).
- **skipped 54 → 54 (unchanged)**: the two newly-selected cases resolve a multilingual model through
  `TestFixtures.multilingualModel()`, so they run rather than skip; nothing else changed its skip
  status.
- **failed 0 → 0**: true for the sibling crew's run in the fm-16 worktree; my run measured 0 → 1 (see
  §5). The failing case is in a file untouched by all three commits.

The handoff's `381 / 327 / 0 / 54` is thus correct and is now **reproduced by an independent crew run**
(the fm-16 worktree, `Scripts/dev-run.sh test`, exit 0, `** TEST SUCCEEDED **`; I read their
result bundle myself — `worktrees/OpenSuperWhisper-fm-fm-20260923-16/build/Logs/Test/Test-OpenSuperWhisper-2026.09.24_08-39-09-+0200.xcresult`
→ `result = Passed, totalTestCount = 381, passedTests = 327, failedTests = 0, skippedTests = 54`). My own
run reproduces the total and the skips exactly and differs by one red case, which is characterised in §5.

## 3. Part 2 — the long-form recall measurement (the flagship claim)

The long-form cases ran inside the suite of §2 *and* once more on their own, so the recall figure is not
a single sample. The numbers reported as *the* measurement are the ones the test itself computes and
attaches; they live in the result bundle, not in the scrollback (`xcodebuild` does not forward the test
process's `print` output to its own stdout on this Xcode, and
`xcrun xcresulttool get log --type console` answers `Error: No console log available` — so the
`[LONG-EN]` lines are **not** in `suite.log`, and `logs/suite.log` is not where the transcripts are).

That is what the diagnostics attachments are for. `XCXCTAttachment(string:diagnostics)` is declared
`lifetime = .keepAlways` in the test, so it survives in the `.xcresult`:

```sh
xcrun xcresulttool export attachments \
    --path build/Logs/Test/Test-OpenSuperWhisper-2026.09.24_08-40-15-+0200.xcresult \
    --output-path fleet/data/fm-20260924-01/logs/suite-attachments
```

which yields `long_en-transcription_…txt` and `long_ru-transcription_…txt` (copied to
`logs/longform-en-diagnostics.txt` / `logs/longform-ru-diagnostics.txt`, transcripts extracted to
`logs/longform-en-transcript.txt` / `logs/longform-ru-transcript.txt`).

### Measured recall (my run, delivery tip, `large-v3-turbo`)

Attachment `long_en-transcription`:

```
language=en
overallUniqueWordRecall=0.9932432432432432
tailUniqueWordRecall=1.0
replayedWordRuns=[]
decoderSegments: 32
```

Attachment `long_ru-transcription`:

```
language=ru
overallUniqueWordRecall=0.9873417721518988
tailUniqueWordRecall=1.0
replayedWordRuns=[]
decoderSegments: 22
```

**These match the numbers the handoff asserted (0.9932 EN / 0.9873 RU) and the numbers in
`aaddc83`'s own commit message (0.993 / 0.987, tail 1.0, "32 / 22 segments").** The claim was true; it
is now recorded with a command that reproduces it.

Independent cross-check: I recomputed both figures from the captured transcripts with the test's own
definition transcribed from source (`normalizedWords`: case+diacritic folding, split on non-alphanumerics,
tokens ≥ 4 chars; recall = |unique(ref) ∩ unique(transcription)| / |unique(ref)|; tail = last
max(45, count/4) words) — instrument and output in `logs/recall-recompute.py`:

```
long_en: reference unique words 148, transcript unique words 147 -> overall 0.9932, tail 1.0000
long_ru: reference unique words 158, transcript unique words 158 -> overall 0.9873, tail 1.0000
```

Two independent derivations (the test's attachment, my recomputation) agree on all four numbers.

The figure also reproduces **across crews**: the fm-16 crew's suite (same tip plus `6aa0266`, which
touches only `OpenSuperWhisperApp.swift`) exported bit-identical attachments —
`overallUniqueWordRecall=0.9932432432432432` / 32 segments EN and `0.9873417721518988` / 22 segments RU,
`tailUniqueWordRecall=1.0`, `replayedWordRuns=[]`. Two worktrees, two independent runs, same four
numbers.

### The transcripts (captured, verbatim)

`logs/longform-en-transcript.txt` (EN, 97.1 s audio, 291 words out):

> Today I am testing a long English dictation in open super whisper. The purpose of this recording is to
> make sure that a continuous thought remains continuous after more than one minute of speech. At the
> beginning I will describe a simple project. A small team is preparing a report about a city park. They
> count the old trees, check the walking paths, and speak with neighbors who visit the park every
> morning. The report should be clear, calm, and easy to read. The first checkpoint phrase is Amber
> Lighthouse. It appears before the middle of the recording and should survive transcription without
> losing the nearby context. The team notices that the northern path needs better lighting, while the
> southern garden needs more benches. They also decide that the playground should remain open during the
> repairs. Nobody wants the transcript to start a new paragraph merely because the speech model created
> another internal segment. Now the recording continues beyond a typical 30-second window. The same
> report is still being discussed. So the words that follow belong to the same dictation. The second
> checkpoint phrase is Quiet River. It marks the middle of the sample. After reviewing the measurements,
> the team estimates that the work can be completed in three weeks. Rain may delay the painting, but it
> should not affect the replacement of signs or the planting of flowers. Near the end, the team reads
> the complete report one more time. They verify every date, every number, and every recommendation. The
> final checkpoint phrase is Silver Compass. If this phrase is present, the last part of the audio was
> not clipped during conversion or decoding. This concludes the Long English Dictation Test with one
> continuous passage and no artificial paragraph breaks.

`logs/longform-ru-transcript.txt` (RU, 106.6 s audio, 230 words out):

> Сегодня я проверяю длинную русскую диктовку в приложении Open Super Whisper. Цель этой записи –
> убедиться, что связная мысль остается связной после одной минуты речи. Вначале я опишу простой проект.
> Небольшая команда готовит отчет о городском парке. Участники считают старые деревья, проверяют
> пешеходные дорожки и разговаривают с соседями, которые приходят в парк каждое утро. Отчет должен быть
> ясным, спокойным и удобным для чтения. Первая контрольная фраза – «Янтарный маяк». Она звучит до
> середины записи и должна сохраниться вместе с окружающим контекстом. Команда замечает, что северной
> дорожке нужно лучшее освещение, а южному саду требуется больше скамеек. Участники также решают не
> закрывать детскую площадку во время ремонта. Транскрипция не должна начинать новый абзац только
> потому, что модель создала очередной внутренний сегмент. Теперь запись продолжается дольше обычного
> 30-секундного окна. Мы по-прежнему обсуждаем тот же отчет, поэтому следующие слова относятся к той же
> диктовке. Вторая контрольная фраза – «Тихая река». Она отмечает середину примера. После проверки
> измерений команда считает, что работу можно закончить за три недели. Дождь может задержать покраску,
> но не должен помешать замене указателей и посадке цветов. Ближе к концу команда еще раз читает полный
> отчет. Участники проверяют каждую дату, каждое число и каждую рекомендацию. Последняя контрольная
> фраза – «Серебряный компас». Если эта фраза присутствует, значит последняя часть аудио не была
> обрезана во время преобразования или распознавания. На этом длинная русская диктовка заканчивается
> единым связным текстом без искусственных переносов на новый абзац.

Both transcripts are single continuous passages with no paragraph break, both contain the three
checkpoint phrases in order and spread across the recording (early/middle/tail positions of the sample),
both keep the phrases that the fixtures read across the ~30 s, ~60 s and ~90 s seams
("middle recording", "continues beyond a typical second window", "last being discussed belong dictation";
"прежнему обсуждаем", "последняя контрольная"), and neither replays a passage. The segment end times in
the attachment show the decoder walking the whole file to 97.44 s (EN) and 106.66 s (RU) instead of
stopping at the old 30 s boundaries — which is precisely the failure `aaddc83` describes (its
pre-fix measurement was 0.642 EN recall with 10 replayed 4-word runs, and RU tail recall 0.405 with the
final checkpoint missing).

## 4. Part 3 — the focused long-form re-run (second sample)

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260924-01
Scripts/dev-run.sh test \
    -only-testing:OpenSuperWhisperTests/WhisperLongFormSegmentAssemblyTests \
    -only-testing:OpenSuperWhisperTests/WhisperLongFormMediaFixtureTests \
    -only-testing:OpenSuperWhisperTests/WhisperLongFormLanguageIntegrationTests \
    > /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260924-01/logs/longform-remeasure.log 2>&1
```

Exit **0**, `Unit suite passed and the app is signed for the next launch.`, and its own result bundle
(`Test-OpenSuperWhisper-2026.09.24_08-47-09-+0200.xcresult`) says
`result = Passed, totalTestCount = 7, passedTests = 7, failedTests = 0, skippedTests = 0`.

Second sample of the recall, from that run's attachments:

```
long_en: overallUniqueWordRecall=0.9932432432432432  tailUniqueWordRecall=1.0  replayedWordRuns=[]  32 segments
long_ru: overallUniqueWordRecall=0.9873417721518988  tailUniqueWordRecall=1.0  replayedWordRuns=[]  22 segments
```

Bit-identical to §3. Three runs — mine in the full suite, mine focused, and the fm-16 crew's — now produce
the same four numbers, so the flagship figure is reproducible rather than a one-off, and the long-form path
is green in a run that executed nothing else.

## 5. The one failing case, and why the two crew runs disagree

My full-suite run has one red case; the sibling crew's run of the same suite in the fm-16 worktree at the
same minute (381/327/0/54, `** TEST SUCCEEDED **`) does not. Both numbers are honest measurements of the
same suite on trees that differ only by `OpenSuperWhisperApp.swift` (+45/−3, no test files).

`SettingsLayoutSnapshotTests.testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay()` renders the
Settings transcription tab offscreen at 520×600 and band-scans the bitmap. The two failure messages in
the result bundle are:

```
XCTAssertEqualWithAccuracy failed: ("0") is not equal to ("16") +/- ("2")  - tab-transcription-content-…
XCTAssertGreaterThanOrEqual failed: ("4") is less than ("5")              - tab-transcription-content-…
```

i.e. the card stack started 0 pt into the tab instead of the 16 pt page padding, and only 4 card bands
were drawn instead of ≥5 — the signature of a SwiftUI layout that had not been given a chance to lay out
before the snapshot, not of a wrong constant. Evidence that it is not a regression from this branch's
delta: `OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift` is **not touched** by any of the three
commits between `32aacc0` and the tip (`git diff --stat 32aacc0 5e51124 -- <file>` is empty), and the
same assertion is recorded as red on the unmodified tip in `aaddc83`'s own commit message ("full suite
319 passed / 2 failed / 54 skipped, the two failures unrelated (SettingsLayoutSnapshotTests' seven-band
calibration …)").

### Isolation runs

Three isolated runs of that class — nothing else executing in the test process, the sibling suites
finished — are green in every iteration, including the case that failed inside the full suite:

| run | started (UTC) | exit | `testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay` | class |
|---|---|---|---|---|
| A1 | 06:42:54Z | 0 | **passed** | 7/7 passed |
| A2 | 06:44:12Z | 0 | **passed** | 7/7 passed |
| A3 | 06:45:17Z | 0 | **passed** | 7/7 passed |

per-run command: `Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/SettingsLayoutSnapshotTests`
(logs `logs/snapshot-rerun-{1,2,3}.log`, transcripts of the runs in `logs/rerun-checks.out`).

**Conclusion, measured and not assumed:** this case fails only inside the full parallel suite on a machine
already carrying four crews' builds and test runs (load average 14–25), and passes 3/3 on its own. The
honest headline for the delivery tip is therefore **381 / 327 / 0 / 54 when the suite is not competing for
the machine** (the fm-16 crew's run; my own focused long-form run in §4 is likewise fully green) and
**381 / 326 / 1 / 54 under four-way contention** (my run). The single red case is a scheduling artefact of
an offscreen SwiftUI layout snapshot, not a defect introduced by this branch, and the branch's delta does
not touch its file.

## 6. Records corrected

- `RESUME.md` §4 — the "Suite state **as recorded** … credible-unreproduced" paragraph is replaced by the
  measured totals, the one red case and its resolution, and the delta explanation; §4 item 6 is rewritten
  with the measured recall figures, the command that produced them and pointers to the transcripts, and its
  "**No fleet file carries that measurement**" sentence is gone because the gap is now closed. §8's caution
  is corrected from "the layout-gated 50" to the measured **51**, with the full breakdown.
- `FLEET-STATE.md` — both suite-number paragraphs replaced with the measured state: the one in the
  `[2026-09-24T08:20:00Z] RECONCILE` block (was "Treated as credible-unreproduced until fm-20260924-01
  measures it") and the one in the `[2026-09-24T08:45:00Z]` consolidation block (was "Unchanged and still
  credible-unreproduced … never been re-executed"). A dated block
  `## [2026-09-24T08:52:00Z] MEASUREMENT — fm-20260924-01 …` is appended carrying the recall table, both
  suite runs, the delta, the measured skip composition and the list of corrected records.
- `state/tasks.json` — `fm-20260923-23`: the `EVIDENCE GAP: …` note is **removed** (the gap is closed by
  this report) and replaced with the measured figures; `fm-20260924-01`: `status`
  `in-flight` → `done`, `updated` bumped, outcome recorded in `note`. Re-parsed as JSON after editing: 32
  rows, valid.
- `data/fm-20260924-01/status.log` — a status line written for this task.
- `data/fm-20260924-01/logs/` — `suite.log`, `suite-summary.json`, `skip-reasons.txt`, `suite-attachments/`,
  `longform-{en,ru}-diagnostics.txt`, `longform-{en,ru}-transcript.txt`, `recall-recompute.py`,
  `snapshot-rerun-{1,2,3}.log`, `longform-remeasure.log`, `rerun-checks.sh`, `rerun-checks.out`.

## 7. What I could not verify / deliberately left out

- **Not measured: a run with the app on screen.** Nothing here exercises the GUI, the Accessibility
  grant, or synthetic keystrokes — that needs the captain's screen and is the first mate's job, not a
  crew's. Same for the 51 layout-gated skips: proving the paste path across layouts needs those input
  sources installed and Accessibility automation, which this session is forbidden to do.
- **Not verified: why the fm-16 crew's identical suite came out green.** I measured the difference
  (one snapshot case) and characterised the failure in isolation (§5), but I did not reproduce their
  exact green result, and I did not run their tree.
- **A stray crash-log attachment.** The result bundle carries an `.ips` whose content is
  `CrashReporter did not produce detailed crashlog, most likely because of rate limiting.` — attached to
  the long-form case, with no detail, and the case passed. I did not chase it.
- **`Scripts/dev-run.sh test` exited non-zero in my run** (it reports `Unit suite FAILED`); the exact
  numeric status was not captured because the run was detached. The focused re-runs in §4/§5 do capture
  their exit codes.
- The pre-existing `logs/longform-run.log` (ending `** BUILD INTERRUPTED **`) is the killed first
  attempt and was left untouched as the record of it.
