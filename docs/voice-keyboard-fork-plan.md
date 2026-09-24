# Fork Plan — OpenSuperWhisper + Local Polish→English + Tone

Companion to `voice-keyboard-study.md` (feasibility and cost). This document is the
execution plan: what to fork, what to change, in what order, and how to verify.

Status: plan only. No repository forked yet.
Revision 2: adds transform/hook ordering, cancellation, history-storage decision,
Qwen reasoning handling, and latency reconciliation. All code references below were
verified against a fresh clone of `Starmel/OpenSuperWhisper` (`main`).

## 1. Goal and scope

Turn OpenSuperWhisper into a local dictation app that also:

- Transcribes Polish speech locally.
- Translates Polish → English locally.
- Applies a local tone adjustment.
- Delivers the result to the focused app by simulating keystrokes (`CGEvent` carrying a Unicode
  string). The clipboard is never touched on the injection path.

In scope:

- One new transform service.
- One integration hook in the paste path.
- Preferences and a settings section.
- Tests for the new code.

Out of scope (v1):

- Streaming / partial transcription.
- Rewriting the STT engine or switching from whisper.cpp.
- Notarization, App Store distribution, auto-update.
- Cloud fallback by default.
- Storing a second translated column in the recording database (decision in Phase 3).

## 2. Base and branch strategy

- Fork `https://github.com/Starmel/OpenSuperWhisper` (MIT) to your own GitHub account or
  a private remote.
- Local remotes:
  - `origin` = your fork.
  - `upstream` = `Starmel/OpenSuperWhisper` (for later rebases).
- Upstream default branch is **`develop`** (not `main`); a `master` branch also exists.
  Base the feature branch on `develop` and keep `develop` a clean mirror of upstream.
- Work on `feat/local-translate-tone` (created off `develop`).
- Commit in small units: build fixes, service, hook, settings, tests.

## 3. Phase 0 — Environment and baseline build

Prerequisite tooling (per upstream `Readme.md` and `run.sh`):

```
brew install cmake libomp rust ruby
gem install --user-install xcpretty
```

**Full Xcode is required, not just Command Line Tools.** `run.sh` uses
`cmake -G Xcode` and `xcodebuild`, both of which need `/Applications/Xcode.app`.
Command Line Tools alone fail with `xcodebuild requires Xcode` and CMake reports
`Xcode 1.5 not supported`. After installing Xcode, accept the license as root once:

```
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

Until the license is accepted, `xcrun` refuses to find `clang`/`clang++`, and CMake
fails with `No CMAKE_C_COMPILER could be found`.

Steps:

1. `git clone <your-fork> OpenSuperWhisper && cd OpenSuperWhisper`
2. `git remote add upstream https://github.com/Starmel/OpenSuperWhisper.git`
3. `git submodule update --init --recursive` — pulls `libwhisper/whisper.cpp` and
   `asian-autocorrect`.
4. `./run.sh build` — configures `libwhisper` with CMake, builds the Rust
   `autocorrect_swift` dylib, then runs `xcodebuild`.
5. Launch the built app once to confirm baseline dictation works and permissions are
   requested.

Run the build with Xcode selected and the user gem bin on PATH (e.g.
`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` and
`export PATH="$HOME/.gem/ruby/*/bin:$PATH"`). If `xcode-select` cannot be switched
(no root), `DEVELOPER_DIR` is sufficient for both CMake and `xcodebuild`.

Exit criteria for Phase 0: baseline app builds and transcribes English with no changes.

### Phase 0 status

- Fork created: `https://github.com/23n0n/OpenSuperWhisper` (fork of `Starmel/OpenSuperWhisper`).
- Clone: `/Volumes/home/zenon/Projects/OpenSuperWhisper`; branch `feat/local-translate-tone`;
  `origin` = fork, `upstream` = Starmel.
- Toolchain installed: cmake 4.4.3, rust/cargo 1.98.1, xcpretty 0.4.1 (user gem).
- Submodules initialized: `whisper.cpp` v1.9.3, `asian-autocorrect`.
- Xcode 27.0 (27A266a) installed from the App Store.
- Blocker: Xcode license must be accepted as root before `xcrun` can find clang
  (see the three `sudo` commands above).

If the Rust autocorrect step blocks, it can be skipped for this feature; autocorrect is
not required for translation or tone. `run.sh` builds the Rust step unconditionally, so
skipping it means editing `run.sh` locally or pre-creating `build/libautocorrect_swift.dylib`.

## 4. Phase 1 — Local transform model availability

Decide and document the transform backend. Two options:

- **Option A (default): local MLX Qwen** already configured on this machine.
  - Server: `http://127.0.0.1:1919/v1/chat/completions`, model
    `Qwen/Qwen3-14B-MLX-6bit`.
  - Must be running. Managed by launchd `com.dsh.mlx-qwen` (currently stopped).
  - Cost: $0.
- **Option B: single-pass whisper translate.**
  - Set whisper.cpp `translate` flag via `Whis/WhisperFullParams.swift`; Polish audio
    becomes English text with no second model. Lower quality, no tone control.

### 4a. Model size vs latency

The acceptance target is ~1-3 s added latency for a short utterance. `Qwen3-14B-MLX-6bit`
plus Whisper may exceed that on longer utterances. Prefer a smaller transform model for
v1 if latency misses the target:

- Try `Qwen3-8B` (or 4B) first; it is configured through the same endpoint and model
  toggle, so switching is a preference change, not a code change.
- Keep 14B as the quality fallback.

The endpoint and model are configurable (`transformEndpoint`, `transformModel`), so the
choice does not block the build.

### 4b. Reasoning-token handling (Qwen3)

`Qwen3-14B` is a reasoning-capable model. It can emit ` thinking...<｜end▁of▁thinking｜>` content or a
separate `reasoning_content` field. The transform must never paste that. Two defenses:

- Request body sets `"chat_template_kwargs": {"enable_thinking": false}` (or appends
  `/no_think` to the system prompt, whichever the running MLX server supports).
- The response parser strips ` thinking...<｜end▁of▁thinking｜>` blocks and any `reasoning_content`
  field before using the result (Phase 2).

Plan for Option A as primary, Option B as a fallback if the LLM is unavailable.

Optionally, an API route (`deepseek-flash`) can replace Option A. Cost ~$0.0001 per
dictation; keep it opt-in, off by default to preserve the "local" guarantee. When enabled
it sends transcript text off-device, so it must be an explicit user opt-in, not a silent
fallback.

## 5. Phase 2 — New `TranslationService.swift`

Add `OpenSuperWhisper/Services/TranslationService.swift` (~150-250 LOC).

Responsibilities:

- Input: raw transcript string, source language, target language, tone mode.
- Build a chat request to the configured OpenAI-compatible endpoint:
  - `POST {endpoint}/v1/chat/completions`
  - `messages`: a fixed system prompt (translate PL→EN, then apply the tone) plus the
    transcript as user content.
  - Deterministic settings: low temperature.
  - Reasoning disabled (Phase 4b).
- Tone modes (enum): `neutral`, `formal`, `casual`. Map each to one instruction line.
- Timeout (8 s default, configurable). On failure, timeout, cancellation, empty
  response, or reasoning-only response, return the raw transcript unchanged.
- Response parsing:
  - Read `choices[0].message.content`.
  - Strip ` thinking...<｜end▁of▁thinking｜>` blocks.
  - If `reasoning_content` is present and `content` is empty, treat as failure.
  - Trim whitespace; reject empty result and fall back to raw input.
- Cancellation: the request must observe Swift task cancellation. Wrap the `URLSession`
  call so that cancelling the decoding task cancels the HTTP request, or at minimum
  check `Task.isCancelled` before returning and after the response.
- Configuration read from `AppPreferences` (endpoint, model, enabled, tone, timeout).

Failure behavior is the important contract: the app must always paste something and must
never paste reasoning text.

## 6. Phase 3 — Integration hook and ordering

Output method (captain directive, 2026-09-23): focused-app delivery is keypress simulation, not
clipboard paste. `IndicatorWindow.insertText(_:)` calls `KeyboardSimulator.typeText(...)` (new
`OpenSuperWhisper/Utils/KeyboardSimulator.swift`), which posts `CGEvent` keystrokes carrying the text
as a Unicode string. The `ClipboardUtil` paste calls are removed from this path; the injection path
never touches `NSPasteboard`. The `autoCopyToClipboard`-only branch (no auto-paste) may still copy to
the clipboard, since that is an explicit copy action, not the output method. This makes §6a's
clipboard-restore concern moot for the injection path.

Insertion currently happens at:

- `OpenSuperWhisper/Indicator/IndicatorWindow.swift:319` `insertText(_:)`
- `applyPostProcessing` at `IndicatorWindow.swift:340` (adds a trailing space)

`insertText(_:)` is called from inside the decoding `Task` in `decodeRecording()`
(`IndicatorWindow.swift:280`), immediately before `finishDecoding(sessionID:)`. This
makes an `await`ed transform straightforward, but the hook must preserve the existing
cancellation/session semantics.

Change:

1. Add `TranslationService.transform(_:tone:) async -> String` that returns the raw input
   on any failure (Phase 2).
2. In `decodeRecording()`, at the call site (`:280`), replace the direct `insertText(text)`
   with:
   - re-check `Task.isCancelled` and `self.decodingSessionID == sessionID`;
   - `let output = await TranslationService.shared.transformIfEnabled(text)`;
   - re-check `Task.isCancelled` and `self.decodingSessionID == sessionID` again;
   - `insertText(output)`.
3. Do **not** fire-and-forget. The transform must be awaited so the paste cannot race
   `finishDecoding(sessionID:)` or the cancel path.
4. Keep `insertText(_:)` synchronous. It still calls `applyPostProcessing` on its input,
   so the required order is: **translate raw text first, then apply post-processing**.
   This guarantees the trailing space and punctuation check run on the English result,
   not on the Polish transcript.
5. If translation is disabled or fails, `transformIfEnabled` returns the raw text and the
   flow is identical to today.

Cancellation contract: a cancelled decoding session must not paste. The two
`decodingSessionID == sessionID` re-checks above enforce this even if the transform
already returned.

### 6a. Clipboard restore timing (clarified)

`ClipboardUtil.clipboardRestoreDelay` is 1.5 s, and the restore timer starts when
`ClipboardUtil.insertText(...)` posts the paste (`ClipboardUtil.swift:53`), guarded by a
pasteboard `changeCount` comparison.

Because the transform runs **before** `ClipboardUtil.insertText(...)` is called, the
restore timer still starts at the paste, not at the start of the transform. Added
transform latency therefore does not collide with the restore delay. No change to
`ClipboardUtil` is required for v1. Phase 6 still verifies the previous clipboard is
restored.

### 6b. History-storage decision

`recorder.moveTemporaryRecording(...)` and `recordingStore.addRecordingSync(newRecording)`
run at `IndicatorWindow.swift:268-270`, before `insertText`. Today the stored transcript
is the raw text.

Decision for v1: **store the raw Polish transcript** (source of truth, no data loss,
searchable), and paste the English/tone result. Document this in the settings section so
the behavior is explicit. Adding a second translated column is out of scope for v1 and
would be a later migration (Phase 4 UI can note it).

## 7. Phase 4 — Preferences and settings UI

- `OpenSuperWhisper/Utils/AppPreferences.swift` (existing prefs around line 130, e.g.
  `autoPasteTranscription`): add
  - `translateEnabled: Bool`
  - `toneMode: ToneMode`
  - `transformEndpoint: String`
  - `transformModel: String`
  - `transformTimeout: TimeInterval` (default 8)
- `ToneMode` must work with the `@UserDefault` property wrapper: back it with a `String`
  raw value (`enum ToneMode: String`) and expose a computed `var toneMode: ToneMode`
  accessor over a private raw-string default. Do not rely on the wrapper to store the
  enum directly.
- `OpenSuperWhisper/Settings.swift` (1860 LOC): add one section for the above. Do not
  restructure existing sections. Include a one-line note that history stores the raw
  transcript while the paste is transformed (Phase 6b).

## 8. Phase 5 — Tests

Add unit tests under `OpenSuperWhisperTests/`:

- Prompt construction for each tone mode.
- Response parsing:
  - normal content;
  - ` thinking...<｜end▁of▁thinking｜>` stripped;
  - `reasoning_content` with empty `content` treated as failure;
  - malformed JSON;
  - empty response.
- Fallback returns raw input on error, timeout, and cancellation.
- Preference decoding/encoding, including `ToneMode` raw-string round-trip.
- Ordering: given a fake transform, the post-processed result carries the English text
  plus the trailing space.

Follow the existing test style in that directory.

## 9. Phase 6 — End-to-end validation

Manual checks:

1. Focus a text field (TextEdit, browser input).
2. Trigger the hotkey, speak Polish, stop.
3. Confirm English (not Polish) text is pasted.
4. Confirm tone mode changes the output as expected.
5. Confirm the clipboard is untouched by the injection path (previous contents preserved because it
   is never modified).
6. Kill the MLX server; confirm raw transcript still pastes (fallback).
7. Check latency: target ~1-3 s for a short utterance. If it misses, switch
   `transformModel` to a smaller Qwen (Phase 4a).
8. Cancel during transform; confirm nothing is pasted.
9. Confirm history shows the raw Polish transcript (Phase 6b).
10. Confirm no ` thinking` text is ever pasted (Phase 4b).
11. Confirm no network calls when all backends are local (privacy check).

## 10. Acceptance criteria

- Global hotkey starts/stops recording from any app.
- Polish speech produces the English text typed into the focused app via synthetic keystrokes.
- One tone control works (at least `formal` and `casual`).
- Fully offline with local backends; no external requests.
- Graceful fallback to the raw transcript when the transform model is unavailable.
- Cancelled dictation pastes nothing.
- No reasoning traces are pasted.
- Baseline English dictation still works.

## 11. Rollback

- The feature is isolated to a new service, one hook, preferences, and a settings
  section. Reverting the feature branch restores upstream behavior.
- Keep `main` clean so `git revert` or a branch reset is trivial.

## 12. Estimated effort (fork path)

| Phase | AI-hours | Tokens |
|---|---|---|
| 0 — environment + baseline build | 1.5-4 | 200-550k |
| 1 — backend decision/wiring | 0.5-1 | 50-150k |
| 2 — TranslationService | 1.5-3 | 200-450k |
| 3 — integration hook + ordering + cancellation | 1-2 | 150-300k |
| 4 — preferences + settings UI | 1-2.5 | 150-400k |
| 5 — tests | 0.5-1.5 | 100-250k |
| 6 — end-to-end debug | 1.5-3 | 200-500k |

Total: **~7.5-17 AI-hours, ~1.05-2.6 M tokens**.
Cost via `deepseek-flash`: typically **$0.10-0.55** (see study section 9b).

## 13. Risks and mitigations

- whisper.cpp CMake or Rust build failure: skip autocorrect; adjust CMake flags per
  `.github/workflows/build.yml`. Note `run.sh` builds Rust unconditionally.
- Qwen3 reasoning traces leaking into the paste: disable thinking in the request and
  strip ` thinking`/`reasoning_content` in the parser; covered by tests.
- Transform latency exceeds the 1-3 s target: switch to a smaller Qwen (8B/4B); timeout
  is configurable.
- Paste/state race: transform is awaited inside the decoding task and guarded by
  `decodingSessionID`; cancelled sessions paste nothing.
- Polish punctuation/casing from Whisper: the LLM pass normalizes it, and post-processing
  runs on the English result.
- History shows Polish while the paste is English: documented v1 behavior; a translated
  column is a later migration.
- MLX server not running: fallback path keeps dictation working.
- Memory: Qwen3-14B plus Whisper ~12 GB; avoid other heavy MLX jobs during use.
- Upstream drift: rebase on `upstream/main` periodically; keep changes localized.
- Licence: MIT base is safe; do not pull GPL code from FluidVoice.

## 14. Implementation status (2026-09-23)

Phases 2-5 are implemented, built, and unit-tested on branch `fm/fm-20260923-01` of the fork
`23n0n/OpenSuperWhisper`, in the isolated worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fm-fm-20260923-01`. Base `develop` at `c8e6fe7`;
feature HEAD `92fc012` (keypress round 4).

- Files: `OpenSuperWhisper/TranslationService.swift` (new),
  `OpenSuperWhisper/Utils/AppPreferences.swift`, `OpenSuperWhisper/Indicator/IndicatorWindow.swift`,
  `OpenSuperWhisper/Settings.swift`, `OpenSuperWhisperTests/TranslationServiceTests.swift` (new).
- Verified: `./run.sh build` exits 0 (`Building successful!`); all `TranslationServiceTests` pass.
  Three `crew-reviewer` rounds closed one critical defect (reasoning-strip tags corrupted by a
  markdown round-trip) and all major findings.
- Not yet done: Phase 6 end-to-end (needs the captain and the running MLX server).

Open questions for the captain:

1. A cancel issued while the transform is awaited deletes the already-saved recording (the cancel
   window widened from ~0 to the transform timeout). Keep as-is (cancel discards) or keep the
   recording and only skip the paste?
2. The default endpoint is loopback. A user-supplied non-loopback HTTP endpoint would be blocked by
   App Transport Security; v1 assumes loopback only.

Correction: the paste hook is in `IndicatorWindow.decodeRecording()`; `applyPostProcessing` lives on
`IndicatorViewModel`, not `IndicatorWindow:340` as an earlier draft stated.

Captain directive (2026-09-23): the output method is keypress simulation, not clipboard paste. A new
`OpenSuperWhisper/Utils/KeyboardSimulator.swift` posts `CGEvent` keystrokes carrying a Unicode string;
`IndicatorWindow.insertText(_:)` uses it and never touches `NSPasteboard`. Also a `run.sh` build fix
(`cp -f` for the read-only `libomp.dylib`). Verified: build green; `KeyboardSimulatorTests` (12)
and `TranslationServiceTests` pass. Feature HEAD `92fc012`.

Round-4 review hardening: synthetic events now clear modifier flags (a held hotkey cannot hijack
typing or turn Tab into Backtab); chunking walks UTF-16 code units so no chunk exceeds the cap and no
surrogate pair is split; the `autoCopyToClipboard` "keep in clipboard" toggle is honored (copy then
type); `run.sh` fail-fasts if the libomp copy fails.

## 15. Runtime backend and language policy (2026-09-23)

Landed on `feat/local-translate-tone` at `bd5ad0e` (fast-forward from `fm/fm-20260923-03`).

**Backend.** `bartowski/Qwen2.5-1.5B-Instruct-GGUF` Q4_K_M (986,048,768 bytes, sha256
`1adf0b11065d8ad2e8123ea110d1ec956dab4ab038eab665614adba04b6c3370`) served by `llama-server` 0.3.0
on `http://127.0.0.1:1919/v1/chat/completions` under the alias `qwen2.5-1.5b-instruct-q4_k_m`, with
`--ctx-size 4096` and full GPU offload. Weights live at
`$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf` (`TRANSFORM_MODEL_DIR` overrides). This is Phase 1
Option A with the Phase 4a preference for a smaller model, keeping tone; Option B and the 154 MB
opus-mt path are not used.

**Repo changes.** `Scripts/transform-server.sh` (serve / `--fetch` with checksum / `--check`, port and
weight guards), `Scripts/verify-transform.sh` (394-line contract harness that extracts the app's own
prompt, tone instructions and preference defaults from the Swift sources), the
`AppPreferences.transformModel` default repointed to the served alias, the matching Settings
placeholder, a Readme section, and a `run.sh` fix: the success gate now tests xcodebuild's own exit
status instead of the status of the log pretty-printer (it previously printed "Building successful!"
for a build that never ran).

**Evidence.** Contract verification: 132/132 checks, re-run independently after landing. Short
utterances 0.12-0.22 s idle / 0.89-2.04 s under ambient load; the 268-character paragraph 0.72-0.85 s
idle / 3.14-3.81 s under load, so the ~1-3 s target holds and the 8.0 s timeout stays. Tone separation
is reproducible (formal markers 3/3, casual 3/3, disjoint outputs). No response carried a reasoning
trace; `stripReasoning` was a no-op on all 13 sampled responses. Known quality limits of a 1.5B model:
"Prosze sprawdzic" doubles its politeness ("check ... please"), and "Zalezy mi na czasie" flattens to
"It's important to me" rather than "it's time-sensitive".

**`NoMicrophoneGuardTests` was never a flake — diagnosed and fixed (fm-20260923-22).**
`NoMicrophoneGuardTests.testIndicatorViewModel_startRecording_withNoMicrophone_showsNoMicrophoneState`
fails deterministically on this machine (4/4 runs, including in isolation), and it does not come from
this branch's changes: with every file this branch touched reverted in place to its `develop` content
(`IndicatorWindow.swift`, `AppPreferences.swift`, `Settings.swift`, `run.sh`), rebuilt and re-run, the
case still fails. (Running the whole `develop` tree in a fresh worktree was attempted but could not
link: the temporary worktree lacks the dylibs `run.sh` builds.)

Root cause, not a timing artefact: `IndicatorViewModel.startRecording()` asked `isTranscriptionBusy`
*before* its microphone guard (`OpenSuperWhisper/Indicator/IndicatorWindow.swift:141-144` ahead of the
guard at `:148-151`), and `TranscriptionService.init` starts a real whisper model load as soon as the
singleton is first touched — so in the app-hosted test bundle `isLoading` is true when the test runs and
`startRecording()` returns `.busy` without ever reading the microphone. Measured on the failing run:
`state=busy busy=true loading=true transcribing=false queue=false mic=nil recorder=false` (`mic=nil`
proves the test's injection does reach the app's `MicrophoneService.shared`; the guard was simply
unreachable). Fixed by checking the microphone first — a missing input device is a precondition, busy is
only work already in flight — while the busy guard still refuses when an input device exists
(`ShortcutManager.swift:156` calls `startRecording()` directly, so the fix is on the real hotkey path).


**Open, captain-directed (queued).** Two independent transform switches (translation and tone, each
user-toggleable) plus language awareness so English dictation is never sent to the Polish→English
transform. Design investigation: `firstmate-home/data/fm-20260923-04`; implementation queued as
`fm-20260923-05`. Phase 6 (on-device run-through) still requires the captain at the microphone.

**Captain constraint — one package (2026-09-23).** Captain, verbatim: "The whole app needs to ship in
one package. It cannot be a few different applications connected by a goodwill. It needs to be
idempotent. I need to be able to simply install it and uninstall it with a single package." The
transform backend may therefore not remain an external `llama-server` (Homebrew) plus a repo script
plus a process on a port plus a model in `~/models`. The runtime has to live inside the installed
package — vendored in-process llama.cpp mirroring the existing whisper integration, a bundled helper
process, or Swift-native MLX — and the weights must be either bundled or fetched by the app through
the model mechanism it already uses for whisper models. One install artifact, one uninstall action
that removes the app and all of its state, and idempotence in both directions. Architecture study:
`firstmate-home/data/fm-20260923-07`.

**Detector choice (2026-09-23).** whisper.cpp's own per-utterance language, read from the same
`whisper_full` call the dictation path already makes (free, in-process, `92.4%` correct in the 2-10 s
band across 111 real dictations — no new dependency). Desert Ant Labs' Ear was measured and rejected
for this purpose: `83.3%` in that band, only ≥10 s reaches 100%, 6 of 66 clips were confidently wrong,
and it adds a non-open-source licence with device-count telemetry. Evidence:
`firstmate-home/data/fm-20260923-06`.

## 16. Language awareness and the two switches (landed 2026-09-23)

Landed on `feat/local-translate-tone` at `faec335`. Behaviour now:

| Translation | Tone | Spoken language | Result |
|---|---|---|---|
| off | off | any | raw transcript, no detection, no HTTP |
| on | off | Polish | translated, no tone sentence in the prompt |
| on | off | English or other | raw transcript (English never reaches the Polish→English transform) |
| off | on | English | rewritten in the selected tone |
| off | on | Polish | raw (a tone-only prompt on Polish translates it anyway — measured 6/6) |
| on | on | Polish | translated and toned |
| on | on | English or other | tone rewrite, nothing translated |
| any | any | unknown | raw transcript |

The language comes from the engine's `fullLangId` on the same `whisper_full` call
(`params.detectLanguage` stays `false` — setting it true makes whisper.cpp return without
transcribing), a fixed `whisperLanguage` is authoritative, Parakeet reports nil, and a pure text
heuristic (diacritics + function words + bigrams) covers the rest. Unknown always passes through: the
study's "unified translate-or-passthrough call" was deliberately not implemented. `toneEnabled` is a
new preference, default `false`, with no migration. `transformIfEnabled` keeps its never-throws
contract and the recording store still receives the raw transcript before any transform.

Verified on the branch and after landing: `262` unit tests pass (including `LanguageDetectorTests`,
`TranscriptionLanguageGateTests`, `WhisperLanguageReportTests`), `Scripts/verify-transform.sh` at
`162` checks, build green through the fixed `run.sh` gate. One first-mate correction on top of the
crew's work: the translation switch no longer vetoes an English tone rewrite — the two switches are
independent, as specified to the captain.

**In flight (2026-09-23):** `fm-20260923-08`, the one-package shipping task (in-process llama.cpp on a
unified ggml, app-managed model download, one `.pkg` and one idempotent uninstall), per the captain's
single-package constraint.

## 17. Local build identity and permissions (landed 2026-09-23)

Landed on `feat/local-translate-tone` at `81d892b`. The captain's report — Accessibility granted in
System Settings while the app refused to pass its permission screen, and synthetic keystrokes
arriving once and then stopping — traced to the build, not the logic: `run.sh` builds with
`CODE_SIGNING_ALLOWED=NO`, so the bundle was only linker-signed and failed its own verification
(`code has no resources but signature indicates they must be present`), and its ad-hoc Designated
Requirement was a **cdhash**, which changes on every rebuild. macOS matches TCC grants against that
requirement, so each rebuild silently revoked Accessibility.

Now:

- `Scripts/dev-signing-identity.sh` creates (idempotently, no sudo) a self-signed
  `OpenSuperWhisper Local Dev` identity in its own keychain
  (`~/Library/Keychains/opensuperwhisper-dev.keychain-db`, leaf `32266BCC…E5A4`), with a documented
  one-line removal; it prefers a real `Developer ID Application` identity when one exists.
- `Scripts/dev-sign.sh <app>` signs the bundle with the project's entitlements and refuses to leave a
  cdhash-based requirement behind. The resulting requirement is
  `identifier "ru.starmel.OpenSuperWhisper" and certificate leaf = H"32266bcc…"` — proven byte-identical
  across rebuilds whose binaries genuinely differed.
- `Scripts/dev-run.sh` is the build-and-run path without the debug-dylib stub (`ENABLE_DEBUG_DYLIB=NO`),
  plus `--reset-tcc`; the Readme documents the one-time grant. Use it instead of bare `run.sh` for
  anything the captain is going to test.
