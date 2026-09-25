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

## [2026-09-24T11:09:03Z] fm-20260923-28 READY — Polish output on Qwen3-8B, and a false red that was a test's fault

Branch `fm/fm-20260923-28` @ `0a4f5f8` (feature `10a4c3d`: 13 files, +1276/−206; test fix `0a4f5f8`).
Unmerged, unpushed — waiting for the captain's merge word.

**What it does.** The built-in transform backend is chosen by the language the answer must be written in:
Polish output → `qwen3-8b-q4_k_m` (5.03 GB on disk, ~5.6 GB wired step), English output → the shipped
`qwen2.5-1.5b-instruct-q4_k_m`; `TransformModelManager.modelID(forOutputLanguage:)` is the single decision
point and one backend is resident at a time. A missing Polish backend is refused with a Settings notice and
its own pinned download — never a silent fallback to the small model, whose English→Polish output is what
this change exists to replace. Per-backend RAM and disk are stated next to the Target language picker, the
8B's load rides the record-start warm-up, and the documented 10-minute idle unload still fires.

**Proven by execution, not asserted** (`fleet/data/fm-20260923-28/report.md`, evidence files under `/tmp/fm28-*`):
en→pl `backend qwen3-8b-q4_k_m` / pl→en `backend qwen2.5-1.5b-instruct-q4_k_m` / pl→pl **0 model calls**;
missing 8B → `attempted ["qwen3-8b-q4_k_m"], resident none`, raw transcript delivered and the card says
which direction is waiting for its model; a mutated copy is refused against the pinned digest and the real
5 GB file re-verifies (`d98cdcbd…`); wired baseline 2.26 GB, 8B step 5.62 GB, 1.5B step 1.43 GB; latency
en→pl 1.01 s steady, pl→en **0.18 s** steady (the recorded baseline for that direction was ~0.29 s).

**First-mate verification, alone on the machine, headless:** clean-state run **387 passed / 0 failed /
54 skipped, `** TEST SUCCEEDED **`, exit 0**, then an incremental run identical; bundle re-signed with the
identity requirement, designated requirement unchanged. Sampling untouched (`Llama.swift` absent from the
diff — `fm-20260923-27` owns it next) and `params.noTimestamps = false` still at `WhisperEngine.swift:415`.

**The false red, worth keeping.** The first verification run was red on exactly one case
(386 / 1 / 54): `SettingsLayoutSnapshotTests.testEveryTabLaysOutItsCardsWhateverTheSwitchesSay()`, reporting
`the card stack ends 0 pt before the end of the tab, expected the 16 pt page padding` — with a **520x600**
image, which is the *window*, not the tab's document (`503x2016`). The capture asked for the tab's scroll view
with a single `if let`; under XCTest's parallel test classes (`parallelizable = "YES"`) the hosted tree was not
built yet, the lookup failed silently, and the capture fell through to a window image whose last card touches
the bottom edge — so a *capture* defect was reported as a *layout padding* defect. `0a4f5f8` makes the
`fullContent` capture wait up to 5 s for the document view and throw `renderFailed` naming the case if the tree
never materialises; no assertion and no part of the settle/draw loop changed. The two green runs are on those
exact bytes. Lesson for the fleet: a silent fallback in a test harness turns environment trouble into a
product-looking failure — a harness that cannot obtain what it asked for must fail loudly as itself.

**Accepted gaps** (stated in the report, not hidden): a cache-evicted cold load was not freshly measured (the
figure that stands is `fm-20260923-24`'s 3.21 s for these weights; the warm-cache warm-up path that hides that
load is measured at 1.01–1.14 s), and the first-utterance-after-warm-up / racing-the-warm-up numbers were
flagged by the crew as contention-corrupted.

## [2026-09-24T11:17:17Z] fm-20260923-28 LANDED LOCALLY (no push)

Merged `--no-ff` into `feat/local-translate-tone` as **`c6f9546`**. The captain chose merge-local-only, so
nothing was pushed: `origin/main` and `origin/feat/local-translate-tone` still point at `23d873a` and the fork
is one landing behind until he says otherwise.

The merge is content-free by construction — `git diff --stat 0a4f5f8 HEAD` is empty, i.e. the merged tree is
byte-identical to the branch tip that passed two headless full-suite runs (387 / 0 / 54 each) and the routing,
missing-model, digest, RAM, latency and idle-unload checks. Nothing was re-measured for the merge because
nothing changed; that identity check is the verification.

Queue continues with `fm-20260923-27` (determinism) rebased on `c6f9546`, then `fm-20260923-26`.

## [2026-09-24T11:49:55Z] fm-20260923-27 READY — the in-process transform was already deterministic

Branch `fm/fm-20260923-27` @ `80d114c`, **test-only** (one new file, +95), base `c6f9546`. Unmerged, unpushed.

**The requirement is met without a code change.** The crew measured the in-process path hard: 64 probe requests over ten
test-process launches produced exactly one output hash per configuration — 1.5B PL→EN ×18, 8B EN→PL ×12, 1.5B EN→PL
(fm-13's exact configuration) ×10, and CPU-only ×6 — and the committed test
`OpenSuperWhisperTests/TransformDeterminismIntegrationTests.swift` hashes repeated runs in both directions. First-mate
verification: clean-state headless run **388 passed / 0 failed / 54 skipped, `** TEST SUCCEEDED **`, exit 0**, both
determinism cases green, bundle identity-signed. The crew's summary line quoted 389 passed; its own log's case lines sum
to 388 and mine is 388 — same 442-case total, so **388/0/54 is the number to quote** and the difference was a counting slip,
not a missing case.

**Where fm-13's "8/10 outputs differed" actually came from — the optional HTTP endpoint, not the app.** That path sends no
`seed` (`TranslationService.buildRequestBody`), `Scripts/transform-server.sh` starts `llama-server` without `--seed`, and
`LLAMA_DEFAULT_SEED` resolves through `std::random_device` (`llama-sampler.cpp:339-353`). In-process the seed is pinned and
the sampler chain is rebuilt per request, which is why it does not vary. The fleet's earlier conclusion that the
nondeterminism lived in seed handling was therefore wrong in its attribution and right in its symptom: the symptom belongs to
a path that is off by default.

**Two findings worth keeping.** First, the crew invalidated its own experiment — the `n_gpu_layers = 0` hook fired after the
model had already loaded 99 layers, so that "CPU-only" run was still Metal; it reported the mistake instead of the number.
Second, real CPU-only (Metal absent) is internally deterministic too but differs from Metal by **one token**
(`Good day. I am calling about order number 423` vs `Good day. I'm calling about order number 423`): reduction order is part
of a build's identity, so cross-configuration equality was never the contract and determinism must be judged per
configuration. Single-threaded sampling is identical to the shipped 4-thread configuration and costs nothing, so it buys
nothing either.

**Side effect that corroborates fm-28.** The 1.5B's EN→PL output is *stably wrong* — `Dzien dobry. Slucham, ale nie moge ci
pomoc.` on all ten runs — a reproducible quality defect rather than variance, which is exactly the direction fm-28 moved to
the 8B.

**Optional, not done (captain's call):** adding a `seed` to the endpoint request body would make the *optional* HTTP path
deterministic as well. Off by default, and it touches an external contract, so nothing was changed.

## [2026-09-24T12:21:26Z] STANDING ORDER — merge every landing locally, push once at the end

The captain, verbatim: *"Don't ask again, merge all locally. We will be pushing to remote only after the whole work
will be finished."*

Interpretation, recorded so no later session has to ask:
- **Merge authority is standing** for every verified crew branch: `git merge --no-ff` into `feat/local-translate-tone` in
  the primary checkout as soon as the branch passes the first-mate verification (clean-state headless suite green plus
  the task's own evidence). No per-landing question, and no per-landing push.
- **Publishing is a single, deferred act**: `main` and `feat/local-translate-tone` go to `origin` (the fork) once, when
  the captain says the work is finished. Until then `origin/*` stays where it is and the local delivery branch runs ahead
  of it — `git status -sb` reporting "ahead N" is the expected, healthy state.
- A landing still requires the verification, and a red suite still stops the landing. This order removes a question, not
  a check.
- Nothing is ever pushed to `upstream` (Starmel's) under any reading of this order; the fork is the only remote that
  receives anything, and only on the final go.

## [2026-09-24T12:24:14Z] fm-20260923-26 LANDED LOCALLY — the daily delivery path is finally covered

Merged `--no-ff` as **`ffda358`** (branch `fm/fm-20260923-26` @ `62eb921`, test-only: two files, +222/−4, no product file in
the diff), under the standing order: merge on verification, push only when the captain declares the work finished.

**Why it mattered.** 50 of the suite's 53 skips were keyboard-layout gated: the cases that exercise synthetic-keystroke
delivery hard-coded layouts (US, Dvorak, Russian, …) that this machine does not have, so the path the captain uses every day
was the least tested code in the repository, and the two cases that did run exercised a code path the product no longer
calls.

**What the new coverage does, and why it is not decoration.** Each family gained one case that always runs against the
machine's **active** input source, resolved at run time and never switched. The typed payload is longer than
`KeyboardSimulator.maxUTF16PerEvent` — so chunk boundaries are exercised — and carries CJK, Cyrillic, emoji, Polish
diacritics, plus Return and Tab: characters the active layout has no key for, which the case also asserts at run time
(`findKeycodeForCharacter` returns nil for some of them). A delivery path that derived characters from key codes (the shape
`ClipboardUtil.sendCmdV` uses), dropped the Unicode payload, or lost characters at chunk boundaries therefore fails it. The
layout-named cases are kept and still skip when their layout is absent — those skips are honest, and the brief forbade
weakening or deleting them. The crew also dropped a candidate assertion it judged tautological instead of padding the count.

**Verification (first mate, clean state, headless, alone on the machine):** authoritative from the `xcresult` summary —
**444 total / 390 passed / 0 failed / 54 skipped, result Passed, exit 0**; the three new cases ran and passed
(`testPasteWithActiveInputSource`, `testPasteAllAvailableLayouts`, `KeyboardSimulatorDeliveryTests`); bundle identity-signed
(`certificate leaf = H"32266bcc…"`).

**Counting lesson, recorded.** Log-line counting under-reports when XCTest's parallel processes interleave a case line: the
fm-26 crew's own summary read 389 'passed' lines for a run the result bundle calls 390, and my fm-27 line-count (388) has
the same shape. Quote totals from the `xcresult` summary (`xcrun xcresulttool get test-results summary`), not from `grep`.

## [2026-09-24T12:27:25Z] MERGED TIP VERIFIED GREEN — all three landings together

`feat/local-translate-tone` @ **`ffda358`** (fm-28 + fm-27 + fm-26), clean-state headless suite alone on the machine,
numbers from the `xcresult` summary: **446 total / 392 passed / 0 failed / 54 skipped, result Passed, exit 0**; bundle
re-signed in the primary checkout with the shipped bundle id and the unchanged designated requirement
(`identifier "ru.starmel.OpenSuperWhisper" and certificate leaf = H"32266bcc…"`).

The arithmetic checks out against the branches measured separately: 444 (fm-26's branch, which excludes fm-27) plus the two
`TransformDeterminismIntegrationTests` cases fm-27 added = 446; passed 390 + 2 = 392; skips unchanged at 54. Nothing about
the three landings interacts: the suites, the routing, the determinism contract and the new delivery coverage all hold in
one tree.

**Crew queue is empty.** What remains is the captain's: the fm-16 occlusion delta in `stash@0` and the eyeball pass over
the merged surfaces (both need his screen), the optional `seed` on the endpoint request body, the optional 14B rung
measurement, and the single deferred publish — `main` + `feat/local-translate-tone` to `origin` when he declares the work
finished.

## [2026-09-24T12:27:46Z] TEARDOWN — landed worktrees removed, refs bundled, nothing pushed

After the three landings (`ffda358` = fm-28 + fm-27 + fm-26, suite **446 / 392 / 0 / 54** `Passed`):

- A fresh all-refs bundle (`fleet-state/archive/all-local-branches-<stamp>.bundle`, thin against `origin/develop`) and its
  ref listing were committed into the records branch — `fleet-state` @ **`086243f`**, committed **locally only**. The standing
  order defers every remote write, so the records branch is pushed at the end with the code.
- The three crew worktrees were removed (deinit + `rm -rf` + `prune`, since `git worktree remove` refuses trees with
  submodules) after each branch was confirmed an ancestor of the delivery tip, and the three merged branches deleted.
  ~12 GB freed; `worktrees/` is empty; the primary checkout is the only worktree besides the records branch.
- Local branches now: `develop`, `feat/local-translate-tone` @ `ffda358`, `main` @ `ffda358` (fast-forwarded to mirror the
  delivery branch, still **behind `origin/main` until the final push**), `fleet-state` @ `086243f`.
- The primary checkout's app was rebuilt and re-signed after the last merge; the occlusion-delta stash is untouched.

**Crew queue: empty.** Remaining items are the captain's, or optional: the fm-16 occlusion delta (his screen), the eyeball
pass over the merged surfaces (his screen), the optional `seed` in the endpoint request body, the optional 14B rung, and
the single deferred publish.

## [2026-09-24T13:44:35Z] PUBLISHED — the fork carries everything (`main`, delivery branch, records)

The captain: *"dispatch to my fork."* All three refs pushed to `origin` = `23n0n/OpenSuperWhisper`, each a plain
fast-forward — no history was rewritten:

| ref | from | to |
|---|---|---|
| `main` (fork default) | `23d873a` | **`ffda358`** |
| `feat/local-translate-tone` | `23d873a` | **`ffda358`** |
| `fleet-state` (records) | `466ba7c` | **`086243f`** |

Verified by reading the refs back with `git ls-remote origin`: all three remote hashes equal the local ones. `upstream`
(Starmel's) received nothing and has no pull request from this fork; the closed PR #211 remains closed. The delivery tip is
the verified merge of fm-28 + fm-27 + fm-26 (`446 / 392 / 0 / 54 Passed`, bundle identity-signed), and the records branch
carries the ledger, briefs, reports, handoff, the redacted first snapshot and the all-refs bundles.

## [2026-09-24T13:46:47Z] OLD INSTANCE KILLED, STALE BUILD CACHES PURGED

Captain: *"kill and purge old version."*

- The running app (pid 18492, launched 11:54 from `repo/build/…/OpenSuperWhisper.app`) was the **pre-fm-28** build: the file
  behind that path had been rebuilt twice since (13:17, then 14:27 at `ffda358`), and a running process keeps the image it
  started from. It was sent `SIGTERM` and is gone; nothing of the app is running now.
- **Five stale Xcode DerivedData trees** left over from direct Xcode builds on 2026-09-23 were removed
  (`~/Library/Developer/Xcode/DerivedData/OpenSuperWhisper-*`): `du` accounts for 2.62 GB, while `df` moved by **869 MB** —
  APFS clones share blocks between those trees, so the apparent size overstates what the filesystem actually reclaims. No
  process was using them and they contained no app bundles, only regenerable caches.
- Swept for anything else launchable: **no** `/Applications` copy, **no** Homebrew cask, no `.pkg` anywhere on the volume,
  no leftover bundle from the pre-move path (`Projects/OpenSuperWhisper` is gone). The only app bundle on this machine is the
  current one, `repo/build/Build/Products/Debug/OpenSuperWhisper.app` — built 14:27 at the merged tip `ffda358`,
  75,055,344 bytes, identity-signed.
- **Not touched on purpose:** the app's own data — preferences, downloaded speech/transform models, dictation history and the
  Accessibility grant. Purging the *version* is not purging the *installation*; say the word if you want the uninstaller path
  taken instead.

## [2026-09-24T13:50:48Z] RELEASE 0.1.0-fork.1 — built, verified, installed, published on the fork

Captain: *"built and install newest also add it as realise to my fork repo"*, and then, on the signature question:
*"No developer id is not an issue."* — so the missing Developer ID is recorded as a fact about this machine, not as a blocker.

**Built** from the merged tip `ffda358` with the repo's own entry points, not upstream's `make_release.sh` (that one demands a
Developer ID and posts to Starmel's repository): `Scripts/build-native.sh Release` · the autocorrect dylib in release ·
`xcodebuild -configuration Release` with `CODE_SIGNING_ALLOWED=NO ENABLE_DEBUG_DYLIB=NO` · `Scripts/dev-sign.sh` with the local
identity (designated requirement `certificate leaf = H"32266bcc…"`) · `packaging/build-pkg.sh --version 0.1.0-fork.1`.

**Artifact:** `dist/OpenSuperWhisper-0.1.0-fork.1.pkg`, **87,574,043 bytes**, sha256
`ae1662312c1aa8b8a356d1d3aeeeca5c6b47bcc056e3389e2a2c229e6ee69185`. Release app 107 MB, `CFBundleShortVersionString` 0.1.0, bundle id `ru.starmel.OpenSuperWhisper`.
`Scripts/verify-packaging.sh --app …`: **ALL CHECKS PASSED (39 checks)** — the uninstaller's path list and idempotence, the
two-entry `/Applications` payload, the receipt id, the preinstall hook, the arm64 / macOS 14 floor, the version substitution.

**Installed on this machine:** `/Applications/OpenSuperWhisper.app` (0.1.0, identity-signed, DR unchanged) plus
`/Applications/Uninstall OpenSuperWhisper.command` — the package's own payload layout. `installer -pkg` was not used because it
needs root and this session has no passwordless sudo; the package remains the canonical installer and is attached to the release.

**Published:** GitHub release **`v0.1.0-fork.1`** on `23n0n/OpenSuperWhisper`,
`https://github.com/23n0n/OpenSuperWhisper/releases/tag/v0.1.0-fork.1`, tag at `main` = the delivery tip `ffda358`, with the
`.pkg` and its `.sha256` attached (verified by reading the release back). The notes describe the fork's additions, the measured
verification on the merged tip (446 tests / 392 passed / 0 failed / 54 skipped), the requirements, and one practical line about
Gatekeeper, which will warn because the package is unsigned — a fact about the build machine, not a defect to fix.

**Trap restated for this machine's own copies:** `/Applications/OpenSuperWhisper.app` and the development checkout's
`build/Build/Products/` (Debug and Release) share the shipped bundle id. One copy at a time — the Accessibility grant is keyed to
the bundle id and the signing identity, and two live copies are what has historically made macOS re-prompt.

## [2026-09-24T13:51:51Z] INSTALLED AND READY TO USE (with the Polish backend staged)

The captain asked to be able to use the release from the Applications folder. Verified on `/Applications/OpenSuperWhisper.app`:

- `codesign --verify --deep --strict`: **valid on disk**, **satisfies its Designated Requirement**; designated requirement is the
  identity one (`certificate leaf = H"32266bcc…"`), so the existing Accessibility grant still applies. `spctl` rejects it for
  *notarization* only, and there is **no `com.apple.quarantine` attribute** on a locally built bundle, so a double-click opens it
  normally — the Gatekeeper dance only matters for a downloaded copy.
- `CFBundleIdentifier ru.starmel.OpenSuperWhisper`, `CFBundleVersion 13`, `LSMinimumSystemVersion 14.0`; single binary
  `Contents/MacOS/OpenSuperWhisper` (29,451,984 bytes, Release), no debug dylib; bundled `ggml-tiny.en.bin` and the Silero VAD.
- User state is shared with the fork's Application Support folder, so it runs immediately: `ggml-large-v3-turbo.bin` and
  `ggml-tiny.en.bin` speech models, the 1.5B transform model with its verified stamp.
- **The Polish backend was staged into the app's own folder** — `transform-models/qwen3-8b-q4_k_m.gguf`, the name
  `TransformModelManager` looks for, as a **hard link** to `~/models/Qwen3-8B-Q4_K_M.gguf` (2 links, 5,027,783,488 bytes, **no
  extra disk used**). Its digest was read back and equals the pin `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785`,
  so the app's own verify step will pass rather than offering a 5 GB download.

To use Polish output: **Settings → Transcription → Translate into … → Target language: Polish** (that is the direction that runs on
the 8B; English output keeps the 1.5B and is the default). The 1.5B remains the model for English output and for the clean-up pass.

**Receipt note:** the app was installed by copying the package's payload (no passwordless sudo for `installer -pkg`). If the pkgutil
receipt matters for the uninstaller's completeness, run it once by hand:
`sudo installer -pkg /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/dist/OpenSuperWhisper-0.1.0-fork.1.pkg -target /`

**One copy at a time.** `/Applications/OpenSuperWhisper.app` and the checkout's `build/Build/Products/…` builds share the shipped
bundle id; running two at once is what makes macOS re-prompt for Accessibility.

## [2026-09-24T13:58:12Z] SHORTCUT TRIGGER BROKEN — mechanism pinned, immediate remedy applied, fix dispatched

Captain: *"Shortcut recording is not working properly"* and *"detecting the first shortcut pre-recorded is not working properly.
The hook is not monitoring my input properly."* Both statements are literally true, and not his keyboard's fault.

**Evidence read off his machine (installed 0.1.0 build):**

```
modifierOnlyHotkey = none            the armed modifier key had been wiped
lastModifierOnlyHotkey = leftOption   the key he used to hold (Left ⌥) was still remembered
mouseButtonHotkey = none
KeyboardShortcuts_toggleRecord = 0    and no key-combination shortcut was stored either
```

**Mechanism, from the code on the delivered tip:**

1. `ShortcutManager.setupRecordingTrigger()` (`ShortcutManager.swift:97-150`) tears down all three triggers and then, with modifier `none`
   and mouse `none`, takes the `else` branch — `KeyboardShortcuts.enable(.toggleRecord)`. With no shortcut stored, **no trigger is armed
   and no monitor is installed**, so the app watches nothing while looking perfectly healthy.
2. `ModifierKeyMonitor.start(modifierKey:)` (`ModifierKeyMonitor.swift:100-140`) returns early through `stop()` when the key is `.none`, so
   the global and local `.flagsChanged` monitors behind hold-to-record never exist. His pre-recorded Left ⌥ did nothing.
3. Two paths write that `.none` **silently**: the trigger-mode segmented picker (`Settings.swift:2225-2245`, `case .keyCombo:`) and the
   onboarding flow (`OnboardingView.swift:31-43`, `case .keyCombination:`). Either leaves the app inert with no word to the user.
4. **The recorder itself looks inert.** `system.log` for the running app holds **two** `KeyboardShortcuts.RecorderCocoa` instances with
   `NSControlGestureRecognizer … state = Began` — mouse gestures that began and never completed — while `isRecordingNewShortcut`
   (`Settings.swift:1154`, hint displayed at `:2327`) is never set by anything: dead state from an unfinished recorder workflow inside the
   sheet's `ScrollView` (library: sindresorhus/KeyboardShortcuts 3.0.1, whose recorder is an `NSSearchField` subclass).

**Immediate remedy applied (his machine):** the app was quit and `modifierOnlyHotkey` restored to `leftOption` (mouse stays `none`), so the
next launch arms the modifier hook again and hold-to-record works with the shortcut he already had. The app is deliberately left quit so the
restored value cannot be overwritten at exit; the next launch picks it up.

**Fix dispatched** as `fm-20260924-06` (branch `fm/shortcut-recorder` @ `ffda358`, crew `FmShortcutFix`): prove where the recorder breaks
with a headless AppKit instrument, make recording a shortcut actually work, stop the silent wipe (preserve the remembered modifier key or
surface the inert state), wire or remove the dead `isRecordingNewShortcut`, and add the test. Lands locally on verification like everything
else; no push until the captain says so.

## [2026-09-24T14:01:26Z] DECISION — translation is dropped; transcription, tone and the clean-up stay

Captain, verbatim: *"Given this we will be dropping completely translation feature and keep only transcription, tone and judgment
as a feature. So basically we will always keep the language recorded. So if it's Polish we will keep Polish, if it's English we
will keep English and that's all."* Confirmed the same day: **tone** is a same-language rewrite in both languages; the **8B** stays
as an *optional* backend that **Polish prefers when installed** (1.5B otherwise — nothing required, nothing refused); **"judgement"**
is the existing clean-up pass plus the reference field; the **external endpoint override is removed**.

**This supersedes the translation work landed earlier today** (`fm-20260923-13`, `-17`, `-28`: the cross-language `TransformPolicy`
rows, the `Translate into …` switch, the Target-language picker, routing by output language, the 8B-for-Polish-quality rationale).
It is a cutover, not a deprecation: the translation paths get deleted rather than hidden behind a switch, and the tests that pin
them get rewritten around the new contract (*same language in, same language out*).

**Engine fact established while diagnosing his report** (`params.translate` in `Whis/WhisperFullParams.swift` defaults to `false`
and `Engines/WhisperEngine.swift` never assigns it): whisper never translated anything for this app. Every Polish→English result he
saw came from our own transform running with an English target — precisely the path this decision removes, which is why dropping
translation also resolves his complaint rather than leaving it half-fixed behind a disabled feature.

**Task `fm-20260924-07`** (`fm/translation-off`, brief written, queued) is sequenced **after** `fm/shortcut-recorder` lands, because
both tasks edit `Settings.swift` and the second must rebase on the first.

**Follow-up implied, not yet done:** the published release `v0.1.0-fork.1` and its notes advertise translation as a feature. Once this
cutover lands, the honest move is a `0.1.0-fork.2` build with corrected notes (and the old release either edited or left as the
historical artifact it is) — the captain's call, recorded here so it is not forgotten.

## [2026-09-24T14:04:43Z] FOUR CONFIRMED CHOICES (asked, answered) — queued accordingly

Asked directly, the captain settled the open decisions:

1. **Key-press streamlining scope** = *interference safety only* ("never corrupt a flow"). Throughput, paced/typewriter delivery and
   trigger-edge timing are out. Task `fm-20260924-08` dispatched in parallel (its files are disjoint from the other two crews'):
   stop cleanly when the frontmost app changes mid-delivery (asserting the *tail* never reaches the new app) and when the user's own
   typing interleaves with injected events, reporting the outcome through `InjectionResult`.
2. **Language: always auto-detect, the picker goes.** With translation gone the only job left for a language setting was to be set
   wrong — a fixed wrong value is exactly what turns speech into nonsense. So `params.language = nil` always, the Language control
   leaves Settings and onboarding, and the English-only-model guard is re-keyed to the detected/heuristic signal because there is no
   setting left to compare against. Folded into `fm-20260924-07`.
3. **The fm-16 occlusion delta: the captain tests it, then decides.** Steps given to him: launch the latest build, close the main
   window, click **Settings…** in the status-bar menu. If Settings opens with the window closed, the delta is unnecessary and gets
   dropped; if it does not, the stashed delta becomes the next task. It stays in `stash@{0}` until then.
4. **Release: cut `0.1.0-fork.2` after the cutover and the shortcut fix land** — rebuild, refresh `/Applications`, publish with
   corrected notes — and **leave `v0.1.0-fork.1` untouched as the historical artifact it is**. The old notes stay wrong by design;
   fork.2 supersedes them.

**Also now dead, with the translation feature:** the optional `seed` in the endpoint request body (the endpoint goes entirely) and the
14B rung measurement (it was a Polish-*output* quality comparand for translation; Polish tone/clean-up keeps the 8B as its preferred
optional backend). Neither needs a decision any more.

## [2026-09-24T14:27:51Z] fm-20260924-08 LANDED LOCALLY — delivery stops instead of corrupting a flow

Merged `--no-ff` as **`58d3744`** (branch `fm/keypress-streamline` @ `407821f`; product `+222/−17` in
`KeyboardSimulator.swift` + `IndicatorWindow.swift`, tests `+346` in two files, 7 new cases). The captain scoped this
feature down to one aspect — *"Interference safety — never corrupt a flow"* — and that is exactly what landed; throughput,
pacing and trigger-edge timing were deliberately not touched.

**What it does.** Delivery captures the target when it begins and, before every pair of events, asks a `DeliveryWatch`
whether anything changed. Two interruptions stop it cleanly and are reported: `focusChanged` (the frontmost application's
pid differs from the one captured at the start) and `userTyping`. Nothing of the remaining transcript reaches the newly
frontmost app, and the user is told through the indicator how much was delivered and that the rest is in the dictation
history — the same reporting path the untrusted-Accessibility warning already uses (`AppErrorCenter`).

**The discriminator, and why it cannot misfire.** A run-loop-driven `NSEvent` monitor or an event tap is unusable here:
delivery is a single uninterrupted main-thread turn (~0.16 ms for 1000 characters), so no callback can run inside it. The
watch therefore reads two synchronous probes between chunks: `NSWorkspace.frontmostApplication` (0.23 µs per read) and the
login session's `CGEventSource.counterForEventType(.combinedSessionState, .keyDown)` (0.01 µs), subtracting the key-downs
this delivery posted. A surplus is a keystroke the process did not make; a **negative** surplus means the session never
counted our posts, which is also silence; a counter that went backwards is treated as no evidence. So the failure mode is a
*missed* stop, never a stopped dictation — and the empty transcript returns before the watch is ever consulted, asserted.

**Verified (first mate, clean state, headless, alone on the machine, from the `xcresult` summary):** 453 total / 399 passed /
0 failed / 54 skipped, `Passed`, exit 0; all six `KeyboardSimulatorInterferenceTests` cases green, including
`testDeliveryStopsWhenTheFrontmostApplicationChanges` (asserts the new target holds nothing, and its unguarded control shows
the tail would otherwise have leaked there) and `testTheLiveWatchTellsItsOwnKeystrokesFromTheUsers`; bundle identity-signed.

**Contract untouched, verified by absence from the diff:** `maxUTF16PerEvent` stays 20, `keyboardSetUnicodeString` unchanged,
no delays added, clipboard never touched, Accessibility the only grant — and `KeyboardSimulatorDeliveryTests` (the
`fm-20260923-26` contract) still green.

Worktree and branch torn down after landing; the refs went into the records branch as
`fleet-state` @ **`1160c36`** (local commit — nothing is pushed until the captain says so).

## [2026-09-24T14:41:24Z] fm-20260924-06 LANDED LOCALLY — the shortcut recorder and the silent trigger wipe are fixed

Merged `--no-ff` as **`210cfb8`** (branch `fm/shortcut-recorder` @ `058d08a`): `Settings.swift` +75/−7, `ShortcutManager.swift` +9,
new `ShortcutRecorderTests.swift` +332 (four cases). This closes the captain's report — *"Shortcut recording is not working
properly"*, *"the hook is not monitoring my input properly"* — whose mechanism was pinned before dispatch.

**Root cause, verified independently in the library source.** `KeyboardShortcuts.RecorderCocoa` creates its
`LocalEventMonitor` **only inside `becomeFirstResponder()`** (`RecorderCocoa.swift:343`, the monitor at `:363`). In this AppKit
context a click installs the *field editor* as the window's first responder and never asks the field itself, so the monitor was
never created: the recorder looked alive, the field accepted the keystrokes as text, and nothing was ever stored. The crew proved
it by hosting the real Settings view as a sheet and using the library's own `recorderActiveStatusDidChange` notification as the
detector — library-as-it-comes: `recording=[false,true,false]`, `stored=nil`, the field showing the typed `K`; through the new
host: `recording=[false,true]`, `stored=Option-Shift-K`. A mutation restoring the old `hitTest` reproduces the symptom and fails
the new case.

**The fix.** A small `NSViewRepresentable` host hands the recorder the first responder on the click and keeps everything else the
library does (display, conflict checks, storage, monitoring toggling); the dead `isRecordingNewShortcut` state and its
unreachable hint are removed. **Second half of the report** — the silent wipe — is closed by arming rather than preserving: in
key-combination mode with nothing stored, the app applies the name's declared initial (`⌥``) instead of monitoring nothing, so
the mode can no longer be selected with no trigger and no word. The alternative (restoring `lastModifierOnlyHotkey`) was rejected
with a reason I agree with: the trigger mode is *derived* from the hotkey preferences, so restoring the modifier key would snap
the segmented control back and break the mutual exclusivity. Stated trade-off: a deliberate clear of the field is undone at the
next reconfigure.

**Verified (first mate, clean state, headless, alone, `xcresult` summary):** 450 total / 396 passed / 0 failed / 54 skipped,
`Passed`; all four `ShortcutRecorderTests` green, including the library-as-it-comes control that captures nothing; bundle
identity-signed. **Flagged, not hidden:** the crew could not obtain a key window in-process, so both measurements are in non-key
windows — the fix does not depend on that, since the app hands the responder over itself.

**Immediately before the captain's app was touched:** his machine had `modifierOnlyHotkey` restored to `leftOption` by hand (the
immediate remedy from the diagnosis) and the app left quit so the value could not be overwritten at exit. The fix means the
*recorder* now works, so he can record whatever combination he wants from the UI.

Worktree and branch torn down; refs bundled into `fleet-state` @ **`cd1e9a8`** (local commit — nothing pushed until he says so).
`fm-20260924-07` (translation cutover, auto-detect-only language) has been dispatched from `210cfb8` and is the last queued crew task.

## [2026-09-24T14:57:22Z] OPEN RED — one long-form case, merged tip `210cfb8`, cause unresolved

The merged-tip verification run (fm-08 + the shortcut fix together) came back **red on one case**:
`WhisperLongFormLanguageIntegrationTests.testCancellingLongWhisperDecodeStopsNativeOperation()` —
`XCTAssertTrue failed - The fixture never reached whisper.cpp decoding`. Totals: **457 total / 402 passed / 1 failed /
54 skipped** (457 = 450 from the shortcut branch + fm-08's 7 cases, so both landings are present).

**What is known, and what is not.**

- The assertion polls `service.progress > 0.12` for **1000 × 20 ms = 20 s** (`LongFormTranscriptionTests.swift:461-477`)
  before failing. Generous, but not unlimited — and the machine was carrying the fm-07 cutover crew's build at the same
  time.
- Neither landing touches the engine or the transcription/cancel path: `fm-20260924-08` changed
  `Utils/KeyboardSimulator.swift` and the injection part of `Indicator/IndicatorWindow.swift`; the shortcut fix changed
  `Settings.swift`, `ShortcutManager.swift` and added a test file. This test drives `TranscriptionService` directly.
- The model fixture is reachable in the primary checkout: `.build/test-models/` is empty there (that hard link belonged
  to the removed fm-24-01 worktree) but `dev-run.sh`'s `multilingual_test_model()` falls back to the app's own
  `whisper-models/ggml-large-v3-turbo.bin`, which is present.
- Load average was 19-21 during the run **with no CPU consumers and no D-state processes** (checked: `ps` shows 0.0% CPU
  across the board, 0 uninterruptible, ~19 GB free, disk ~15 MB/s). So the number is real but its source is not obvious
  on this host; it is recorded as an observation, not as an explanation.
- An isolated re-run of that class was started (`/tmp/isolated-longform.log`); an earlier attempt produced no output
  within 300 s while the crew was building, which is why the measurement is being repeated rather than concluded.

**Next, in order:** let the fm-07 cutover crew settle (it will rebuild and test, and it is rewriting the language-related
tests anyway — `settings.selectedLanguage = "en"` in this very case may not survive the auto-detect change); then re-run
the merged tip on an otherwise idle machine. **Green there ⇒ contention, recorded with both logs. Red again ⇒ a real
bug, and it becomes the next task** with the poll bound and the progress signal as the first suspects.

## [2026-09-24T15:05:22Z] RESOLVED — the long-form red was load-induced, not a regression

The isolated re-run settles it: `Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/WhisperLongFormLanguageIntegrationTests`
→ **`** TEST SUCCEEDED **`**, exit 0, with both cases passing —
`testCancellingLongWhisperDecodeStopsNativeOperation()` in **159.5 s** and
`testLongEnglishAndRussianAudioKeepsLanguageContextAndTail()` in 34.7 s. Neither landing touched the engine or the
transcription/cancel path, and the case passes alone on the same bytes that were red in the full run, so the red is
**contention with the fm-07 crew's build**, not a defect.

The timing is the evidence: this case normally runs in roughly the time its 20 s progress poll plus one decode needs; 159 s
means the machine was degraded by a factor of several while the full suite ran. The fragility is in the test, not the
product: `LongFormTranscriptionTests.swift:461-477` polls `service.progress > 0.12` for 1000 × 20 ms and asserts if the
native decoder never started *inside that window* — a fixed bound for a load-dependent event, the same family as the
snapshot-capture bug fixed earlier today. **Follow-up, cheapest honest form:** raise that wait to a real time budget (or
wait on the decode-start signal rather than a progress threshold) — waiting longer for a start-of-decode signal cannot make
a wrong result pass, so it weakens nothing. The fm-07 crew, which is already rewriting these tests for the cutover, has been
asked to do it in passing.

**Load observation, still unexplained:** during the affected run the 1-minute load average sat at 19-21 while `ps` showed no
CPU consumers, no uninterruptible processes, ~19 GB free memory and ~15 MB/s of disk. Recorded as an observation about this
host; nothing in the fleet's own processes explains it.

## [2026-09-24T16:31:46Z] RELEASE 0.1.0-fork.2 PUBLISHED — the product without translation

Built from the cutover tip **`3dcde52`** and published as
`https://github.com/23n0n/OpenSuperWhisper/releases/tag/v0.1.0-fork.2`: tag at `main`, assets
`OpenSuperWhisper-0.1.0-fork.2.pkg` (87,549,062 bytes) and its `.sha256`
(`a39d6a0a01134624f5ec8afba74d5109e48790dd74f59d342b735a4a4b4031d2`). `Scripts/verify-packaging.sh`: **ALL CHECKS PASSED (39)**.

**Notes corrected, not hidden:** they lead with *"translation is gone, deliberately"*, name what was removed with it (the
switch, both pickers, the endpoint override, `transform-server.sh`, `verify-transform.sh`), state that
`v0.1.0-fork.1` remains as the historical artifact whose notes describe a feature this build no longer has, and then describe
what the build actually does — same-language tone and clean-up, auto-detected language, the optional 8B that Polish prefers
when installed, zero model calls with both switches off, interference-safe delivery, the long-form recall numbers, model
management, and the one practical Gatekeeper line.

**Pushed for it, and only for it:** `main`, `feat/local-translate-tone` and `fleet-state` went to `origin` as fast-forwards
(`main` had to be fast-forwarded locally first — it was still at `ffda358`). `upstream` received nothing; no pull request
exists against it.

**Installed copy refreshed:** `/Applications/OpenSuperWhisper.app` now carries the fork.2 build — `codesign --verify --deep
--strict` valid on disk and satisfies its designated requirement (`certificate leaf = H"32266bcc…"`), binary 29,368,096
bytes (smaller than fork.1's 29,451,984, consistent with the removed code), and **`Target language` is absent from the
binary's strings** — the removed surface is gone from the artifact, not merely from the source. The app was not running
during the swap, so nothing was interrupted.

**What remains:** the captain's own two checks — launching this build and the fm-16 occlusion test (close the main window,
click `Settings…` in the status-bar menu) — and nothing else is queued.

## [2026-09-25T05:39:34Z] TONE OUTPUT — measured, designed, queued (dispatch held for off-peak)

Captain: *"Tone transcription is not working as intended… the whole mechanism or pipeline is working. The only thing
that is lacking is the correct output."* Then, after the evidence below: **"Both tasks A and B should be completed."**

**Measured before designing anything** (harness `/tmp/tone-ab.py`, real weights over `llama-server` with the app's own
sampling, seven adversarial cases, three prompt variants, two models; full tables in `data/fm-20260924-10/tone-prompt.md`):

- **The model is the dominant variable.** Every failure a user notices on `qwen2.5-1.5b-instruct-q4_k_m` — an added
  `"Sure,"`, a preamble (`"Sure, here's the rewritten text in a casual register:"`), dropped articles, an invented
  noun, and at temperature 0 an outright `"Understood."` — **is absent on `qwen3-8b-q4_k_m` with the same prompt.**
- **Temperature 0 is worse than 0.2** on both models; no sampling change.
- **The proposed prompt is not a win on its own**: equal-or-better on the 8B, and it introduced the preamble on the
  small model. Hence A and B together: the prompt makes good output likelier, the 8B makes it possible, the guard makes
  the bad case impossible.
- Casual and neutral legitimately return text unchanged when it is already in that register.

**A** — tone runs on the 8B for both languages while it is installed (clean-up alone keeps the language-based
preference); the card states which model a job will use. **B** — the tightened prompt, a framed and delimited user turn
(dictated text is often an imperative or a question, and an unframed turn makes the model obey or answer it), and a
deterministic guard that rejects an assistant frame, a stub, or a language-flipped result and delivers the raw
transcript with a visible notice instead. The guard cannot catch subtle content drift — recorded as a limit, not
papered over.

**Queued as `fm-20260924-11`** (`fm/tone-output`, brief written). **Dispatch held to 10:00 UTC** because the provider's
peak window opens at 06:00 UTC; the captain can overrule that if he wants it started immediately.

## [2026-09-25T05:43:47Z] OPERATING RULE CHANGE — dispatch immediately, gate the expensive steps inside the task

The captain's correction, taken: holding a dispatch until the off-peak window opens wastes the window that is actually
available. From now on a task is dispatched as soon as it is briefed, and **the peak window is handled inside the task**:

- cheap work — code, prompts, unit tests, reading — runs any time;
- expensive work — loading the 8B, any real-weight measurement, `llama-server`, the full suite — is gated by the crew
  itself: `date -u`, and if the hour is 06-09 UTC it waits with a **single shell sleep until 10:00 UTC**. A sleeping shell
  costs nothing; a measurement that runs into peak costs double.

`fm-20260924-11` (tone on the 8B for both languages + the tightened prompt, the framed user turn and the deterministic
guard) was dispatched under this rule, 19 minutes before peak opened, with the gate written into its prompt.

## [2026-09-25T05:50:48Z] CAPTAIN'S DATA POINT — English tone works, Polish tone is the failure

Verbatim: *"The tone transcription is also bound with Polish. The English tone transcription works well."*

That is a significant constraint on `fm-20260924-11`, because its part A routes tone to the 8B in **both** languages,
and the captain now reports that the shipped-model path he already has for English is good. The crew has been told,
before it stops for peak:

- **Prove English does not regress**: same real English dictation through the 1.5B (today's behaviour) and through the
  8B with the new prompt, judged on his terms — meaning kept, register moved, nothing added, no assistant frame. If the
  8B is not clearly at least as good, English keeps the 1.5B and the routing table and card follow that.
- **Make Polish tone the acceptance focus**, measured on his *real* Polish dictations from `recordings.sqlite`, per
  register: is the register moved, is every dictated word still there, is anything invented, is there English leakage
  or honourific invention ("Szanowni Państwo")? If Polish register control on the 8B is weak, the report must say where
  and how rather than declare success.
- Commit the worktree's pending `TransformService.swift` change so the branch is coherent, and stop at the boundary.

**Why this matters beyond the tone task:** his Polish-only failures now have two independent causes recorded — the
pause/segment handling (`fm-20260924-12`) and the tone rewrite (`fm-20260924-11`) — plus the instruction-shaped
`initialPrompt` he still has set, which is measured in `fm-20260924-12` because it affects Polish decoding most.

## [2026-09-25T06:00:38Z] DECISION — one model governs tone; no deletion, no root move; land the branch after off-peak verification

The captain, after the keychain correction: *"I wish to maintain simplicity. Therefore, one model to govern them all. Thus,
a single route for tone transcription that is applicable to both Polish and English. If the current setup is in place, no
changes should be made."*

**Reading, recorded so it is not re-litigated:** he wants **one model serving tone in both languages** — a single route with no
per-language split for tone — and *nothing else changed*. That supersedes the earlier "migrate to the English root and delete
the other model": **no model file is deleted, no root is migrated, the shipped 1.5B and the `~/models` copies stay**, and the
8B stays installed and pinned.

**Correction he was told:** the *delivered* build does **not** satisfy that today — it routes tone per language (Polish → 8B,
English → 1.5B). The unlanded branch `fm/tone-output` does: `TransformModelManager.model(for policy:)` gives tone one model in
both languages, with the per-language preference removed for tone only.

**Plan, no other changes:** finish the crew's admitted gap (weight-backed Polish/English measurements and the full suite were
never run — the off-peak gated step), then **land `fm/tone-output` locally** under the standing order. One nuance stated and
deliberately not changed: clean-up-alone keeps its language rule (Polish → 8B, English → 1.5B); collapsing that too is one line
and happens only on his word.

**Peak:** the timer fired at 06:00:30 UTC and work stopped there. Everything is parked: `fm/tone-output` @ `9c36eae` (four
commits, worktree clean, build re-signed with the identity requirement), the pause task briefed as `fm-20260924-12` and
undispatched, and no heavy process left running. Next off-peak window opens 10:00 UTC (12:00 Wrocław).

## [2026-09-25T06:01:48Z] FREEZE — peak hours, all work stopped (captain's order)

Captain: *"I believe peak hour begins. Freeze all the work!"* — correct, peak started 06:00:30 UTC / 08:00 Wrocław.

**Verified at freeze time:** no `llama-server`, no `xcodebuild`/`swift-frontend`/`clang`, no MLX process, no timers armed. All four crews stopped at 06:00:30. Every worktree clean at its recorded commit; the tone worktree `fm/tone-output` @ `9c36eae` (four commits) with its build re-signed to the identity requirement.

**Parked, in priority order, for the next off-peak window (opens 10:00 UTC / 12:00 Wrocław):**
1. `fm-20260924-11` (tone) — the two steps its own report admits are unexecuted: the weight-backed Polish/English measurements and the full suite (`Scripts/dev-run.sh test`, off-peak only), then land the branch locally. Nothing deleted, no root moves.
2. `fm-20260924-12` (pause task) — briefed, undispatched.
3. The captain's late-afternoon request: the bilingual dictation measurement (Polish and English on the same content), for which the app must be rebuilt with `DEV_SIGN_ENTITLEMENTS` so the Accessibility grant survives.

**Standing constraints reaffirmed:** heavy work only off-peak; never a bare `xcodebuild test` (it launches the GUI); the captain's terminal and app instance are not to be killed, and no headless test run may take down the session. Memory numbers for the record: 8B route = 5.03 GB weights + 576 MiB KV @ ctx 4096 (144 KiB/token); 1.5B = 0.99 GB + 112 MiB (28 KiB/token); one model resident at a time, 10-minute idle unload.

## [2026-09-25T07:11:46Z] HANDOFF PREPARED — restart; the peak guard is live, and the freeze premise was wrong

The captain: *"Prepare the session to hand-off. We need to restart."* The handoff block now heads
`fleet/data/RESUME.md`; this entry is its ledger record.

**The guard turned out to be installed and working — and it contradicts the freeze.** It lives at
`~/.omp/agent/extensions/deepseek-peak-guard.ts` (812 lines, written 2026-09-24 12:45 by another session that
titled itself "DeepSeek peak-hours guard extension"), and native auto-discovery of the agent directory's
`extensions/` loads it in every new session — **verified in the wild**, not inferred: the session started
today at 07:07 UTC in `-Documents-deepseek_general-ai-interactive-portfolio` carries the injected
`com.zenon.deepseek-peak-guard` brief reading *"DeepSeek peak-hours guard is active … DeepSeek billing:
OFF-PEAK (chinese-public-holiday)"*. Its own suite passes every phase
(`cd ~/.omp/agent/skills/deepseek-peak-hours && bun peak-guard.test.ts` → all phases passed), covering
off-peak passthrough, peak blocking without a UI, subagent-spawn blocking, approval persistence, `mode=wait`,
`mode=block`, and the `/peak` commands. Defaults are exactly the desired policy — `enabled: true`,
`mode: "ask"`, `onlyDeepSeekModels: true`, `blockSubagentSpawns: true`, `autoResumeAtOffPeak: true`,
`stopTurnOnPeakEnter: true`, `injectSessionBrief: true` — so **no `deepseek-peak-guard.json` is written**
(absent = defaults; a malformed file also keeps them).

**Why this session had no guard:** it started 2026-09-24 08:33 local, four hours *before* the extension was
written, so it never loaded it. Every session from now on does.

**The freeze was unnecessary.** 2026-09-25 is a Chinese public holiday in the guard's calendar
(`peak_config.json`, 33 entries for 2026, entry `2026-09-25` present), so the provider bills the whole day at
off-peak and the guard gates nothing. Next peak: **Mon 2026-09-28 01:00 UTC**. Nothing heavy was running when
the freeze was ordered, so the freeze cost nothing — but the operating rule from here is *ask the guard*, not
the wall clock: `python3 ~/.omp/agent/skills/deepseek-peak-hours/peak_hours.py status`.

**State frozen for the handoff, all verified at write time:** delivery branch `feat/local-translate-tone` ==
`main` == `3dcde52`, clean; unlanded `fm/tone-output` @ `9c36eae`, 4 commits ahead, clean worktree, and
**both** built apps identity-signed (`certificate leaf = H"32266bcc…"`) — the tone crew's "keychain will not
unlock" claim is void, the stored password unlocks it (exit 0); records on the `fleet-state` branch @
`6fbdc2e`; no process of ours running.

## [2026-09-25T08:01:10Z] TONE LANDED — `fm/tone-output` merged, one model for tone in both languages, verified and measured

The captain's decision (*"one model to govern them all… a single route for tone transcription that is applicable to
both Polish and English"*) is now in the delivery branch. `fm/tone-output` @ **`877d19e`** was fast-forwarded into
`feat/local-translate-tone`, and `main` was advanced with it, so both are **`877d19e`** (16 files, +1175/−158). The
branch's five commits: `741431a` (tone on the 8B in both languages, with a guard on the answer), `e194655` (Readme),
`b9f6893` (`TransformOutcome` carries the guard rejection), `9c36eae` (prompt pin), `877d19e` (the fix pass).

**The requirement, verified in code rather than asserted:** `TransformModelManager.model(for:)` returns one model for
`.tone` and `.cleanUpWithTone` with no language branch, reached through the single injection point
`TransformService.swift:246`; only `.cleanUp` alone keeps the per-language rule. An independent review confirmed both
that and the absence of dead code from the withdrawn "run everything on the 1.5B" plan.

**Verification.** Suite on the fixed head: **434 total / 380 passed / 0 failed / 54 skipped**, `** TEST SUCCEEDED **`,
`SUITE_EXIT=0` (`/tmp/fm2412-tone-fix-suite.log`), bundle identity-signed (`certificate leaf = H"32266bcc…"`). The
earlier run's three failures were all test-side staleness — a fixture the guard correctly rejected, six lowercase
prompt-string pins against a capitalised prompt, and a gate test still expecting the pre-frame transcript.
Measurement with the **exact compiled prompt** on the 8B (78 answers, app sampling, classified by the real guard and
detector): **0 rejections, 0 flips**; the new prompt beats the old in both languages (Polish inventions 2 answers vs 7,
lost words 4 vs 8; English 1 vs 4 invented) and the 8 differing Polish answers against the harness variant are within
run-to-run noise (27/28 identical when the identical prompt is re-run).

**Defects the independent review found and the fix pass closed** — worth remembering as a class: the guard treated
`"here is"`, `"here's"` and `"i've"` as assistant frames, so a rewrite that legitimately kept a dictated opening was
thrown away and the raw transcript delivered with a misleading notice; the record-start warm-up still loaded the
1.5B while tone runs on the 8B, so the first tone dictation paid the cold 8B load the Readme promised was hidden; and
`TransformOutcome.guardRejection` was set and never read, so a rejection was **invisible** — the report claimed the
model ran while the user's own words came back. It now reaches `DictationReport.guardRejection`/`guardNotice`, the
transform label says "answer rejected, transcript kept", and the notice line renders. Deferred with reasons recorded:
the stub floor counting fillers, and the flip rule needing engine/detector agreement.

**Price, stated for the record:** English tone moves from the 1.5B's 0.25 s median to the 8B's ~1.0 s, and the app
holds ~4.2 GB more while the transform model is resident (one model at a time; the 10-minute idle unload still
returns it to the 2.26 GB baseline).

**State:** the merged tip is being rebuilt and re-verified in the primary checkout (`/tmp/merged-tip-suite.log`,
running) so the app the captain launches carries the change; the worktree comes down after that. **Nothing is
published** — `origin/main` is still `3dcde52` and the push waits on the captain. `fm/pause-boundary` is in flight on
its own branch (implementation committed at `1383234`, measurement and suite still owed); it was cut from `3dcde52`,
so expect conflicts in `Settings.swift` and `Readme.md` where both branches touched them.
