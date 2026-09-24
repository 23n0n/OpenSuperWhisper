# Local Voice Keyboard for macOS — Feasibility & Implementation Study

Status: study only. No code written.
Target machine: Mac mini M4, 10-core, 32 GB RAM, data on 1 TB `/Volumes/home`.
Assumed present (per user; sandbox cannot see `/Applications`): Xcode.

## 1. Goal

A minimal macOS dictation app that:

- Triggers from a global keyboard shortcut (press / hold-to-talk).
- Records the microphone.
- Transcribes speech **locally** (Whisper-class model).
- Optionally translates **Polish → English** on the fly, locally.
- Optionally adjusts tone, locally.
- Types/pastes the result into the focused app.

Everything stays on-device. No cloud, no per-use cost.

## 2. Feasibility verdict

Feasible. Low risk. The machine already runs every component needed:

- `whisper.cpp 1.9.2` installed at `/opt/homebrew` — `whisper-cli`, `whisper-server`,
  `whisper-stream`, `parakeet-cli`. Built-in `--translate` flag (any language → English).
- `llama.cpp` installed (`llama-server`).
- MLX virtualenv with `Qwen/Qwen3-14B-MLX-6bit` configured (launchd `com.dsh.mlx-qwen`,
  port 1919). Server currently stopped; must be running for low-latency transform.
- `python3.14`, `ffmpeg`, `node`, `brew`. `libomp` installed.
- Whisper weights not yet downloaded (only a tiny test blob). Need ~1.5 GB pull.

## 3. Recommended base: fork OpenSuperWhisper

`Starmel/OpenSuperWhisper` — MIT, Swift/AppKit, native, ~12,100 LOC, 2.9k stars.

Why this base:

- Already solves the hard parts: global hotkey, mic capture, whisper.cpp integration,
  model download, tray indicator, clipboard paste, settings UI.
- MIT licence — safe for closed or open derivative.
- Clean insertion hook, so translation/tone is a small local change.
- Alternatives considered:
  - `moona3k/macparakeet` (Swift) — has "Transforms" + automation CLI, but licence is
    NOASSERTION; verify before use.
  - `altic-dev/FluidVoice` (Swift, 11.7k) — has an AI-enhancement model, but **GPL-3.0**
    (viral; avoid if derivative may be closed).
  - `OpenWhispr/openwhispr` (MIT, JS/Electron) — cross-platform but heavy (112 MB repo).
  - `amicalhq/amical` (MIT, TypeScript) — local-first, not native.
  - `tover0314-w/opentypeless` (MIT, Rust) — cross-platform, smaller Swift fit.

## 4. How the base works today (input method)

**Text injection = synthetic Cmd+V, not per-character typing.**

- `OpenSuperWhisper/Utils/ClipboardUtil.swift`
  - `insertText(_:)` writes the text to `NSPasteboard.general`.
  - `sendCmdV` builds a `CGEvent` keyboard event: `virtualKey = 9` (V), flags
    `.maskCommand`, posts to `.cghidEventTap`.
  - Layout-aware keycode resolution (Dvorak etc.); fallback keycode 9.
  - Saves the previous clipboard and restores it after 1.5 s, only if the pasteboard
    is unchanged.
- Call site: `OpenSuperWhisper/Indicator/IndicatorWindow.swift:319` `insertText(_:)`,
  after `applyPostProcessing` (adds a trailing space). Preferences:
  `autoPasteTranscription` (default true), `autoCopyToClipboard`.
- Requires **Accessibility permission**; fails under secure input fields.

**Trigger / hotkey** (`OpenSuperWhisper/ShortcutManager.swift`):

- `sindresorhus/KeyboardShortcuts` library. Default `Option+`` (configurable).
- Modifier-only hold (`ModifierKeyMonitor.swift`) and mouse button
  (`MouseButtonMonitor.swift`) use raw `CGEvent.tapCreate` — need Accessibility +
  Input Monitoring.
- `Utils/FocusUtils.swift` uses `AXUIElement` only to read the focused element / caret
  rect for indicator placement — not for insertion.

**STT engine:** `libwhisper` (whisper.cpp submodule) via `Bridge.h`; Swift wrapper in
`Whis/Whis.swift`. `FluidAudio` dependency present (Parakeet support path).
**Dependencies:** `KeyboardShortcuts`, `GRDB`, `FluidAudio` (SwiftPM).

## 5. Changes needed for this project

Minimal surface — one new service, one hook, settings.

1. **New `TranslationService.swift`** (~150-250 LOC)
   - `URLSession` POST to local OpenAI-compatible endpoint
     (`http://127.0.0.1:1919/v1/chat/completions`, MLX Qwen).
   - Prompt: translate Polish → English, then apply tone (`formal` / `casual` /
     `neutral`, etc.).
   - Timeout + fallback: on error/empty, return raw transcript unchanged.
2. **Hook in `IndicatorWindow.insertText` (`:319`) / `applyPostProcessing`**
   - Run transcript through `TranslationService` asynchronously before
     `ClipboardUtil` paste. ~30-60 LOC.
3. **`AppPreferences` + `Settings.swift` UI**
   - Toggles: translate on/off, tone mode, endpoint URL, model name.
   - `Settings.swift` is 1,860 LOC — add a section, not a rewrite.
4. **Optional hotkey tone modes** — separate shortcuts per tone.
5. **Tests** — prompt building, response parsing, fallback path.

Alternative to step 1 for translation only: set whisper.cpp `translate` flag in
`WhisperFullParams` (one-pass pl→en, cheaper, lower quality). Tone still needs the LLM.

## 6. Models

| Role | Model | Size | Notes |
|---|---|---|---|
| STT default | whisper `large-v3-turbo` (ggml) | ~1.6 GB | Decent Polish; fast on M4 |
| STT alt | parakeet-tdt-0.6b-v3 | ~600 MB | 25 European langs incl. Polish; faster |
| Translate + tone | Qwen3-14B (already configured) | ~11 GB | One prompt does both |
| Translate + tone (lighter) | Qwen3-8B / 4B | 5-8 GB | Lower latency |
| Translation fallback | Opus-MT pl-en | ~300 MB | Fast, no tone control |

Whisper `--translate` = one-pass pl→en, no extra model, lower quality.
Recommended: two-pass (transcribe Polish → Qwen translate + tone).

## 7. Pipeline and latency

```
hotkey (KeyboardShortcuts / CGEvent tap)
  -> AVAudioEngine record -> 16 kHz mono WAV
  -> whisper-server (large-v3-turbo)          [STT]
  -> POST 127.0.0.1:1919/v1/chat/completions  [Qwen: pl->en + tone]
  -> ClipboardUtil.insertText -> Cmd+V CGEvent
```

Estimated added latency for a short utterance: STT ~0.3-1 s + Qwen ~0.5-2 s =
**~1-3 s total**. Acceptable.

## 8. Build steps (Xcode present)

```
git clone https://github.com/Starmel/OpenSuperWhisper.git
cd OpenSuperWhisper
git submodule update --init --recursive        # whisper.cpp, autocorrect
brew install cmake libomp rust ruby
gem install xcpretty
./run.sh build                                  # cmake libwhisper; cargo autocorrect; xcodebuild
```

First build compiles whisper.cpp + a Rust dylib + the Swift app. Expect one or two
toolchain fixes.

## 9. Effort and cost estimate (fork path)

Setup:

| Step | AI-hours | Tokens |
|---|---|---|
| Install `cmake`/`rust`/`xcpretty`, init submodules | 0.5-1 | 50-150k |
| First green build (cmake + cargo + xcodebuild) | 1-3 | 150-400k |

Feature:

| Step | AI-hours | Tokens |
|---|---|---|
| `TranslationService.swift` | 1.5-3 | 200-450k |
| Hook in `IndicatorWindow.insertText` | 0.5-1.5 | 100-250k |
| `AppPreferences` + Settings UI | 1-2.5 | 150-400k |
| End-to-end debug (permissions, latency, clipboard timing) | 1.5-3 | 200-500k |
| Basic tests | 0.5-1.5 | 100-250k |

**Total: ~6-14 AI-hours, ~1-2.5 M tokens** (budget 16 h / 3 M).
Money: **$0** if driven by a local model; ~$15-50 if driven by a paid API.
Runtime: **$0** marginal; electricity only.

### 9b. Cost in DeepSeek V4.1 Flash tokens

Model `deepseek-flash` (DeepSeek-V4.1-Flash). Rates per 1M tokens, from DeepSeek API
docs and this machine's `~/.pi/agent/models-store.json` (which uses peak rates):

| | cache hit | cache miss (input) | output |
|---|---|---|---|
| Peak | $0.006 | $0.30 | $1.20 |
| Off-peak | $0.003 | $0.15 | $0.60 |

Peak hours: 01:00-04:00 and 06:00-10:00 UTC, Mon-Fri (excl. Chinese holidays).
All other hours, weekends and CN holidays are off-peak. Off-peak is half of peak.

Assumptions: agentic Swift work, input ~90% of tokens, output ~10%; among input
~80% cache hit (repo and build logs are re-sent and cached).

Fork build:

| Total tokens | Peak | Off-peak |
|---|---|---|
| 1.0M | ~$0.18 | ~$0.09 |
| 1.75M (mid) | ~$0.31 | ~$0.16 |
| 2.5M | ~$0.45 | ~$0.22 |
| 3.0M (budget) | ~$0.53 | ~$0.27 |

Pessimistic upper bound (no cache, output 15%): ~$0.44 per 1M total, so 3M tokens
~= **$1.30**. The whole fork stays under ~$1.50 worst case.

App runtime, if translate+tone is routed to `deepseek-flash` instead of local Qwen:

- ~190 input + ~40 output tokens per dictation.
- Peak ~= **$0.0001 per dictation**, ~$0.10 per 1,000, ~$1 per 10,000.
- Off-peak ~= half. Local Qwen route = **$0**.

Conclusion: building the fork costs cents (budget under $1.50). The running app costs
$0 with local models, or about a cent per hundred dictations via the API.

## 10. Risks

- Whisper Polish punctuation/casing weaker than English; the LLM pass fixes most.
- whisper.cpp CMake or Rust autocorrect build fails: +2-5 h. Can drop autocorrect
  (skip the Rust step) if it blocks.
- Clipboard restore uses a fixed 1.5 s delay — translation adds latency, may need
  to paste after transform completes rather than on a timer.
- Both models loaded together ~12 GB — fits 32 GB; do not run heavy MLX jobs at once.
- Accessibility + Microphone + Input Monitoring permissions required; unsigned local
  build adds extra permission clicks.
- MLX server must be running (currently stopped); use launchd keep-alive.
- Licence: MIT base is safe; avoid GPL FluidVoice for a closed derivative.

## 11. Cheaper alternative

Skip the fork. Write a minimal SwiftPM menu-bar app reusing the same Cmd+V `CGEvent`
technique, calling `whisper-cli` and the MLX Qwen endpoint. Avoids large repo and
submodules, but re-implements hotkey, indicator, settings, model handling:
~10-20 h, ~3-6 M tokens. Fork wins on hours.

## 12. Minimal "done" definition

- Global hotkey starts/stops recording from anywhere.
- Polish speech → English text pasted into the focused app.
- One tone control (e.g. formal / casual).
- Works offline; no network calls.
- Graceful fallback to raw transcript if the transform model is unavailable.
