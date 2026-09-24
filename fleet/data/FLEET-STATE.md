# Fleet state — OpenSuperWhisper voice keyboard (single source of truth)

Updated: 2026-09-23. Repo: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo` (fork of Starmel/OpenSuperWhisper).
Delivery branch: `feat/local-translate-tone`. Fleet home: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet`.

## Captain's asks (all of them)
1. Local Polish→English translation + tone adjustment + delivery by simulated keystrokes (clipboard untouched).
2. Language awareness: English dictation must never be translated; Polish translates only when switched on.
3. Tone must have its own user toggle, independent of translation.
4. One package: install and uninstall in a single idempotent operation, nothing connected by goodwill.
5. Press-and-hold push-to-talk: press a key to start recording, release to stop.
6. Input Monitoring permission must not be required.
7. Ship only finished, verified work; report once at the end.

## Landed on the delivery branch (verified)
- `81d892b` dev signing: `Scripts/dev-signing-identity.sh` (self-signed `OpenSuperWhisper Local Dev`, own keychain), `Scripts/dev-sign.sh` (identity-based Designated Requirement, survives rebuilds), `Scripts/dev-run.sh` (build with `ENABLE_DEBUG_DYLIB=NO`, sign, run).
- `faec335` language-aware gate + two switches: `Utils/LanguageDetector.swift`, `TransformPolicy` table, optional-tone prompts, `toneEnabled` pref (default false, no migration), engine `fullLangId` plumbing, Readme table. `transformIfEnabled(_:sourceLanguage:)` keeps its never-throws contract; recordings still saved raw before transform.
- `f9c2f00` (merge of fm-08): vendored llama.cpp on a single unified ggml, in-process runtime (`OpenSuperWhisper/Llama/Llama.swift`, `TransformRuntime.swift`), app-managed sha256 model download (`TransformModelManager.swift`), packaging (`packaging/build-pkg.sh`, `distribution.xml`, `uninstall.sh`, `preinstall`), uninstall service + Settings/Advanced entry point, `Scripts/build-native.sh`, `Scripts/verify-packaging.sh`, CI updated, libomp coupling removed, `ggml-tiny.en.bin` bundled.
- Model: `Qwen2.5-1.5B-Instruct-Q4_K_M` (986 MB, sha256 `1adf0b11…6c3370`); pre-seeded at
  `~/Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models/qwen2.5-1.5b-instruct-q4_k_m.gguf`.
- Evidence: unit suite 286 passed / 1 red case (`NoMicrophoneGuardTests` — deterministic, long mislabelled a "mic-state dependent flake"; root cause found and fixed by fm-20260923-22); packaging harness 39/39; contract harness 162/162; in-process decode proven by `LlamaRuntimeIntegrationTests` 3/3 against real weights (Metal 0.25 s/transform, RSS 1.32 GB warm; CPU-only 2.27 GB).

## Open / in flight

> **Superseded 2026-09-24.** Nothing in this fleet is running. Every item below either landed on the
> delivery branch or was cancelled at the captain's halt; `fm-20260923-10` completed at 15:25Z on 09-23.
> See the reconcile block at the end of this file for the corrected state.

- `fm-20260923-10` (crew, running): (a) keystrokes stop after the first dictation — instrument live Accessibility trust, log each dictation, prove mechanism A (trust lost) vs B (state machine), fix; (b) remove the Input Monitoring requirement by replacing the listen-only `flagsChanged` tap in `ModifierKeyMonitor.swift:139` with an Accessibility-gated implementation; (c) distinct bundle id for dev/CI builds; (d) fix the "Apply tone" caption that wrongly says Polish is never toned.
- Trigger semantics for press-and-hold: `ModifierKeyMonitor` + `ShortcutManager.handleKeyDown/Up` with `holdThreshold` 0.3 s — press starts, release after 0.3 s stops, quick tap toggles. Set `modifierOnlyHotkey = leftOption`, `holdToRecord = true`. Key-combination mode cannot stop on release; a held key *combination* would need a code change.
- Captain's live prefs: `translateEnabled = 1`, `toneEnabled = 1` (formal), `whisperLanguage = auto`, `selectedWhisperModelPath` = Turbo V3 in app-owned storage, `transformModel = qwen2.5-1.5b-instruct-q4_k_m`, `modifierOnlyHotkey` to be set to `leftOption`.

## Known traps (do not repeat)
- `run.sh` builds unsigned; use `Scripts/dev-run.sh`, otherwise the Accessibility grant dies on rebuild.
- Multiple copies with the same bundle id poison the TCC list; crew/test builds must use a different bundle id.
- `llama_tokenize` returns the required capacity as a negative number — never feed it to `Array(repeating:count:)`.
- `feat/local-translate-tone` has diverged from crew branches twice; use `--no-ff` merges and expect Readme conflicts.
- The commercial `Superwhisper` app runs alongside and is easily mistaken for this fork (its Settings has no Translation & Tone section).
- The HTTP backend (`Scripts/transform-server.sh`, port 1919) is now optional — the app runs inference in-process.

## Final state (2026-09-23, delivery tip 550d9d1)

- App built and signed (identity DR, cert leaf 32266bcc…), running from the primary checkout; Debug VAD abort fixed per-configuration (llamafile kernels off in Debug only, Release unchanged).
- Verification: 357 unit tests executed, 0 failures, 58 skipped (serial Debug); packaging harness 39/39 on Debug and Release apps; external-endpoint contract 162/162; uninstall proven in scratch roots 25/25 twice and with the app absent; Release .pkg built (87 MB, unsigned — 0 signing identities on this machine).
- In-process transform: llama.cpp vendored on one unified ggml; Qwen2.5-1.5B-Instruct Q4_K_M staged in app-owned storage with a verified stamp; transform 0.19-1.0 s, RSS ~1.27 GB with both engines warm.
- Captain settings: hold Left Option to record, release to stop; translation on; tone off; language Auto-detect; Turbo V3 multilingual model.
- Input Monitoring is no longer used or required anywhere (no IOHID symbols in the binary). Accessibility is the only event-related grant.
- The HTTP transform server is stopped; the app no longer needs it.
[2026-09-23T18:25:38Z] full suite on the merged tip 32aacc0: 379 total, 325 passed, 0 failed, 54 skipped, result Passed, exit 0, app identity-signed. Skips accounted: ClipboardUtilPasteIntegrationTests (35) + ClipboardUtilKeyboardLayoutTests (9) + KeyboardLayoutProviderTests (6) skip when an input-source layout (US/Dvorak/Russian/...) is not installed on this machine; PCMRecordingTests (1) needs OSW_TEST_MICROPHONE=1 + mic authorization; WhisperTurboRegressionTests (2) needs OSW_TEST_TURBO_MODEL; WhisperLongFormLanguageIntegrationTests skipped by the calibrated-model guard. Registered fm-26: the delivery path (synthetic keystrokes) deserves a layout-independent test using the active input source, since 50 of the 54 skips are layout-gated.

## [2026-09-24T05:30:54Z] STOP — captain called a halt

All crews cancelled (fm-20260923-16, -17, -27) and fm-20260923-15 told to stop and commit nothing further.
All crew app instances killed; no model servers left bound; the captain's app instance (pid 99430) is
running on the delivery tip. Delivery tip: 5e51124 on feat/local-translate-tone, working tree clean.

### Preserved mid-flight work (NOT merged, recoverable)
- fm/fm-20260923-16: 8e8b92a "feat(menu): add Settings… to the status-bar menu" + 1 uncommitted file
  (OpenSuperWhisperApp.swift) in worktree OpenSuperWhisper-fm-fm-20260923-16.
- fm/fm-20260923-15 (fm-25 assignment): 5263999 "feat(settings): show and manage the speech models that
  are on disk (G-04, G-05, G-06, G-07)" in worktree OpenSuperWhisper-fm-fm-20260923-15.
- fm/fm-20260923-17 (clean-up + glossary + guard, uncommitted): 7 modified + 3 new files in worktree
  OpenSuperWhisper-fm-fm-20260923-17 — AppErrorCenter, ContentView, WhisperEngine, IndicatorWindow,
  TranscriptionService, TranslationService, AppPreferences; new: DictationReport.swift,
  Utils/DictationScrubber.swift, Utils/SpeechModelLanguageGate.swift.
- fm/fm-20260923-27 (determinism): no changes made.

### Corrected inventory from the crews at the halt (from fm-20260923-15)
- Committed on fm/fm-20260923-15: 5263999 — G-04 Remove per row with space freed (both engines), G-05
  Installed models (N) + in-use marker + Use/Verify/Remove + Selected model line, G-06 real sha256
  verification against the digests Hugging Face publishes (pinned in the catalogue), G-07 fallback as a
  notice instead of a print. Was green: 7/7 ModelStorageTests. NOT merged.
- Uncommitted in that worktree: G-02/G-03 (Permissions card atop the Shortcuts tab: Accessibility +
  Microphone state + Open System Settings), G-10 (Clipboard & Paste subtitle: keystrokes, no clipboard,
  Accessibility required), G-11 (Debug Mode wired through Settings.debugMode into WhisperFullParams;
  orphan qwen3Variant key deleted), G-12 (Advanced → Welcome Screen card resetting hasCompletedOnboarding),
  updated SettingsLayoutSnapshotTests rendering every tab whole, and SettingsExposureTests (2 tests, green),
  plus a last unbuilt polish pinning the bundled model's published digest so Verify covers it.
- Not done because of the halt: that last polish and the four uncommitted files were never built or tested
  together, and no rebase/test/sign pass was run on them.
- fm/fm-20260923-16: 8e8b92a (menu Settings…) committed + OpenSuperWhisperApp.swift uncommitted.
- fm/fm-20260923-17: uncommitted as recorded above (clean-up, glossary, guard, language display).

## [2026-09-24T08:20:00Z] RECONCILE — handoff corrected against disk

Written by a session that started in a different working directory, found this fleet by search, and verified
every claim below against the repository. Nothing was merged, pushed, or deleted; no app or crew was started.

**Verified facts (delivery tip `5e51124` on `feat/local-translate-tone`, working tree clean, 160 tracked
files, 60 commits ahead of `origin/develop`)**

- Every commit this file claims as landed is an ancestor of the tip: `81d892b`, `faec335`, `f9c2f00`,
  `bd5ad0e`, `92fc012`, `4d1e281`, `93978c8`, `2a2c213`, `95c7e2c`, `aaddc83`, `ce1619e`.
- 12 of 15 local `fm/*` branches are merged. Exactly three are not: `fm-15` (`5263999` + 5 uncommitted
  files), `fm-16` (`8e8b92a` + 1 uncommitted), `fm-09` (`98c63fd`, a duplicate whose change is already in
  the delivery tree via `dev-run.sh`).
- The preserved mid-flight inventory matched the worktrees file-for-file: fm-16 = 1 dirty entry; the
  fm-15/fm-25 worktree = 3 modified + 1 modified test + 1 new test; fm-17 = 7 modified + 3 new; fm-27 = no
  changes at all.
- The delivery branch is **unpushed**: `git ls-remote origin` carries no `feat/local-translate-tone`.
  *(Superseded later the same day: the work was published as `main` on `origin` — see the PUBLISHED entry at the
  end of this file. As written, this line was true when the reconcile ran.)*

**Corrections made to the records**

- `state/tasks.json`: 31 rows after reconcile. `fm-20260923-23` was `in-flight` while its merge was the
  delivery tip — now `done` and pointing at its worktree/branch. `fm-15`/`fm-25` were `parked`/`done` with no
  worktree recorded — both now `ready` and pointing at the SAME worktree and branch, with the id collision
  stated. `fm-16`/`fm-17` were `in-flight` — now `parked` with their real worktrees. `fm-09` carries a note
  that its unmerged commit is a duplicate. `fm-18` registered as folded into `fm-17`. Missing briefs closed:
  `fm-26`, `fm-27`, `fm-28` and the three new tasks below now have real briefs (fm-27/28 previously held the
  unfilled `{TASK}` template, which is not dispatchable).
- `data/RESUME.md`: added the `FIRSTMATE_HOME` requirement, the unpushed state,
  corrected provenance for the suite numbers (§4), the corrected worktree/branch mapping (§6), a
  rewritten priority list (§7), and four new cautions (§8).
- `data/backlog.md`: rewritten to reality — the shipped entries marked shipped, the open ones in priority
  order, the fm-23 evidence gap stated.

**New tasks registered (2026-09-24; briefs written, nothing dispatched; one withdrawn — see below)**

- `fm-20260924-01` scout — re-measure and RECORD the fm-23 long-form evidence and the suite totals on the
  delivery tip. `fm-20260923-23` left no `status.log` and no report; the recall figures 0.9932 EN / 0.9873 RU
  quoted in RESUME exist in no other fleet file.
- `fm-20260924-02` ops — **WITHDRAWN the same day, by the captain's correction**: it recorded the agent
  session's own sandbox limit as a project task and put it at the top of the queue. The project builds in a
  normal terminal; how an agent session happens to be sandboxed is not project work. The observation itself
  is kept here for the record only: inside an omp sandboxed session `/Applications` is not readable, so
  `xcodebuild` cannot run and `Scripts/dev-run.sh` dies with `CMake Error: Xcode 1.5 not supported` after
  `xcrun` fails to `dlopen` `libxcrun.dylib`. Nothing in the project's build documentation was changed for
  it, and no build path was altered. This is a fact about the agent runtime, not about the fork.
- `fm-20260924-03` ops — preservation: the unpushed branch, three unlanded branches and three worktrees of
  uncommitted work all live on one disk, and a branch-only backup would drop the uncommitted sets.

**Suite numbers, MEASURED 2026-09-24 by `fm-20260924-01`** (superseding the "credible-unreproduced" note)

This file's last recorded run *was* 379 total / 325 passed / 0 failed / 54 skipped at `32aacc0`, and
RESUME's 381/327/0/54 was consistent with it plus the two long-form cases `ce1619e` un-skipped
(327+54=381) but had never been re-executed after the final merge. It now has been, twice, on two trees at
the tip:

- fm-16 crew, `worktrees/OpenSuperWhisper-fm-fm-20260923-16` (tip + `6aa0266`, which touches only
  `OpenSuperWhisperApp.swift`): **381 / 327 / 0 / 54**, result `Passed`, `** TEST SUCCEEDED **`.
- fm-20260924-01 crew, `worktrees/OpenSuperWhisper-fm-fm-20260924-01` (the tip, clean):
  `rm -rf libllama/build libwhisper/build` then `Scripts/dev-run.sh test` → **381 / 326 / 1 / 54**, result
  `Failed`. The single red case is
  `SettingsLayoutSnapshotTests.testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay()` (an offscreen
  render whose card stack came out 0 pt into the tab instead of 16 ±2 and 4 bands instead of ≥5); it passed
  **3/3** when that class ran in isolation, and its file is untouched by the three commits between the runs,
  so it is machine contention under four concurrent suites, not a regression.

Delta against `32aacc0`, explained from the three commits between the runs (`aaddc83`, `ce1619e`, `5e51124`
= `git rev-list --count 32aacc0..5e51124`): **+2 total, +2 passed, skips unchanged at 54**. `ce1619e`
deleted the `skip_calibrated` block that made `dev-run.sh` pass
`-skip-testing:OpenSuperWhisperTests/WhisperLongFormLanguageIntegrationTests` whenever the machine's
multilingual model was not named `ggml-tiny.bin`; an excluded case is counted in neither the total nor the
skip count, so removing the exclusion adds exactly those two cases, and both pass.

Skip composition, measured from the result bundle (not inferred): **51 layout-gated** (36
`ClipboardUtilPasteIntegrationTests` + 9 `ClipboardUtilKeyboardLayoutTests` + 6
`KeyboardLayoutProviderTests`; this machine's only enabled input source is `Polish Pro`) + **2**
`WhisperTurboRegressionTests` (`OSW_TEST_TURBO_MODEL` unset) + **1** `PCMRecordingTests` (microphone
opt-in). The older "50 of the 54 are layout-gated" figure undercounted
`ClipboardUtilPasteIntegrationTests` by one.

Long-form recall was re-measured in the same run: **0.9932 EN / 0.9873 RU** unique-word recall, tail recall
**1.0** in both, **0** replayed four-word runs, 32 EN / 22 RU decoder segments, against
`ggml-large-v3-turbo`. Full evidence, commands and transcripts: `data/fm-20260924-01/report.md` and
`data/fm-20260924-01/logs/`.

**Operational notes**

- The fleet lock was stale (owner pid 2725, dead since 09-23); reclaimed on 2026-09-24 and re-held.
- A second fleet home exists at `Documents/deepseek_general/firstmate-home`. The skill derives the home
  from the working directory, so any session that does not export `FIRSTMATE_HOME` may read the wrong fleet.

## [2026-09-24T08:45:00Z] WORKSPACE CONSOLIDATION + fm-27 premise falsified

**Layout.** The captain's instruction ("move all work to a well-structured folder") is done. New root
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/`: `repo/` (the checkout), `worktrees/` (fm-15, -16,
-17 — the only worktrees holding unmerged work), `fleet/` (this home), `docs/` (the fork plan and study),
`archive/` (the verified bundle). `README.md` at the root records the layout, the build entry point and
the restore procedure. `/Volumes/home/zenon/firstmate-home` is now a symlink to `fork/fleet`, so an
un-updated path still resolves. Absolute paths in 48 fleet record files were rewritten to the new root.

**Freed space.** The five merged crew worktrees (fm-12, -13, -22, -23, -27) were removed: ~11 GB of build
products. Their commits were already in the delivery branch and every branch is in the archive bundle.

**Repairs the move required** (a moved git tree is not automatically a working git tree): `git worktree
repair` for the worktree admin links, and a hand repair of the moved worktrees' submodule links — git
2.54 stores those relative, both the submodule's `.git` file and the `worktree` value in its admin
config, and both point at the old parent directory. Verified afterwards: the main checkout is clean, each
preserved worktree reports exactly its recorded entry count (fm-15: 5, fm-16: 1, fm-17: 10), and every
submodule is clean in all three. The CMake caches under `libllama/build` and `libwhisper/build` were
deleted (they embed the old absolute source path) and the moved tree was rebuilt through
`Scripts/dev-run.sh build` to prove it builds from the new location.

**fm-20260923-27 (in-process determinism) — premise falsified, not dispatched.** A read-only scout read
the delivery tip: the sampling is already fully seed-pinned. `Llama.swift:270-278` builds
`top_k(40) -> top_p(0.95) -> min_p(0.05) -> temp(0.2) -> dist(seed = 0)`; the chain is created per request
and freed immediately (`Llama.swift:158-159`) with the KV cache cleared (`:156`), so no RNG state carries
between dictations, and no `llama_set_rng_seed` exists anywhere. `libllama/llama.cpp`
`src/llama-sampler.cpp:1399-1409` seeds `std::mt19937` from that literal seed, and `:340-353` shows only
`LLAMA_DEFAULT_SEED` randomises. The one genuinely unseeded path is the optional external HTTP backend
(`TranslationService.swift:334` sends `temperature 0.2` and no seed), which is off by default
(`AppPreferences.swift:296`). Therefore, if the in-process path does still differ run to run, the cause is
backend reduction nondeterminism (Metal / threaded accumulation), not seed handling: a fixed seed cannot
remove it and greedy sampling would only make it rarer. The task as briefed would have changed nothing
that matters. Decision pending: measure it once against real weights, or drop the requirement.

**Suite numbers.** Measured the same day — see the measurement entry at the end of this file. The tip is
**381/327/0/54** (`Passed`, fm-16 worktree) and **381/326/1/54** under four-way machine contention
(fm-20260924-01 worktree, the one red case green 3/3 in isolation). The `32aacc0` run stands as 379/325/0/54;
the delta is +2 passed, explained by `ce1619e` dropping the `-skip-testing:` exclusion. `fm-20260924-01` is
done, not pending.

### Post-move repairs (same day, found by building)

The move invalidated four things beyond the worktree admin links, each failing in a way that does not look
like a move problem. All are repaired and the primary checkout builds green from the new root
(`Scripts/dev-run.sh build`, exit 0, identity-signed, designated requirement unchanged).

1. **SwiftPM artifact paths.** `SourcePackages/workspace-state.json` records the binary-artifact path
   absolutely, so `xcodebuild` failed in seconds with
   `There is no XCFramework found at '<old path>/…NemoTextProcessing.xcframework'`. Repaired in the repo and
   in the worktrees, with every recorded path verified to exist. (One repair pass was not idempotent and
   wrote `OpenSuperWhisper-fork/repo-fork/…`; a canonicalisation pass collapsed it.)
2. **Native CMake caches.** `libllama/build` and `libwhisper/build` embed the old source directory; deleted,
   regenerated by `Scripts/build-native.sh`.
3. **Worktree submodule links.** git 2.54 stores both the submodule's `.git` file and the `worktree` value in
   `repo/.git/worktrees/<wt>/modules/<path>/config` relative to the old parent; re-pointed at the new admin
   dirs. Verified: every preserved worktree is clean against its recorded state and reports 3/3 submodules.
4. **Submodule URLs.** `.git/config` and the worktree module configs pointed at pre-move local clones, so
   `submodule update --init` in a fresh worktree failed with `repository '<old path>/asian-autocorrect' does
   not exist`; rewritten to the new clone paths.

`fork/README.md` carries the same list as a troubleshooting table.

### Crews dispatched (2026-09-24, after the consolidation)

Four, on the moved tree, all briefed with the captain's least-code directive: `fm-20260923-16` (finish the
status-bar Settings item; the uncommitted occlusion delta must be justified by exercising the
closed/hidden-window case or dropped), `fm-20260923-25` (the remaining UI-exposure gaps, with the known
`noTimestamps` rebase trap spelled out), `fm-20260923-17` (the captain's own guard + clean-up + reference +
language-display work, never built: commit, rebase, repair the three test-signature breaks, and close the
three visibility gaps that make it dead code), `fm-20260924-01` (the measurement above, in its own
worktree so the captain's identity-signed instance in the primary checkout is never rebuilt mid-run).
`fm-20260923-26` (layout-independent delivery test) and `fm-20260923-28` (Qwen3-8B Polish backend) are
deliberately not dispatched yet: they are the two largest diffs left and neither is needed to make the
delivered features visible or correct.

## [2026-09-24T08:52:00Z] MEASUREMENT — fm-20260924-01 lands the long-form recall evidence and the suite totals

The branch's flagship fix (`aaddc83`, delivered as `5e51124`) no longer rests on prose. Deliverable:
`data/fm-20260924-01/report.md`; raw logs and per-command evidence in `data/fm-20260924-01/logs/`.

**Long-form recall, re-measured** (my run in `worktrees/OpenSuperWhisper-fm-fm-20260924-01`, at the clean
tip, with the multilingual model offered to the tests as `.build/test-models/ggml-tiny.bin` — a real hard
link to the captain's `ggml-large-v3-turbo.bin`, same inode, size 1624555275):

| fixture | overall unique-word recall | tail recall | replayed 4-word runs | decoder segments |
|---|---|---|---|---|
| `long_en` (97.1 s) | **0.9932** (`0.9932432432432432`) | 1.0 | 0 | 32 |
| `long_ru` (106.6 s) | **0.9873** (`0.9873417721518988`) | 1.0 | 0 | 22 |

The handoff's 0.9932 EN / 0.9873 RU are therefore **confirmed to every printed digit** — and reproduced
bit-identically by the fm-16 crew's independent run on the same tip. Transcripts captured:
`data/fm-20260924-01/logs/longform-{en,ru}-transcript.txt`; the numbers come from the test's own
`.keepAlways` `XCTAttachment` (`xcrun xcresulttool export attachments`), and were cross-checked against a
recomputation from the captured transcript using the test's own definition
(`data/fm-20260924-01/logs/recall-recompute.py`) — the two agree.

**Suite totals, re-executed** — command:
`rm -rf libllama/build libwhisper/build && Scripts/dev-run.sh test` (log
`data/fm-20260924-01/logs/suite.log`, `result` from `xcrun xcresulttool get test-results summary`):

- fm-20260924-01 worktree, tip, **under four concurrent crews' suites**: 381 total / 326 passed / 1 failed /
  54 skipped, `Failed`. The red case is
  `SettingsLayoutSnapshotTests.testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay()`, which passed
  3/3 in isolation (`data/fm-20260924-01/logs/snapshot-rerun-{1,2,3}.log`) and whose file is untouched by
  the delta: contention, not a regression.
- fm-16 worktree (tip + `6aa0266`), uncontended: 381 / 327 / 0 / 54, `Passed`.

**Delta against the recorded 379/325/0/54 at `32aacc0`: +2 total, +2 passed, skips unchanged.** Only three
commits separate them — `aaddc83` (the fix + the rewritten long-form tests), `ce1619e` (removes
`dev-run.sh`'s `-skip-testing:` exclusion of `WhisperLongFormLanguageIntegrationTests`), `5e51124` (merge).
`-skip-testing:` excludes those two cases from the run entirely, so removing it adds exactly two cases that
now execute and pass; no other test file changed (`git diff --stat 32aacc0 5e51124`).

**Skip composition, measured:** 51 input-layout-gated (36 `ClipboardUtilPasteIntegrationTests` + 9
`ClipboardUtilKeyboardLayoutTests` + 6 `KeyboardLayoutProviderTests`) + 2 `WhisperTurboRegressionTests`
(`OSW_TEST_TURBO_MODEL` unset) + 1 `PCMRecordingTests` (microphone opt-in). The older "50 of the 54" was one
short. Reasons read from the result bundle: `data/fm-20260924-01/logs/skip-reasons.txt`.

Records corrected in place: `RESUME.md` §4 (the suite-state paragraph and item 6), this file's two
"credible-unreproduced" paragraphs, and the `fm-20260923-23` row in `state/tasks.json`, whose EVIDENCE GAP
note is removed because the gap is now closed by `data/fm-20260924-01/report.md`.

## [2026-09-24T07:05:00Z] RELAUNCH AFTER A TERMINAL HANGUP — headless rule, four crews, tip MEASURED

**What killed the first dispatch.** At 08:32 the whole agent session and all four crews died with SIGHUP.
Cause, from the crew transcripts: the `fm-20260923-16` crew proved its menu item by driving the GUI app —
`open -n` on its own build, `osascript` System Events keystrokes (`⌘W`, `⌘H`), `screencapture`, clicks on
status-bar menu items. One keystroke landed on the frontmost window, which was the agent's own terminal.
No code was lost: every crew's partial work was on disk and was re-verified before the relaunch.

**Headless rule — in every brief as "Relaunch addendum 2", and in `fork/README.md`.** Forbidden for any agent
on this project: `open`; `osascript` in any form; System Events / Accessibility automation; synthetic
keystrokes; `screencapture`; launching any OpenSuperWhisper build; `Scripts/dev-run.sh` **with no mode
argument** (it `exec`s the GUI app); touching Terminal or iTerm. Expected: `Scripts/dev-run.sh build|test`,
`xcodebuild`, `git`, `python3`, unit and snapshot tests, long output redirected to a file. A check that needs
the app on screen is reported as *needs the captain's screen*, never improvised. Verified after the relaunch:
210 shell calls across the four crews, zero banned commands, and no crew launched an app.

**The suite is headless by construction, with one trap.** `run_unit_tests()` passes
`-only-testing:OpenSuperWhisperTests`, so the scheme's XCUITest bundle is never run — but passing your own
`-only-testing:` replaces that selection, and the UI bundle then runs and launches the app.

**One contention flake, not a regression.** With four suites running concurrently (load average 14–25) the
`fm-20260924-01` run went red on one case and one only:
`SettingsLayoutSnapshotTests.testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay()`; it passed 3/3 when
that class ran alone, and its file is untouched by every commit between `32aacc0` and the tip. The same
suite run uncontended in the fm-16 worktree a minute earlier was 327 passed / 0 failed. Operational
consequence: **do not run several suites at once on purpose**; sequential is the honest default.

**Crew outcomes** — all four relaunched headless, all four worktrees clean at the end, nothing merged or
pushed, every claim re-checked by the first mate against the run logs:

| task | branch @ head | what the run proved |
|---|---|---|
| `fm-20260923-16` | `fm/fm-20260923-16` @ `6aa0266` | `Settings…` in the status-bar menu now reaches Settings with the main window closed or hidden; suite 327/0/54 `Passed`; bundle identity-signed, designated requirement unchanged. The occlusion delta stays stashed — its premise is a GUI-timing claim that the test host cannot exercise (`applicationDidFinishLaunching` returns early under test), so no new code was added. |
| `fm-20260923-25` | `fm/fm-20260923-15` @ `786ceef` | G-04..G-07 (`8bcc8f6`) + G-02/G-03/G-10/G-11/G-12 (`a123947`) + the two never-built polish edits (`786ceef`); suite 335/0/54 `Passed` (389 cases = tip 381 + 8); `params.noTimestamps = false` intact. |
| `fm-20260923-17` | `fm/fm-20260923-17` @ `8d0b9eb` | guard + clean-up pass + reference field implemented, reachable in Settings → Transcription and displayed for the last dictation; suite from a clean state 358/0/54 `Passed` (412 cases = tip 381 + 31); `params.noTimestamps = false` intact; latency/model-call table measured on the captain's own 23 recordings. Quality finding: **en→pl is unusable on the 1.5B** (it invents words) — that is the direction `fm-20260923-28` (Qwen3-8B Polish backend) owns. |
| `fm-20260924-01` | no branch (scout) | the flagship fix is measured, not asserted — see the numbers below. |

**Delivery tip numbers, measured (`data/fm-20260924-01/report.md` + `logs/`).** Uncontended:
**381 total / 327 passed / 0 failed / 54 skipped**, `Passed`. Under four-way load the same suite ran
381 / 326 / 1 / 54 (the contention flake above). Skips: **51** input-layout/Accessibility gated (the older
records said 50 — corrected), 2 `OSW_TEST_TURBO_MODEL` opt-in, 1 microphone opt-in. Delta against
379 / 325 / 0 / 54 at `32aacc0`: **+2 total, +2 passed, skips unchanged**, because `ce1619e` stopped
`dev-run.sh` excluding `WhisperLongFormLanguageIntegrationTests` with `-skip-testing:` — an excluded case is
counted in neither the total nor the skips, and both cases now run and pass.

**The flagship fix no longer rests on prose.** `LongFormTranscriptionTests` against `ggml-large-v3-turbo`
(offered to the tests as `.build/test-models/ggml-tiny.bin`, a real hard link — same inode, link count 2):
**unique-word recall 0.9932 EN** (`0.9932432432432432`) and **0.9873 RU** (`0.9873417721518988`), tail recall
**1.0** in both languages, **0 replayed four-word runs**, 32 EN / 22 RU decoder segments. Four independent
derivations agree to the last printed digit (two suite attachments, a recomputation from the captured
transcripts, and the fm-16 crew's separate run) and the handoff's claimed 0.9932 / 0.9873 is confirmed
exactly. The English and Russian transcripts are captured verbatim in `data/fm-20260924-01/logs/`.

## [2026-09-24T08:05:00Z] MERGED — the three ready branches are on the delivery branch

Captain authorised the merge ("merge the repository"). Merged `--no-ff`, priority order, one at a time, in
the primary checkout. The delivery branch moved `5e51124` -> **`319f3a3`**. No conflicts: the branches touch
overlapping files (`Settings.swift`, `WhisperEngine.swift`, `AppPreferences.swift`) but in disjoint regions
and `ort` auto-merged all three.

| task | merge commit | branch @ head | change |
|---|---|---|---|
| `fm-20260923-17` | `2aebf89` | `fm/fm-20260923-17` @ `8d0b9eb` | 17 files, +1878/−104 |
| `fm-20260923-25` | `d66298b` | `fm/fm-20260923-15` @ `786ceef` | 8 files, +1026/−55 |
| `fm-20260923-16` | `319f3a3` | `fm/fm-20260923-16` @ `6aa0266` | 1 file, +45/−3 |

**Merged tip verified headless — a merge of three separately-green branches is not itself proof.**
`Scripts/dev-run.sh test` in a worktree fast-forwarded to `319f3a3`, alone on the machine: exit 0,
`** TEST SUCCEEDED **`, **420 total / 367 passed / 0 failed / 53 skipped**; bundle re-signed with the
identity requirement and the designated requirement unchanged (`certificate leaf = H"32266bcc…"`). Every
class from both branches ran: `DictationScrubberTests` 14, `SpeechModelLanguageGateTests` 10,
`ModelStorageTests` 7, `SettingsExposureTests` 2, `SettingsLayoutSnapshotTests` 7,
`WhisperLongFormLanguageIntegrationTests` 2.

**Skip reconciliation (the honest ledger).** 53 skips = **50** input-layout/Accessibility-gated (35
`ClipboardUtilPasteIntegrationTests` + 9 `ClipboardUtilKeyboardLayoutTests` + 6
`KeyboardLayoutProviderTests`) + 2 `OSW_TEST_TURBO_MODEL` opt-in + 1 microphone opt-in. Earlier same-day
runs recorded 54 (51 gated); the difference is exactly
`ClipboardUtilPasteIntegrationTests.testPasteWithTurkishLayout()`, which **skips or passes depending on
transient input-source state**: the gate is `ClipboardUtil.switchToInputSource(withID:)`, which
substring-matches `TISCreateInputSourceList` IDs (`ClipboardUtil.swift:227`) and returns
`TISSelectInputSource(...) == noErr`. Under load that call failed and the case skipped; alone it returned
`noErr` and the case passed. **Caveat:** `TISSelectInputSource` can return `noErr` without the layout
actually becoming active, and the case asserts the pasted text rather than the layout, so its green does not
prove a Turkish layout was in use. The layout-gated skip count can therefore read 50 or 51 on the same tree
— neither is wrong, but the condition belongs next to the number whenever it is quoted.

**Teardown.** All four crew worktrees were removed after each branch was confirmed clean and an ancestor of
`319f3a3` (`git worktree remove` refuses on trees with submodules; `submodule deinit -f --all`, `rm -rf`,
`git worktree prune` instead). ~10 GB freed, `worktrees/` is empty, the primary checkout is the only
worktree and it is clean. The `fm/*` branches are kept and everything remains inside `archive/`. The
occlusion delta from `fm-20260923-16` still sits in the repo-level stash (`stash@{0}`).

**Still unpushed.** `feat/local-translate-tone` @ `319f3a3` exists only on this machine; publishing remains
a captain decision.

*(Superseded later the same day: the work was published as `main` on `origin` — see the PUBLISHED entry below.
The branch name `feat/local-translate-tone` is still local-only, which was the point of this line when it was
written.)*

## [2026-09-24T09:11:55Z] docs — the fork now describes itself

`eca5971 docs(readme): describe the fork, its features and every difference from upstream` (+205 lines)
followed the merges on the delivery branch. `repo/Readme.md` gained a fork banner (including that the `brew`
line and the release links install upstream's build), an "Added by this fork" list beside upstream's Features
list, and a "What this fork changes" section: the scale of the delta (54 own commits, 78 files, +12,995/−715)
and ten subsections — in-process translation and tone, language-aware gating, the English-only model guard, the
clean-up pass and reference field, keystroke delivery with an untouched clipboard, Accessibility-only
permissions and nothing blocking on them, the long-form audio fix, the settings/model/diagnostics surfaces,
packaging and uninstall, developer tooling — plus what is inherited unchanged and what is deliberately not
built yet (the Qwen3-8B Polish backend, transform determinism). Every number quoted there is one the fleet
measured on this branch; the open items are labelled open, not shipped. Delivery tip: `eca5971`, then `23d873a`
after the publish wording was corrected.

## [2026-09-24T09:18:41Z] PUBLISHED — `main` on the fork's own repository

The captain asked for the work to be on `main`. No uncommitted changes existed (the tree was already clean), so
this was a branch operation, not a commit: local `main` was created at the delivery tip and pushed.

- `origin` = `https://github.com/23n0n/OpenSuperWhisper.git` (the fork's own repository; `upstream` is Starmel's).
- `origin/main` = **`23d873a`** = `feat/local-translate-tone` HEAD. At that moment the branch *name*
  `feat/local-translate-tone` existed only locally. *(Superseded within the hour: the captain asked to work
  exclusively on his fork, so that branch was pushed and tracking set up — see the entry below.)*
- Nothing was sent upstream: no push to `upstream`, no pull request. `upstream/develop` is untouched.
- Before the push, two lines in `repo/Readme.md` that said the fork was "not pushed to any remote" were corrected
  and amended into the same README commit, so the published tree describes its own publishing state accurately.
- Publishing further (a PR to Starmel, a release, a second branch) remains a captain decision.

## [2026-09-24T09:22:42Z] FORK IS THE WORKING REPO — delivery branch pushed, default branch moved

The captain: "I want to work exclusively on my fork." Two changes on `origin` (= his fork,
`23n0n/OpenSuperWhisper.git`), neither touching `upstream`:

1. **`feat/local-translate-tone` pushed** (`git push -u origin feat/local-translate-tone`, new branch, tracking
   set up). The fork carries the work under both names — `main` and `feat/local-translate-tone`, both at
   `23d873a` — so a clone gets the delivered fork whichever branch it lands on.
2. **Default branch moved `develop` -> `main`** (`gh api -X PATCH repos/23n0n/OpenSuperWhisper -f
   default_branch=main`, verified by reading it back). The fork's `develop` was a mirror of upstream's,
   71 commits behind the fork's own work, so a fresh clone — or the repository's GitHub front page — showed
   none of it. Revert with the same call and `develop`.

Nothing was pushed to `upstream` (Starmel's) and no pull request exists against it; `upstream/develop` is still
`c8e6fe7`. Nothing needed committing for this: `repo/` was already clean at `23d873a`.

**Open question left with the captain — the fleet records are not in git.** `fleet/` (ledger, briefs, reports,
`FLEET-STATE.md`, `RESUME.md`), `docs/` and `archive/` live under `OpenSuperWhisper-fork/` but outside `repo/`,
so pushing the repository backs up the code only; the records and the preservation bundle stay on one disk —
the exposure `fm-20260924-03` was registered for. Cheapest option that closes it: a `fleet-state` branch in this
same repository holding those files. Alternatives: a second small repository, or nothing.

## [2026-09-24T09:34:47Z] UPSTREAM PR CLOSED — #211 "work so far"

A pull request did exist against Starmel's repository for about fourteen minutes, and it was **not** opened by
the fleet: the captain opened it by hand right after the first push, following GitHub's "create a pull request
for 'main'" hint that the push itself printed.

- PR: `https://github.com/Starmel/OpenSuperWhisper/pull/211` — "work so far", head `23n0n:main`, opened
  2026-09-24T09:20:20Z.
- The captain asked for it to be removed; closed with `gh pr close 211 --repo Starmel/OpenSuperWhisper` at
  2026-09-24T09:34:31Z, verified by reading the state back (`CLOSED`). No comment was added, so the upstream
  maintainer got no notification beyond the close itself.
- Re-checked afterwards: **no open PR** from this fork or from this account remains against
  Starmel/OpenSuperWhisper, and `upstream/develop` is still `c8e6fe7` — no commit of this fork has ever been
  pushed to upstream.
- The fork's own `main` is unchanged and still the head branch that PR pointed at; closing a PR touches nothing
  in the fork.
- Standing instruction recorded: this fork is worked on exclusively by its owner and is not offered upstream.
  The README's "nothing has been sent upstream, and no pull request is open against it" is therefore accurate
  both before and after this episode.

## [2026-09-24T09:47:14Z] PAUSED — DeepSeek peak pricing; work waits for off-peak

The captain asked to check the provider's peak hours before spending. Checked against the provider's own docs
(`https://api-docs.deepseek.com/quick_start/pricing`), not from memory, because the window has changed since it
was last recorded:

> Peak hours are **01:00 – 04:00 and 06:00 – 10:00 UTC, Monday through Friday**, excluding Chinese public
> holidays. All other hours are off-peak, including weekends and Chinese public holidays in full. Off-peak rates
> are half of peak rates.

At 09:46 UTC on Thursday 2026-09-24 that is **peak** (inside 06:00–10:00 UTC). The window closes at **10:00 UTC
(12:00 CEST)**, after which all hours are off-peak until the next window opens 2026-09-25 01:00 UTC.

- `fm-20260923-28` was dispatched at 09:47 UTC and **cancelled at 09:50 UTC** to stop peak-rate spending. Nothing
  was lost: it had only created its worktree and branch.
- State left behind, verified clean afterwards: worktree `worktrees/OpenSuperWhisper-fm-fm-20260923-28`, branch
  `fm/fm-20260923-28` @ `23d873a`, no commits, no build directory, all three submodules reset to the pinned
  commits (`f7b76763`, `4e416ee7`, `371b5a75`) so the relaunch starts from a clean tree.
- Relaunch happens after 10:00 UTC, off-peak. **Standing rule for this fleet: dispatch crews only outside
  01:00–04:00 and 06:00–10:00 UTC on weekdays.** The rest of the queue (fm-27, fm-26, the records backup and the
  branch cleanup) is unaffected by the pause and runs in the same off-peak window.
