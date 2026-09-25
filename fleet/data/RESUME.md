# RESUME — OpenSuperWhisper fork, state at the computer restart

## UPDATE 2026-09-25T08:01:10Z — the tone branch has LANDED (supersedes §2 item 1 of the handoff below)

`fm/tone-output` @ `877d19e` was fast-forwarded into `feat/local-translate-tone` **and** `main` (both now `877d19e`),
after a green suite (434/380/0/54) on the fixed head and a measured exact-prompt run in both languages (78 answers,
0 guard rejections). Details and the review findings behind the fix pass are in `FLEET-STATE.md`. The merged tip is
being rebuilt in the primary checkout so the running app carries it; the tone worktree comes down afterwards.

**Publication rule (captain, 2026-09-25):** push `main` to the fork **only when every local task is finished** — no
partial publication. `origin/main` is still `3dcde52`; local `main` tracks the delivery branch and is ahead by every
landing since. The records branch `fleet-state` is exempt and current.

**Still open from the queue:** `fm/pause-boundary` (ignore long pauses; implementation committed at `1383234` in
`worktrees/OpenSuperWhisper-fm-pauses`, measurement + full suite owed, expect `Settings.swift`/`Readme.md` conflicts
against the new delivery tip) and the bilingual dictation measurement, which needs the captain's own audio. **Nothing
is published:** `origin/main` is still `3dcde52` and the push awaits his word.

## HANDOFF — 2026-09-25T07:11:38Z — restart; read this before anything else

This block supersedes the older state paragraphs below wherever they disagree. Three of them are now
**wrong** and were corrected here: the delivery-branch tip, the worktree list, and the note that the dev
keychain "will not unlock for this session".

### 0. First three actions

1. `cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork` then
   `export FIRSTMATE_HOME=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet`.
2. **The DeepSeek peak guard is installed, verified, and needs nothing armed.** It is loaded automatically
   from `~/.omp/agent/extensions/deepseek-peak-guard.ts` (native auto-discovery of the agent directory's
   `extensions/`), it briefs every new session with the live billing window, and its own test suite passes
   (`cd ~/.omp/agent/skills/deepseek-peak-hours && bun peak-guard.test.ts` → all phases). Ask it, never
   guess the clock:
   `python3 ~/.omp/agent/skills/deepseek-peak-hours/peak_hours.py status` (exit 0 = off-peak, 3 = peak).
   During peak it blocks tool calls and subagent spawns in `mode: ask` until `/peak approve`, or waits with
   `/peak wait` and resumes by itself; `/peak status`, `/peak on`, `/peak off` also exist. Defaults apply
   because no `deepseek-peak-guard.json` is written — do not write one unless the mode must change.
3. Work the queue at the end of this block; item 1 is the only branch that is not yet landed.

### 1. Facts established this session — do not re-derive, do not re-litigate

- **The dev keychain password was never wrong.** `~/.opensuperwhisper-dev/keychain-password`
  (`kxzGTbR6Qbwo9rSFGfL0lJSJLG24B/wI`, mode 600, outside the repo, never committed) **does** unlock
  `~/Library/Keychains/opensuperwhisper-dev.keychain-db` — verified: `security unlock-keychain` → exit 0,
  `find-identity -v -p codesigning` → 1 valid identity, `codesign --sign "OpenSuperWhisper Local Dev"` →
  exit 0 with `designated => … certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"`. The crew's
  single unlock attempt failed transiently (its recorded error even contains
  `SecKeychainCopySettings …: User canceled the operation`, the locked-keychain path); the identical retry
  succeeds. **Both built apps are signed with the identity as of this handoff**, including the tone
  worktree's. No rotation, no re-grant. Its report's "keychain has to be unlocked by hand first" is void.
- **One model serves tone in both languages — the captain's decision, final.** *"I wish to maintain
  simplicity… one model to govern them all… a single route for tone transcription applicable to both Polish
  and English. If the current setup is in place, no changes should be made."* Consequences to hold:
  **nothing is deleted, no model moves roots**, the shipped 1.5B stays, `~/models` stays, the 8B stays
  installed and pinned. The *delivered* build does **not** yet satisfy him (tone is still routed per
  language); the unlanded branch does. That branch is the whole remaining task.
- **Memory budget, measured from the models' own GGUF metadata** (not estimates):
  | | weights | KV @ ctx 4096 | KV/token | step measured |
  |---|---|---|---|---|
  | Qwen3-8B Q4_K_M (36 layers, 8 KV heads, dim 128) | 5.03 GB | **576 MiB** | 144 KiB | 5.62 GB |
  | Qwen2.5-1.5B Q4_K_M (28 layers, 2 KV heads, dim 128) | 0.99 GB | **112 MiB** | 28 KiB | 1.43 GB |
  App sets `defaultContextSize = 4096`, `gpuLayers = 99`, `maxNewTokens = 1024`, temp 0.2, seed 0
  (`OpenSuperWhisper/Llama/Llama.swift`). KV is allocated for the full context regardless of prompt length,
  so each context doubling costs another 576 MiB on the 8B; with 4096 + 1024 output, a ~3000-token
  dictation is refused (`promptTooLong`) rather than truncated. One transform model is resident at a time;
  the 10-minute idle unload returns the app to its 2.26 GB baseline. Total resident measured: 7.88–8.93 GB
  with the 8B, 3.69–3.76 GB with the 1.5B. **The single-route change moves English tone from the 1.5B to the
  8B: about +4.2 GB while resident.** The 19 GB Qwen3-30B-A3B must never be wired (17.2 GB wired, 66 s cold
  load — incompatible with the idle-unload contract).
- **Peak-hours premise corrected.** 2026-09-25 is a **Chinese public holiday** per the guard's calendar, so the
  whole day is off-peak (the provider bills half rate and the guard gates nothing). Next peak:
  **Mon 2026-09-28 01:00 UTC**. The earlier "freeze until 10:00 UTC" was unnecessary; nothing heavy was
  running when it was ordered, so nothing was lost.

### 2. Unlanded work — the only open branch

`fm/tone-output` @ **`9c36eae`**, worktree `worktrees/OpenSuperWhisper-fm-tone` (clean, 0 dirty), **4 commits
ahead of the delivery branch**, build identity-signed. The four commits:

| commit | what |
|---|---|
| `741431a` | tone on the 8B in **both** languages, with the guard on the answer |
| `e194655` | Readme: the 8B is preferred for tone in both languages, not for Polish alone |
| `b9f6893` | `TransformOutcome` carries the guard rejection in its initializer |
| `9c36eae` | the test pins the combined tone+clean-up prompt to the new wording |

**Verified on it:** the app target and the whole test bundle compile clean, and `TransformGuardTests` is
green in-app (13/13, 53 s). **Not verified (its own admission):** the weight-backed Polish/English
measurement and the full suite. That is the off-peak step, and it is now off-peak:

```
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone
Scripts/dev-run.sh test > /tmp/fm2411-suite.log 2>&1          # build + suite + re-sign
# then the measurement: llama-server with the app's sampling (temp 0.2 / top-k 40 / top-p 0.95 /
# min-p 0.05, enable_thinking=false) on qwen3-8b-q4_k_m, the seven cases, both languages, prompt+frame
# exactly as landed (system = TransformService.systemPrompt, user = userPrompt).
```

Then land it locally under the standing order (merge into the delivery branch, re-sign, teardown the
worktree) — and make no other change, per §1.

### 3. The rest of the queue

- `fm-20260924-12` — **ignore pauses, Polish only** (brief written, never dispatched:
  `fleet/data/fm-20260924-12/launch-brief.md`). Long pauses split a Polish dictation into sentences without
  sense; the captain narrowed it to Polish alone.
- **Bilingual dictation measurement** (his late-afternoon request): the same content dictated in Polish and
  in English, then compared. Needs a rebuild with `DEV_SIGN_ENTITLEMENTS` set so the Accessibility grant
  survives, and his spoken audio.
- Ship/teardown: nothing is published for `3dcde52` beyond the fork's own refs; `fleet-state` branch holds
  the records bundle.

### 4. Invariants that have already cost time — do not relearn them

- **Never a bare `xcodebuild test`.** `Scripts/dev-run.sh` is the only correct entry point (it keeps
  `ENABLE_DEBUG_DYLIB=NO`, signs with the identity, clears a stale split layout, re-signs after tests). A
  bare `xcodebuild test` leaves the app **ad-hoc signed**, and the Accessibility grant matches the
  designated requirement — so the app silently loses the ability to type. Check with
  `codesign -d -r- <app>`; it must show `certificate leaf = H"32266bcc…"`, not `cdhash`.
- **Never kill the captain's terminal, the running app, or an omp process.** A previous crew's GUI
  automation SIGHUP'd two whole sessions. Launch the GUI app only through the build/dev-run path, and run
  any long build or measurement detached (`setsid … > log 2>&1 &`), never in the foreground of a session
  whose terminal matters.
- **Never launch a long build through a harness-backgrounded job.** A `bash` call the harness backgrounds (the
  "Backgrounded early to handle an incoming message" path) is torn down with its session: `fm-20260924-12`'s first
  focused run died mid-build that way, leaving a log with no exit marker and a redirect error naming a path the
  command never used. Detach instead — macOS has no `setsid`, so `python3 -c "subprocess.Popen([...],
  start_new_session=True, stdout=open(log,'w'), stderr=subprocess.STDOUT)"` — and pass that recipe to every crew.
- Heavy local work (llama, xcodebuild) spends no provider tokens; the peak rule is about **token spend**.
  That is exactly what the guard gates — so consult the guard, not the clock, and not your own arithmetic.

### 5. Where the records are

`fleet/data/FLEET-STATE.md` (the ledger; this handoff's entry is appended there), `fleet/data/RESUME.md`
(this file), `fleet/data/fm-*/report.md` (per-crew evidence), `fleet/data/fm-20260923-27/` … `fm-20260924-12/`
(briefs), `fleet-state` branch + `fleet-state/archive/*.bundle` (records and branch snapshots), and the
guard's own home: `~/.omp/agent/extensions/deepseek-peak-guard.ts`,
`~/.omp/agent/skills/deepseek-peak-hours/{SKILL.md,peak_hours.py,peak_config.json,peak-guard.test.ts}`.

---

Written 2026-09-24, immediately before a machine restart. Nothing of ours is running; all crews were
cancelled. Nothing needs saving from memory or `/tmp` — the one artifact that mattered (the 5 GB 8B model)
was already moved to `~/models/`. A restart loses no work.

**Corrected 2026-09-24T08:20Z** against the repository and the fleet records by a later session: the
`FIRSTMATE_HOME` requirement, the unpushed state, the provenance of the suite numbers, the worktree/branch
mapping, the priority list and the cautions were added or fixed. What changed and why is recorded in the
reconcile block at the end of `FLEET-STATE.md`.

**Consolidated 2026-09-24T08:45Z** on the captain's instruction: everything for this fork now lives under
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/` — `repo/` (below, this checkout), `worktrees/` (only
the three worktrees still holding unmerged work: fm-15, fm-16, fm-17), `fleet/` (this home, with a
`fleet/`-relative ledger), `docs/` (the fork plan and study, moved out of `Documents/deepseek_general/`)
and `archive/` (the verified bundle). The five merged crew worktrees were removed for ~11 GB, and
`/Volumes/home/zenon/firstmate-home` is now a symlink to `fork/fleet`. Paths in this file and in the rest
of the records were rewritten to the new root; the layout, the build entry point and the restore
procedure are in `fork/README.md`.

**MERGED, THEN PUBLISHED 2026-09-24** — the captain authorised the merge, and then asked for the work to be on
`main`: the delivery branch `feat/local-translate-tone` @ **`23d873a`** (was `5e51124`, then `319f3a3` after the
merges, then the README commit) is clean, and its head is also **`origin/main`** — the fork's own GitHub
repository, and the only place this work is published. Nothing was sent upstream; both `main` and
`feat/local-translate-tone` are on the fork, and `main` is the fork's default branch. A pull request against
Starmel's repository (`#211`) was opened by hand on 2026-09-24 and closed at the captain's request the same
morning — no open PR remains upstream (`FLEET-STATE.md`, UPSTREAM PR CLOSED). Merge commits: `2aebf89` (fm-20260923-17), `d66298b` (fm-20260923-25), `319f3a3`
(fm-20260923-16). The merged tip was re-verified headless at 420 / 367 passed / 0 failed / 53 skipped.
The four crew worktrees were torn down afterwards and `worktrees/` is empty. One further commit followed the
merges: `23d873a docs(readme): describe the fork, its features and every difference from upstream`, which is the
fork's feature description and upstream delta in `repo/Readme.md`. Sections 4, 6 and 7 below are
updated accordingly; `FLEET-STATE.md` carries the merge block, the skip reconciliation and the teardown.

## 1. Where everything is

| what | path |
|---|---|
| app repo (the one you run) | `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo` |
| delivery branch | `feat/local-translate-tone` @ **`23d873a`** (three crew branches merged 2026-09-24, then the README commit), working tree clean; head of **`origin/main`** *and* `origin/feat/local-translate-tone` (the fork carries both refs and `main` is its default branch since 2026-09-24), and the tree is 71 commits ahead of `origin/develop` |
| **set this first** | `export FIRSTMATE_HOME=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet`. The skill derives the home from the working directory, so a session started anywhere else reads a different fleet; that has already cost one session (2026-09-24). |
| firstmate home (state, briefs, reports) | `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet` |
| crew worktrees | **none** — every crew worktree was torn down after its branch landed (2026-09-24; the last three after
  `ffda358`); every landed branch is inside `fleet-state/archive/all-local-branches-*.bundle`, and the only worktrees are
  the primary checkout and the `fleet-state` records branch |
| built app | `<repo>/build/Build/Products/Debug/OpenSuperWhisper.app` |

## 2. How to run it again after the restart

```bash
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer   # only needed for builds
open build/Build/Products/Debug/OpenSuperWhisper.app              # just launch what is built
./Scripts/dev-run.sh build                                        # rebuild + sign (identity)
./Scripts/dev-run.sh test                                         # build + full suite + re-sign
```
`Scripts/dev-run.sh` is the only correct entry point: it keeps `ENABLE_DEBUG_DYLIB=NO`, signs with the
identity, removes a stale split layout, and re-signs after a test run. A bare `xcodebuild test` leaves the
app **ad-hoc signed**, which silently breaks the Accessibility grant.

Expected on launch: one menu-bar app, ⌥ (hold) to record, Polish speech → Polish transcript → English typed
into the focused app.

## 3. Machine configuration as left

- Speech model: `~/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin`
  (multilingual). Also present: `ggml-tiny.en.bin` (English-only — **never** use with language `auto`).
- Transform: **in-process** 1.5B, `~/Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models/qwen2.5-1.5b-instruct-q4_k_m.gguf`
  (SHA-256 verified). `transformUseExternalEndpoint=0` — no server involved.
- Other models on disk: `~/models/Qwen3-8B-Q4_K_M.gguf` (5.03 GB, the chosen Polish-output backend),
  `~/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` (19 GB, optional maximum-quality, needs ~18 GB wired).
- Prefs that matter (`defaults read ru.starmel.OpenSuperWhisper`): `modifierOnlyHotkey=leftOption`,
  `holdToRecord=1`, `translateEnabled=1`, `toneEnabled=0`, `whisperLanguage=auto`, `selectedEngine=whisper`,
  `transformTargetLanguage` unset = English default.
- Accessibility grant: given to the **identity-signed** app (`certificate leaf = H"32266bcc…"`). If the
  indicator says keystrokes are off after the restart, the grant was invalidated with the signature —
  re-grant in System Settings; the app now warns inline instead of blocking.
- `/tmp/fm24-models/` no longer exists (the 8B model was moved to `~/models/`).

## 4. What is live in the app now

Suite state **measured** on the merged tip **`ffda358`** (2026-09-24, all three landings): **446 total, 392 passed,
0 failed, 54 skipped**, `Passed`, read from the `xcresult` summary — 444 (the fm-26 branch, which excludes fm-27) plus
fm-27's two determinism cases. Earlier the same day, before those landings, the merged tip `319f3a3` measured
420 / 367 / 0 / 53. The older paragraph, kept as provenance:

Suite state **measured** on the **merged** tip `319f3a3` (2026-09-24, alone on the machine): **420 total,
367 passed, 0 failed, 53 skipped**, `Passed` — the merge of the three branches was re-verified, not assumed.
Of the 53 skips, **50** are input-layout/Accessibility-gated, 2 are `OSW_TEST_TURBO_MODEL` opt-in and 1 is the
microphone opt-in; `ClipboardUtilPasteIntegrationTests.testPasteWithTurkishLayout()` is conditionally gated
(it skips under load, passes alone) so the gated count can read 50 or 51. Before the merge, the tip was
measured the same day by `fm-20260924-01` —
`rm -rf libllama/build libwhisper/build && Scripts/dev-run.sh test` in
`worktrees/OpenSuperWhisper-fm-fm-20260924-01`: **381 total, 326 passed, 1 failed, 54 skipped**, result
`Failed`; the fm-16 crew's uncontended run of the same suite: **381 / 327 / 0 / 54**, `Passed`. The single
red case — `SettingsLayoutSnapshotTests.testEveryTranscriptionCardLaysOutWhateverTheSwitchesSay()` — passed
3/3 when that class ran in isolation, and its file is untouched by any commit between `32aacc0` and the tip,
so it is contention, not a regression. Delta against the 379/325/0/54 recorded at `32aacc0`: **+2 total / +2
passed, skips unchanged**, because `ce1619e` stopped `dev-run.sh` excluding
`WhisperLongFormLanguageIntegrationTests` with `-skip-testing:` (an excluded case is in neither the total nor
the skip count, and both cases now run and pass). Evidence, commands and skip reasons:
`data/fm-20260924-01/report.md` and `data/fm-20260924-01/logs/`.

1. No permission gate — inline grant notices, onboarding "Skip for now"; builds can no longer launch in the
   broken split-dylib layout. Root cause proven: ad-hoc linker-signed split build vs TCC's identity
   requirement (`tccd … status: -67050` two seconds after the grant was recorded Allowed).
2. Settings sheet usable — macOS lays a `TabView`'s strip out **0×0 inside a sheet**; replaced with a
   segmented picker; sheet fits the window; snapshot test guards it.
3. Target language (English default, Polish) with pass-through when spoken == target (no model call).
4. Indicator reports "No microphone" instead of "Processing…" (guard order fixed).
5. Test isolation — per-process preference stores, fixtures resolved explicitly; tests no longer read your
   `selectedWhisperModelPath`.
6. **Long-form audio loss fixed** — `noTimestamps = !showTimestamps` (default off) made whisper.cpp advance
   the seek a full 30 s per window and discard untranscribed audio. **Re-measured on the delivery tip
   `5e51124` by `fm-20260924-01` (2026-09-24)**: unique-word recall **0.9932 EN**
   (`0.9932432432432432`) and **0.9873 RU** (`0.9873417721518988`), tail recall **1.0** in both languages,
   **0 replayed four-word runs**, 32 EN / 22 RU decoder segments, against `ggml-large-v3-turbo` (offered to
   the tests as `.build/test-models/ggml-tiny.bin`, a real hard link to it — same inode). Command:
   `Scripts/dev-run.sh test` in `worktrees/OpenSuperWhisper-fm-fm-20260924-01`; the numbers are read from
   the test's own `.keepAlways` attachment with `xcrun xcresulttool export attachments`, and reproduce the
   figures the handoff asserted to every printed digit. Transcripts:
   `data/fm-20260924-01/logs/longform-{en,ru}-transcript.txt`; full evidence and the reconciliation of the
   suite totals: `data/fm-20260924-01/report.md`. The evidence gap this item described is closed.

## 5. Diagnoses and decisions that must not be re-litigated

- "The translate model is shit" was an input problem: English-only `ggml-tiny.en.bin` + language `auto`
  produced English hallucination before the transform ran. Same WAV: tiny.en → "There are some people who
  are going to go to the airport."; large-v3-turbo → "Teraz mówię po polsku i chcę, żeby była po polsku."
- Polish → English keeps the shipped 1.5B: 8/8 correct, ~0.29 s, 1.1 GB.
- **Polish output uses Qwen3-8B** (your decision): 11/15 clean, never invents, 5.33 GB wired, 3.2 s cold load,
  idle unload viable. Pinned: `https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf`,
  SHA-256 `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785`, 5 027 783 488 bytes.
  The 30B-A3B is better (12/15, no broken grammar) **and** faster (1.04 s) but needs ~18 GB wired and a 44 s
  cold load, so it cannot honour the 10-minute idle unload.
- Unresolved: the **in-process** transform is non-deterministic (8/10 outputs differed between identical
  runs) while the same model over `llama-server` is byte-identical ×3 — the fix was cancelled mid-flight.

## 6. Work that was stopped mid-flight — ALL THREE BRANCHES MERGED 2026-09-24

Everything in the table below is now on the delivery branch (`2aebf89`, `d66298b`, `319f3a3`); each was
green headless in its own worktree before the merge and the merged tree was green again afterwards. The
table is kept as the provenance of each branch. The one item still unlanded is the fm-16 occlusion delta,
which sits in the repo-level stash (`stash@{0}`) because proving it needs the screen.

| worktree (this is where the work lives) | branch @ tip | state |
|---|---|---|
| `…-fm-20260923-16` | `fm/fm-20260923-16` @ `8e8b92a` | committed: "add Settings… to the status-bar menu" + 1 uncommitted file (`OpenSuperWhisper/OpenSuperWhisperApp.swift`) |
| `…-fm-20260923-15` | `fm/fm-20260923-15` @ `5263999` | committed: G-04 remove models (space freed), G-05 installed-models list + Use/Verify/Remove + Selected line, G-06 real SHA-256 verification incl. the bundled model, G-07 fallback as a notice; 7/7 ModelStorageTests green. **This is the `fm-20260923-25` assignment** — the brief is `data/fm-20260923-25/launch-brief.md` while the branch is named `15`; that id mismatch is real, not a typo |
| `…-fm-20260923-15` (uncommitted) | — | G-02/G-03 Permissions card (Accessibility + Microphone + Open System Settings), G-10 honest "keystrokes, no clipboard" subtitle, G-11 Debug Mode wired (orphan `qwen3Variant` deleted), G-12 Welcome-Screen reset card, updated snapshot tests + `SettingsExposureTests`, and one unbuilt polish pinning the bundled model's digest — 5 entries in `git status` |
| `…-fm-20260923-17` (uncommitted only) | `fm/fm-20260923-17` @ `32aacc0` (that tip is **already merged** as the isolation follow-up) | the fm-17 assignment itself is uncommitted: 7 modified (AppErrorCenter, ContentView, WhisperEngine, IndicatorWindow, TranscriptionService, TranslationService, AppPreferences) + 3 new (`DictationReport.swift`, `Utils/DictationScrubber.swift`, `Utils/SpeechModelLanguageGate.swift`) |
| `fm/fm-20260923-09` (no worktree; branch only) | `fm/fm-20260923-09` @ `98c63fd` | one unmerged commit whose change is **already in the delivery tree** (`dev-run.sh` worktree bundle-id suffix). A duplicate — inspect it, then delete the branch; do not re-merge |
| `…-fm-20260923-{12,13,22,23,27}` | merged | land already on the delivery branch; these worktrees are inert and safe to remove once preservation (`fm-20260924-03`) is done |

None of the uncommitted sets was built or tested together; everything through G-12 was green before the last
polish. To inspect: `git -C <worktree> status` and `git -C <worktree> log --oneline -3`. The ledger
(`state/tasks.json`) carries the same mapping — verified against disk on 2026-09-24.

## 7. Open tasks, in priority order

Rewritten 2026-09-24, after the merges and after the branch cleanup. Every open entry has a complete brief
under `data/<id>/launch-brief.md`. Order is project value, not agent convenience.

**TRANSLATION REMOVED, RELEASE 0.1.0-fork.2 PUBLISHED (2026-09-24, tip `3dcde52`).** The captain dropped the translation feature
entirely: the app never changes a dictation's language, and the switch, both pickers, the external endpoint and the two
transform scripts are deleted. Tone is a same-language rewrite, clean-up/judgement runs in the spoken language, the 8B is an
optional backend Polish prefers when installed, and the engine always auto-detects. Published on the fork as `v0.1.0-fork.2`
with corrected notes; `v0.1.0-fork.1` stays as history. The `/Applications` copy was refreshed to this build.

**Delivery mode:** every verified branch is merged locally into `feat/local-translate-tone` without asking, and the
push happens once at the end. **That publish has happened** (2026-09-24): `main`, `feat/local-translate-tone` @ `ffda358`
and `fleet-state` @ `086243f` are on `origin` = `23n0n/OpenSuperWhisper`, all fast-forwards, verified with
`git ls-remote origin`. Nothing was sent to `upstream` and no pull request is open against it.

**Landed** on `feat/local-translate-tone` (and `main`, both on the fork): `fm-20260923-16`, `-25`, `-17`; the
measurement `fm-20260924-01`; the preservation `fm-20260924-03`. Since then: the README feature description,
the `fleet-state` records branch, and the branch cleanup — 17 finished branches deleted, each verified inside
`fleet-state/archive/all-local-branches-20260924.bundle` first.

1. **fm-20260923-28** — Qwen3-8B as the Polish-output backend (your decision). **READY, unmerged**: branch
   `fm/fm-20260923-28` @ `0a4f5f8`; two headless full-suite runs green (387 passed / 0 failed / 54 skipped);
   routing, the missing-model refusal, the digest checks, wired RAM, latency and the idle unload all proven
   by execution. Awaiting the captain's merge word. Detail and the false-red story: `FLEET-STATE.md`.
2. **fm-20260923-27** — in-process determinism. Brief rewritten: the sampler is already seed-pinned
   (`Llama.swift:270-278`, `dist(seed = 0)` per request, chain freed each time), so drift can only come from
   backend reduction. Reproduce 5x over two process launches, discriminate with CPU-only / single-thread,
   then fix or document — and add the determinism test either way. Runs after fm-28, rebased on its tip.
3. **fm-20260923-26** — delivery-path coverage: 50 of the 53 skips are keyboard-layout-gated, so the path you
   use daily is the least covered in the suite. Test-only code.
4. Optional, not registered: the 14B rung (~9 GB) between the 8B and the 30B-A3B.
5. Needs the captain's screen, not a crew: the fm-16 occlusion delta in `stash@{0}`, and the eyeball pass over
   the merged surfaces (status-bar `Settings…`, the new Settings cards, the last-dictation card).

## 8. Cautions

- **Dispatch crews off-peak only.** The provider bills peak rates during 01:00-04:00 and 06:00-10:00 UTC,
  Monday to Friday (checked against `api-docs.deepseek.com/quick_start/pricing`, 2026-09-24); every other
  hour, all weekend and Chinese public holidays are off-peak at half the rate. A crew was cancelled mid-flight
  on 2026-09-24 for exactly this reason; its worktree survived and was relaunched clean.

- Do not run a bare `xcodebuild test` (see §2). Verify with `codesign -d -r-` that the bundle shows the
  **identity requirement**, never a bare `cdhash`.
- Do not use an English-only Whisper model with language `auto`; that is the hallucination defect.
- Crew worktrees share the app's `.dev` bundle id and (by default) one preference domain — one app instance
  at a time, and prefer `Scripts/dev-run.sh`.
- The suite's 54 skips are environmental and now enumerated from the result bundle: **51 input-layout-gated**
  (36 `ClipboardUtilPasteIntegrationTests` + 9 `ClipboardUtilKeyboardLayoutTests` + 6
  `KeyboardLayoutProviderTests`; only `Polish Pro` is enabled on this machine), **2** turbo opt-in
  (`OSW_TEST_TURBO_MODEL`), **1** microphone opt-in (`OSW_TEST_MICROPHONE=1`). The long-form path no longer
  skips since `ce1619e`. `fm-20260923-26` targets the layout-gated 51. Source:
  `data/fm-20260924-01/logs/skip-reasons.txt`.
- **Ledger semantics after the 2026-09-24 reconcile.** `state/tasks.json` is trustworthy again, but read the
  `status` field, never the `updated` timestamp: `parked` = the captain halted the crew and the work sits
  unlanded in the row's `worktree`; `ready` = the crew finished, the work is unlanded and awaiting a merge
  decision. Two rows (`fm-20260923-15`, `fm-20260923-25`) deliberately point at the **same** worktree and
  branch.
- `fm/fm-20260923-09` carries one unmerged commit that is already in the delivery tree — a duplicate. Do not
  merge it; delete the branch when convenient.
- **Everything is on one disk, plus one remote.** The work is published as `main` on `origin` (the fork's own
  repository) and nowhere else; upstream has received nothing. The unlanded work exists only in the
  worktrees. `fm-20260924-03` exists because of that.
- Two fleet homes exist on this machine (`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet` — this project — and
  `/Volumes/home/zenon/Documents/deepseek_general/firstmate-home` — the other project). Always export
  `FIRSTMATE_HOME` (section 1) before reading or writing fleet state; a stale lock in the wrong home has
  already misled one session.
- Task ledger and per-task logs: `firstmate-home/state/tasks.json`, `firstmate-home/data/fm-*/status.log`,
  fleet history in `firstmate-home/data/FLEET-STATE.md`.
