# fm-20260923-28 — Polish output runs on Qwen3-8B

Ship task, local-only. Branch `fm/fm-20260923-28` @ **`10a4c3d`** (13 files, +1276/−206), worktree
`worktrees/OpenSuperWhisper-fm-fm-20260923-28`, based on the delivery tip `23d873a` — no rebase was
needed, the primary checkout has not moved.

Finished by **Fm28Ship3**, a resumption. The first attempt was killed mid-flight at 10:20Z with 12
uncommitted files in the worktree; this run adopted them, diagnosed the one red case it left behind,
finished the report the measurements were missing, and re-verified what it could by execution. **The
last third of the plan was cut off by the run's budget — see "What this run did not finish" at the end,
which is the honest headline for whoever picks this up.**

## What was done

**Routing by output direction.** The built-in transform backend is chosen by the language the answer must
be written in, never by the stored model preference:

| Output language | Backend | Disk | RAM while loaded | Load |
|---|---|---|---|---|
| English | `qwen2.5-1.5b-instruct-q4_k_m` (shipped) | 986 MB | ~1.1 GB (allocation report); +1.06…1.43 GB as an in-process wired **step** | warm-cache warm-up 1.0 s (measured) |
| Polish | `qwen3-8b-q4_k_m` (new) | 5.03 GB | ~5.3 GB (allocation report); +4.94…5.63 GB as a wired **step** | warm-cache warm-up 1.01–1.14 s (measured); **cache-evicted load not measured** (see below) |

`TransformModelManager.modelID(forOutputLanguage:)` is the single source of that decision;
`TranslationService.transformInProcess` resolves it from the policy's `outputLanguage` and hands the model
to `TransformRuntime`, which loads (or swaps) exactly those weights. One backend is resident at a time: a
direction change unloads the other one first, so the wired memory is the model in use, not the sum. The
10-minute idle unload still clears the resident-model id, and its interval is now injectable so a test can
watch the timer fire (it does: released 2.31 s after a transform with the interval injected as 1 s, and
the shipped interval is asserted to be 600 s).

**Never a silent substitute.** With Polish selected and the 8B absent, the runtime throws
`.notInstalled(<the Polish model's name>)`, the transcript is pasted unchanged, and the Settings card says
so for that direction — with its own Download button, pinned to the same URL and sha256 in
`TransformModelManager.availableModels` (`d98cdcbd…`, 5 027 783 488 bytes). The 1.5B is never loaded for
Polish.

**Costs in the UI.** Both backends' disk and RAM are stated next to the Target language picker, and each
row of the (reused) model card carries its own state, cost, Download/Remove and the pin's provenance.
`SettingsViewModel` now takes an injectable `TransformModelManager`, so the card's words are proved against
a directory the test stages rather than only through a string assertion.

**Warm-up.** `TransformRuntime.warmUpIfEnabled()` (already called at recording start from
`AudioRecorder.swift:202`) now warms the model for the current target's output language, so the 8B's load
runs while the user is still speaking.

## The one red case, and what was wrong with the capture

`/tmp/fm28-suite.log` (full suite, 12:17 local) ended `** TEST FAILED **` with one failure, 384 passed:

```
XCTAssertEqualWithAccuracy failed: ("0") is not equal to ("16") +/- ("2") -
tab-transcription-content-transforms-off: the card stack ends 0 pt before the end of the tab,
expected the 16 pt page padding
```

The *top* padding assertion in the same capture passed; the bottom one measured **0 pt**, i.e. the capture's
last row carried card pixels. The shape of a *correct* capture of that case, now that the test prints its
geometry (`/tmp/fm28-layfix-evidence.txt`):

```
[snapshot] tab-transcription-content-transforms-off 503x2016: bands=[16-135, 156-316, 337-494,
  515-1503, 1524-1680, 1701-1828, 1849-1999] gaps=[20 × 6]
```

Seven cards, 16 pt of page padding above the first and below the last. So the red run's image was a capture
whose rect the content had outgrown — a capture taken mid-convergence, not a layout with missing padding.
Same family as this class's recorded behaviour (`FLEET-STATE.md`; `fm-20260924-01` §5: "0 pt into the tab
and only 4 card bands" under four concurrent suites, green 3/3 alone). It is not a regression from this
branch: the assertions were not touched, and the content renders with its padding in every green run.

**Isolated first, as the brief requires — and it passes alone.** Every run below is green:

| run | condition | result |
|---|---|---|
| A | isolated: `dev-run.sh test -only-testing:…/SettingsLayoutSnapshotTests` | `** TEST SUCCEEDED **`, 7/7 |
| B, C | isolated (`test-without-building`) | 7 passed each |
| D, E | + `PolishOutputBackendIntegrationTests` + `WhisperLongFormLanguageIntegrationTests` in parallel | 15 passed each |
| F | the six-class mix that produced the red run¹ | 108 passed |
| G, H, I | the same six-class mix, twice more after the capture below | 108 passed each |

¹ `SettingsLayout`, `PolishOutputBackendIntegration`, `TransformBackend`, `TransformModelManager`,
`SettingsExposure`, `TranslationService`. Logs: `/tmp/fm28-layout-isolated.log`, `/tmp/fm28-lay-alone-{1,2,3,4}.log`,
`/tmp/fm28-lay-load-{1,2}.log`, `/tmp/fm28-race-{load,alone}.log`, `/tmp/fm28-layfix-{1,2,3}.log`.

**What the capture does now**, before it asserts anything:

* waits for the scroll document's height to be quiet for **half a second** (five consecutive equal samples,
  because a tall `Text` measures in stages and two samples can agree mid-growth);
* then forces the pending layout of the **whole window tree** and draws — repeatedly, up to three seconds —
  accepting a capture only when **both the rect it draws and the raster it produces are unchanged** from the
  previous pass.

The failure this targets is a mid-convergence capture: the scroll view's usable width changes when its
scroller's space is decided, every wrapped caption re-wraps and the stack grows downwards — the last card
then lands on the image's last row, which is exactly the measured `0`. An instrumented probe
(`ZzLayoutRaceProbe`, throwaway, deleted) that samples that same case every 100 ms for six seconds *inside*
the failing class mix saw a document height of `2016.0` from the first sample and three consecutive correct
captures, so the instrumented path could not reproduce it — which is why the fix targets settling rather
than a value.

**No assertion was weakened, removed or loosened.** Padding, band count, card height and gap assertions are
exactly as they were, and a red run now prints the image size, the capture size and every band into its
failure message (the band summary also goes to the evidence file, because `xcodebuild` drops a test
process's stdout). The red run's own binary cannot be re-inspected any more — its test file was edited at
12:19:30, after that run's build — so whether the killed attempt's first version of the wait was in it
cannot be recovered; that is why the capture was strengthened instead of declared fixed.

## Measured, on this machine

**Routing, the missing-model path and the digest** (real weights; `/tmp/fm28-evidence.txt` and
`/tmp/fm28-layfix-evidence.txt`; each line is asserted by equality on the model id, not merely printed):

```
[routing] pl→en backend: qwen2.5-1.5b-instruct-q4_k_m
[routing] en→pl backend: qwen3-8b-q4_k_m
[polish-backend] en→pl: backend qwen3-8b-q4_k_m | policy English → Polish | didRunModel true
[polish-backend] en→pl output: Proszę wysłać raport.
[polish-backend] pl→en: backend qwen2.5-1.5b-instruct-q4_k_m | policy Polish → English | didRunModel true
[polish-backend] pl→en output: Please send the report tomorrow morning.
[polish-backend] pl→pl (Polish target): model calls 0, text untouched true
[polish-backend] missing 8B: attempted ["qwen3-8b-q4_k_m"], resident none, delivered the raw transcript
[polish-backend] mutated copy refused: The downloaded transform model does not match the pinned checksum
                  (expected d98cdcbd03e1…, got 52612ae7358f…).
[polish-backend] on-disk Qwen3-8B-Q4_K_M.gguf re-verifies against d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785
[polish-backend] /Volumes/home/zenon/models/Qwen3-8B-Q4_K_M.gguf verifies: 5027783488 bytes, d98cdcbd03e17…
[polish-backend] card notices with the 1.5B installed and the 8B missing: installed
                  ["qwen2.5-1.5b-instruct-q4_k_m"], for qwen3-8b-q4_k_m: "Without it, dictation that would
                  come out in Polish is pasted unchanged — the app does not fall back to Qwen2.5 1.5B
                  Instruct (Q4_K_M) for Polish, whose English→Polish output is what this backend exists
                  to replace."
[polish-backend] card notices once the 8B is staged: installed ["qwen2.5-1.5b-instruct-q4_k_m",
                  "qwen3-8b-q4_k_m"], for qwen3-8b-q4_k_m: none
[polish-backend] idle unload with the interval injected as 1 s: released true after 2.31 s
```

The missing-model case stages the 1.5B, leaves the 8B out and asks for Polish: the only backend ever
requested is the Polish one, nothing is resident afterwards, and the transcript is delivered unchanged —
while the card, pointed at that same directory, says in those words which direction is waiting and that the
small model is not its stand-in. The digest is exercised both ways against the real 5 GB file: an APFS clone
with one flipped byte goes through the app's own install path (`install(fileAt:model:)`, the step
`download(model:)` ends in), is refused with `checksumMismatch`, leaves nothing installed, and the untouched
file then re-verifies against the pin.

Where the two halves of "say so" live: the *dictation* keeps the transcript and its report line reads
"English → Polish — model call failed, transcript kept" (`DictationReport.transformLabel` +
`TransformPolicy.summary`, unchanged); the *model's name*, the RAM/disk cost and the Download button for
that direction are in Settings → Transcription. The name is not repeated in the per-dictation line — that
would mean a new error channel through `TransformOutcome`.

The pin itself, re-checked in this run: `shasum -a 256 ~/models/Qwen3-8B-Q4_K_M.gguf` = `d98cdcbd…c5745785`,
5 027 783 488 bytes, and the publisher's headers for the pinned URL (`x-linked-size: 5027783488`,
`x-linked-etag: "d98cdcbd…"`) agree. The 1.5B's pin (`1adf0b11…`, 986 048 768 bytes) matches its URL too.

**Wired memory, read as a step across a load** (`Pages wired down`, the instrument `fm-20260923-24`
validated; the absolute baseline drifts by GB on this machine, so only the step and the resident id carry
information):

| run | baseline | with the 8B | 8B step | after the swap to the 1.5B | 1.5B step |
|---|---|---|---|---|---|
| 1 | 2.26 GB | 7.88 GB | **+5.62 GB** | 3.69 GB | — |
| 2 | 2.91 GB | 7.85 GB | **+4.94 GB** | — | — |
| 3 | 4.18 GB | 9.81 GB | **+5.63 GB** | 5.24 GB | +1.06 GB |

fm-20260923-24's allocation report for the same weights: 5.33 GB (8B) and 1.08 GB (1.5B). The direction
change really evicts: the resident id changes and the wired level drops by the step.

**Latency, in-process** (the first call pays the load, steady is the same call with the weights resident):

| direction | backend | first call | steady | brief's baseline (fm-20260923-24, HTTP, same machine) |
|---|---|---|---|---|
| English → Polish | `qwen3-8b-q4_k_m` | 4.10–4.13 s | 1.01–1.06 s | 1.93 s mean (median 1.51 s) |
| Polish → English | `qwen2.5-1.5b-instruct-q4_k_m` | 1.36–1.38 s (that call also swapped the 8B out) | **0.18 s** | 0.30 s mean (median 0.22 s), the brief's "~0.29 s" |

The daily direction is therefore **not slower than before** — it is faster than the recorded baseline, and
its code path is unchanged (same model id, same prompt builder; the model is resolved one level earlier and
passed in). The one new cost for a user who alternates directions is the swap: the first Polish→English
dictation after a Polish one waits for the 8B to be unloaded and the 1.5B loaded (measured: 1.38 s total).

**Warm-up, warm cache** (the file was just hashed, which is the app's steady state after an install or a
Settings visit): 1.01 s and 1.04 s and 1.14 s across runs, i.e. the 8B's load plus a throwaway decode. The
first utterance right after a finished warm-up measured 7.0–7.4 s and the utterance overlapping the warm-up
7.9–8.1 s in those runs — but **those two numbers are contention-corrupted** (the 5 GB integration class
ran in parallel in the same invocation), and the clean machine-time run that would replace them was cut off;
see below.

## What this run did NOT finish

Stated plainly, because the brief asks for the measurements and the green suite and this run ran out of
budget for the last third of its plan:

1. **The cache-evicted (cold) load and the clean first-utterance latency are not measured.** The harness
    exists and was staged as `OpenSuperWhisperTests/ZzColdLoadProbe.swift` (a throwaway file, **deleted
    again, not in the commit**): it evicts the page cache by churning 14 GB through it, verifies the
    eviction with a read-rate probe of the model file, then measures the cold load, the 3.2 s-class number
    the brief's decision rests on; it also measures the utterance that races the warm-up, and the real
    600-second idle unload against the shipped interval. Driver: `/tmp/fm28-validate-and-probe2.sh`. Its run
    was cancelled by the budget; the only cold-load figure in this report is therefore fm-20260923-24's own
    3.21 s for these weights, not a fresh one.
2. **The full suite was not re-run on this commit.** The last full-suite run (12:17, before the capture fix)
    is `384 passed / 1 failed / 54 skipped` — the red case above. Everything after the fix is green, but in
    the class mixes listed in the table (108 cases max), not in the full suite. The required clean-state run
    is `rm -rf build libllama/build libwhisper/build && Scripts/dev-run.sh test` → `/tmp/fm28-suite-final.log`
    (driver ready at `/tmp/fm28-final-suite.sh`, which also refuses to run if a probe file is present).
3. **The last tweak to the capture loop is compile-checked, not re-run.** Runs F–I validate the version that
    waited for the geometry and required two identical rasters; the final version additionally requires half
    a second of quiet, lays out the whole window tree and has a three-second retry budget
    (`SettingsLayoutSnapshotTests.swift:129-195`). It parses and the earlier version it grew out of is 4/4
    green under the failing mix, but the shipped bytes have not been exercised.

Verified in this run, on the other hand: the pin (bytes and digest on disk, and the publisher's headers);
routing, missing-model and digest behaviour against real weights; the wired steps; both directions'
latency; the idle timer firing; the bundle's designated requirement, re-signed after the cancelled run and
read back as `certificate leaf` (never a bare `cdhash`):

```
Executable=…/build/Build/Products/Debug/OpenSuperWhisper.app/Contents/MacOS/OpenSuperWhisper
designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
```

## A correction the measurement forced

The brief's summary gives the shipped 1.5B "3/15 clean" with "invented content" for English→Polish. The
surviving measurement behind it (`fm-20260923-24/raw/verdicts.json`) says **4/15 clean, 2 with invented
content, 5 with broken grammar** (a second scorer: 1/15, the same 2 inventions). Nothing in the decision
changes — 11/15 with zero inventions against 4/15 with two is categorical — but the app's own words cited a
number the raw file does not contain, so `Readme.md` (two places) and the comment on
`TransformModelManager.polishOutputModelID` now cite the measured counts and the file they come from.

Two smaller things were corrected while finishing:

* `TransformModel.sha256`'s doc claimed the digest is "the same hash `Scripts/transform-server.sh` verifies
  with". That script serves the 1.5B only, so for the 8B the sentence over-claimed; it now says the
  catalogue is the only place either digest lives.
* `SettingsViewModel.isDownloadingTransformModel` was left behind by the per-row refactor — declared,
  written, never read (the card asks `isDownloading(_:)`). Deleted.

## Files changed (commit `10a4c3d`)

| File | Lines | What |
|---|---|---|
| `OpenSuperWhisper/TransformModelManager.swift` | +94/-… | the 8B catalogue entry (url/sha256/size/licence), `memoryBytes` per model, `modelID(forOutputLanguage:)` + `model(forOutputLanguage:)`, `notInstalled(modelName)`, the preference-driven `installedModelPath()` dropped |
| `OpenSuperWhisper/Llama/TransformRuntime.swift` | +153/-… | per-model loads, one resident at a time with a swap on a direction change, `warmUp(for:)`, `loadedModelID`, `unloadIfResident(modelID:)`, an injectable idle interval, model names in the log lines |
| `OpenSuperWhisper/TranslationService.swift` | +36/-… | `localModel(outputLanguage)` injection, the model passed into `localTransform` |
| `OpenSuperWhisper/Settings.swift` | +281/-… | per-backend rows with state/cost/Download/Remove, direction-aware missing-model notice, per-backend cost next to the target picker, direction-aware Advanced caption, injectable `TransformModelManager`, dead download flag deleted |
| `OpenSuperWhisper/Utils/AppPreferences.swift` | +9/-… | the routing note on `transformTargetLanguage` |
| `OpenSuperWhisperTests/PolishOutputBackendIntegrationTests.swift` | new, 443 | real weights: routing with per-direction latency, resident swap + wired steps, missing-model refusal plus the card's words against a staged directory, warm-up latency, idle unload, wrong-digest refusal + on-disk re-verify |
| `OpenSuperWhisperTests/SettingsLayoutSnapshotTests.swift` | +83/-… | the settling capture, the band diagnostics, the failure messages' geometry |
| `OpenSuperWhisperTests/TransformBackendTests.swift` | +123/-… | routing recorded per call, both directions, Polish clean-up, spoken == target makes no call, missing Polish backend never substitutes |
| `OpenSuperWhisperTests/TransformModelManagerTests.swift` | +63 | routing map, catalogue pinning, a stored preference cannot move the backends |
| `OpenSuperWhisperTests/SettingsExposureTests.swift` | +92 | the card's words: role, state with RAM+disk, the notice, and that it points away from the 1.5B |
| `OpenSuperWhisperTests/TestFixtures.swift` | +21 | `report(_:)`, which mirrors measurement lines to `OSW_TEST_EVIDENCE` |
| `Readme.md`, `packaging/conclusion.html` | +70, +14 | the two backends and their costs, the routing rule, per-dictation cost, the honest note, the limits |

## Not verified, or deliberately left out

* **The Settings card on screen.** Rows, notices and the picker caption are asserted through the view model
  (including against a staged directory) and the tab's layout is covered by the snapshot suite, but nobody
  has *looked* at it. GUI automation is forbidden here, so this is a **needs the captain's screen** item.
* **The HTTP hop of a real download.** `download(model:)` is `URLSession.downloadTask` → `install()`; the
  proof covers `install()`, the step that carries the digest, plus the publisher's headers. Re-downloading
  5 GB the machine already has would have proved nothing more.
* **A first use with a hand-placed file.** The app's Download button writes a verification stamp during
  install, so its first load is a stamp hit. A file dropped in by hand has no stamp: the first
  `verifiedPath` hashes 5 GB, which happens when Settings is opened (the card refreshes on init) rather than
  during a dictation — but a user who never opens Settings would pay it inside the first warm-up. Not
  measured end to end; noted rather than claimed.
* **The external-endpoint override.** Unchanged on purpose: it is handed the single model id configured in
  Advanced and serves both directions itself. Routing it by direction would be a new mechanism, which the
  brief forbids.
* **`Qwen3-30B-A3B`.** Still not wired, per the brief: ~18 GB wired and a 44 s load cannot honour the
  10-minute unload on a 32 GB machine.
* **In-process transform determinism.** Untouched: `Llama.swift` (the sampling chain, `dist(seed = 0)`) is
  not in this diff at all, so `fm-20260923-27`'s territory is untouched. `params.noTimestamps = false` and
  its rationale are intact at `WhisperEngine.swift:415`.
* **The disk-space guard.** `DiskSpaceUtil.requiredFreeSpace` is 10 GB; the 8B's download peaks at about
  10 GB (5 GB temporary plus 5 GB installed). Pre-existing and shared with the speech models, so unchanged
  — but marginal for the new backend.

## Notes for whoever lands this

* One commit on `23d873a`. Nothing pushed, nothing merged, no branch deleted, the primary checkout
  untouched.
* The measurement and diagnosis harnesses (`ZzColdLoadProbe.swift`, `ZzLayoutRaceProbe.swift`) were
  deleted before the commit; their drivers are in `/tmp` (`fm28-validate-and-probe2.sh`,
  `fm28-run-probe-and-loads.sh`) if the cold-load numbers are wanted again — re-add the probe file, build,
  and run it with nothing else on the machine.
* `AppPreferences.transformModel` no longer selects the local backend — the direction does. It is still the
  model id the external endpoint is asked for, which is what the Advanced field documents.
* The layout case has a record of going red under machine contention. The capture is now strict about
  settling and a failure prints its geometry, so the next red run says on its face whether the image was
  short (clipped capture) or the real layout changed.

## First-mate verification (added 2026-09-24T11:08:55Z)

Independent of the crew's own runs, two headless full-suite runs on this branch (`0a4f5f8`), alone on the machine:

| run | command | result |
|---|---|---|
| A, clean state | `rm -rf build libllama/build libwhisper/build && Scripts/dev-run.sh test` | 387 passed / 0 failed / 54 skipped, `** TEST SUCCEEDED **`, exit 0 |
| B, incremental | `Scripts/dev-run.sh test` | 387 passed / 0 failed / 54 skipped, `** TEST SUCCEEDED **`, exit 0 |
| signature | `codesign -d -r- …` | `certificate leaf = H"32266bcc…"`, designated requirement unchanged, never a bare `cdhash` |

The first verification run was **red on exactly one case** (386 passed / 1 failed / 54 skipped):
`SettingsLayoutSnapshotTests.testEveryTabLaysOutItsCardsWhateverTheSwitchesSay()`, with
`the card stack ends 0 pt before the end of the tab, expected the 16 pt page padding — 520x600 img,
bands ["16-135","156-316","337-494","515-599"]`. The `520x600` image is the **window**, not the tab
document (`503x2016`): `captureHosted(fullContent: true)` looked up the scroll view's document view with a
single `if let`, and when the hosted SwiftUI tree had not been built yet — XCTest runs test classes in
parallel (`parallelizable = "YES"`) — it silently fell through to the window capture. The assertion then
reported a padding defect for a capture that was never a tab capture. Fixed as `0a4f5f8`: wait up to 5 s
for the document view, `throw SnapshotError.renderFailed` naming the case and the wait if the tree never
materialises, and never fall back to a window capture for a `fullContent` request. No assertion and no part
of the settle/draw loop was touched; the two green runs above are the same bytes.

Not verified, and accepted as gaps: a cache-evicted cold load (the only figure remains `fm-20260923-24`'s
3.21 s for these weights, and the warm-cache warm-up path that hides it is measured at 1.01–1.14 s), and the
first-utterance-after-warm-up / racing-the-warm-up numbers, which the crew flagged as contention-corrupted in
its own report.
