# Task fm-20260923-03 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

Captain (verbatim, this session): "Use 'first mate' and continue."

Standing captain directives that still apply:
- (2026-09-23) "Only acceptable output method is keypress simulation." — the injection path is done
  and merged; do not touch it.
- The plan's goal (voice-keyboard-fork-plan.md §1) requires a *toned* English result, so the
  transform must keep tone control.

Open decision this task resolves (plan §14 / scout fm-20260923-02 §8, captain's "continue" = go):
- Tone vs size → **keep tone** (plan §1). Smallest toned drop-in per scout: `Qwen2.5-1.5B-Instruct`
  GGUF Q4_K_M (~986 MB) served by `llama-server`, **zero app change** (prefs only).
- Integration shape → **zero app change**: the app already POSTs to an OpenAI-compatible
  `/v1/chat/completions`. Do not build the native `/translate` route or the CT2 wrapper.

Context: the feature branch `feat/local-translate-tone` (primary checkout at
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`, HEAD `92fc012`) now contains the landed
translation + tone service, the settings section, the keypress output, and their tests. What is
missing for the product to work is the local backend the app talks to, plus proof that the app's
exact request/response contract holds against it.

Scout evidence to read first (do not repeat its work, extend it):
- `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260923-02/report.md` §2, §5, §7, §8, §9.
- Prior task records: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260923-01/output-method.md`.

## Firstmate spec

Deliver a working local transform backend plus recorded evidence that the app's contract holds.

1. **Backend (local, offline, port 1919).**
   - Serve an OpenAI-compatible `/v1/chat/completions` on `http://127.0.0.1:1919` — the app's
     `transformEndpoint` default. Port 1919 is currently free.
   - Preferred runtime: `llama-server` (already installed: 0.3.0, build 10621) with
     `Qwen2.5-1.5B-Instruct` GGUF Q4_K_M (~986 MB). Acceptable alternatives if 1.5B fails the tone
     check with evidence: `gemma-3-1b-it` Q5_K_S/Q4_K_M (~836/806 MB), then `Qwen2.5-3B-Instruct`.
     Alternative runtime `mlx_lm.server` from `/Volumes/home/zenon/mlx/.venv` (mlx 0.32.2,
     mlx-lm 0.31.3) with an mlx-community 4-bit model is acceptable. Do **not** use any cloud
     provider; the product guarantee is fully local.
   - Total weights budget: 2.5 GB. Keep weights out of the repo (HF cache or
     `/Volumes/home/zenon/models/`). No sudo, no launchd job, no system-wide install.
   - Idempotent runner committed in the repo: `scripts/transform-server.sh` — starts the server on
     port 1919 with the model alias the app default uses, prints the ready URL, fails loudly when
     weights are missing (and fetches them only with an explicit flag). One short section in the
     existing `Readme.md` describing how to run it. Do not add new markdown files beyond that.

2. **App defaults in the worktree (minimal, no behavior change).**
   - `OpenSuperWhisper/Utils/AppPreferences.swift`: `transformModel` default becomes the model id
     the runner actually serves. Keep `transformEndpoint` default
     `http://127.0.0.1:1919/v1/chat/completions`, `transformToneMode` neutral, `transformTimeout`
     8.0 unless measured latency proves it wrong (then say why in the report).
     `OpenSuperWhisper/Settings.swift` placeholder strings (~lines 1082, 1090) must match the new
     defaults.
   - `run.sh`: the build-success gate is broken — `BUILD_OUTPUT=$(xcodebuild ...)` is followed by an
     `if command -v xcpretty ... fi` block and then `if [[ $? -eq 0 ]]`, so `$?` is the status of the
     pretty-printer, not of `xcodebuild`. It printed "Building successful!" today for a build that
     never ran (`xcode-select: error: tool 'xcodebuild' requires Xcode`). Capture xcodebuild's status
     immediately and gate on that; keep everything else in the script unchanged.
   - Do NOT change: `KeyboardSimulator.swift`, `IndicatorWindow.insertText(_:)` semantics, `ToneMode`
     cases/instructions, the reasoning-strip logic, the raw-transcript fallback behavior, or any
     cloud path.

3. **Contract verification, headless, with evidence (this is the core deliverable).**
   - Drive the server with the app's **exact** request body — same JSON shape as
     `TranslationService.buildRequestBody(text:tone:model:)`: system prompt from
     `TranslationService.systemPrompt(for:)` (includes the tone instruction and `/no_think`), user
     message = the Polish text, `temperature` 0.2, `stream` false,
     `chat_template_kwargs.enable_thinking` false — and parse the response with the same expectation
     as `TranslationService.parseContent(from:)` (choices[0].message.content, reasoning stripped).
   - Run at least 6 Polish sentences, including the scout's four samples from report §4, and record
     the actual outputs verbatim.
   - Tone check: the same Polish sentence under `formal` and `casual` must produce measurably
     different register; paste the outputs as evidence. If the chosen model cannot separate the two,
     say so plainly and move to the next candidate rather than dressing it up.
   - Assert no reasoning traces appear in any output (think/thinking/reasoning tags, the Qwen3
     end-of-thinking token, or a `reasoning_content` payload).
   - Record per-request wall-clock latency and state whether the plan's ~1–3 s short-utterance target
     is met.
   - Commit the verification as a runnable script (`scripts/verify-transform.sh`) that exits non-zero
     on any failed assertion, and paste its output into your final report.

4. **Verification of the repo itself.**
   - `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./run.sh build` must print
     "Building successful!" because xcodebuild really succeeded — also confirm the fixed gate now
     fails when xcodebuild fails (e.g. run it once with `DEVELOPER_DIR` pointed at
     `/Library/Developer/CommandLineTools` and show it reports failure). Non-interactive shells here
     default to the CommandLineTools developer dir, so set `DEVELOPER_DIR` explicitly.
   - `xcodebuild test -scheme OpenSuperWhisper -destination 'platform=macOS,arch=arm64'
     -only-testing:OpenSuperWhisperTests` must pass; report the executed test count.
   - Commit in small units with conventional messages (`feat(transform):`, `fix(build):`, `test:`,
     `docs:`).

## Worktree isolation assertion

Work in the worktree at `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-03` ONLY,
branch `fm/fm-20260923-03` (created from `feat/local-translate-tone` @ `92fc012`). This path is NOT
the primary checkout. Never touch `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`.

## Delegation guard

You are a crew member. Do not spawn subagents. If you need more depth, say so in your final report.

## Definition of done

- `fm/fm-20260923-03` holds a clean, committed, ready-to-merge branch; no push, no PR.
- `scripts/transform-server.sh` starts the local backend on port 1919 and
  `scripts/verify-transform.sh` passes against it, with the real outputs and latencies pasted in
  your final report.
- App defaults point at the served model; `Readme.md` has the short "run the local transform
  backend" section.
- Build succeeds *and* the fixed `run.sh` gate demonstrates it can report failure;
  `OpenSuperWhisperTests` pass.
- Report: outcome, files changed, exact commands run, model chosen and why, latency numbers, tone
  evidence, reasoning-trace check, and any honest failure. Never claim success you did not verify.
