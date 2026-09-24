# Task fm-20260923-01 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

"proceed with creation of the tool. So, use all proper skills, use caveman, use crew, and begin
the creation of this fork."

Context: this is a fork of `Starmel/OpenSuperWhisper` (MIT) that must become a local dictation app
which transcribes Polish speech, translates Polish → English locally, applies a local tone
adjustment, and pastes the result into the focused app with the existing Cmd+V mechanism.
Phase 0 (fork, clone, toolchain, baseline build) is already done and green. This task implements
the feature (plan Phases 2–5). The authoritative plan is at
`/Volumes/home/zenon/Documents/deepseek_general/voice-keyboard-fork-plan.md` — read it first.
End-to-end validation (plan Phase 6) needs the captain and the MLX server; it is NOT part of this
task's definition of done.

## Worktree isolation assertion

Work in the worktree at
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-01` ONLY.
This path is NOT the primary checkout. Never touch
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`.
You are on branch `fm/fm-20260923-01`, based on `develop`.

## Delegation guard

You are a crew member. Do not spawn subagents. If you need more depth, say so in your final report.

## Environment (already installed, verified)

Xcode 27.0 at `/Applications/Xcode.app` (license accepted, `xcode-select` points at it).
CMake 4.4.3, Rust/Cargo 1.98.1, xcpretty 0.4.1 all installed. Submodules are already initialized in
this worktree (`libwhisper/whisper.cpp` v1.9.3, `asian-autocorrect`).

Every build/test shell needs:

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="/Volumes/home/zenon/.gem/ruby/2.6.0/bin:$PATH"
```

Baseline build command (redirect to a log; the log is large — never dump it whole):

```
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-01
./run.sh build > /tmp/osw-wt-build.log 2>&1; echo "EXIT=$?"; tail -40 /tmp/osw-wt-build.log
```

`run.sh` prints a few harmless `error: the following command failed with exit code 0 but produced no
further output` lines from xcpretty; success is `Building successful!` and EXIT=0.

Run the new unit tests with:

```
xcodebuild test -scheme OpenSuperWhisper -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  -clonedSourcePackagesDirPath SourcePackages \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:OpenSuperWhisperTests/TranslationServiceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

Project uses Xcode **file-system-synchronized groups** (`objectVersion = 77`), so a new `.swift`
file dropped into `OpenSuperWhisper/` or `OpenSuperWhisperTests/` is picked up automatically. Do
NOT edit `project.pbxproj`.

## Firstmate spec

Implement exactly these five changes. Keep scope tight; no refactors, no drive-by edits, no new
dependencies.

### 1. New file `OpenSuperWhisper/TranslationService.swift` (~150–250 LOC)

- `enum ToneMode: String, CaseIterable, Identifiable` with cases `neutral`, `formal`, `casual`;
  `displayName` and a one-line tone `instruction` each.
- `TranslationService` with `static let shared`.
- `func transformIfEnabled(_ text: String) async -> String` — the only entry point the UI uses:
  - if `AppPreferences.shared.translateEnabled` is false, or `text` is empty → return `text`
    unchanged;
  - otherwise call `transform`, and on ANY thrown error return `text` unchanged
    (global fallback contract: the app must always paste something).
- `func transform(_ text: String) async throws -> String` — performs the HTTP call:
  - endpoint from `AppPreferences.shared.transformEndpoint`
    (default `http://127.0.0.1:1919/v1/chat/completions`), model from `transformModel`
    (default `Qwen/Qwen3-14B-MLX-6bit`), timeout from `transformTimeout` (default 8 s).
  - `POST` OpenAI-compatible chat completions. Body: `model`, `messages`
    (system + user), `temperature` 0.2, `stream: false`.
  - System prompt: translate the Polish input into natural English, then rewrite it in the selected
    tone; output ONLY the final English text, no quotes/labels/explanation. Append `/no_think`
    (Qwen3 soft switch) and include `"chat_template_kwargs": {"enable_thinking": false}` in the
    body so Qwen3 does not emit reasoning.
  - Use `URLSession` with the configured timeout. The call must observe task cancellation: either
    use the async `URLSession.data(for:)` API (which cancels on task cancellation) or check
    `Task.isCancelled` before and after.
  - Parse `choices[0].message.content`; also read `reasoning_content` if present.
  - **Strip any ` thinking…<｜end▁of▁thinking｜>` block** (and any other `<…>` reasoning markers) from
    the content before use. If the stripped result is empty (including the case where only
    `reasoning_content` came back), throw so the caller falls back to the raw transcript.
  - Trim whitespace; reject an empty final string.
- Make the pure parts testable without network:
  - `static func buildRequestBody(text:tone:model:) throws -> Data`
  - `static func parseContent(from data: Data) throws -> String` (decodes + strips reasoning;
    throws on malformed/empty).
- Use `Codable` request/response structs.

### 2. Edit `OpenSuperWhisper/Utils/AppPreferences.swift`

Add these alongside the existing clipboard prefs (the file already defines `@UserDefault` and
`autoPasteTranscription`):

```swift
// Translation / tone settings
@UserDefault(key: "translateEnabled", defaultValue: false)
var translateEnabled: Bool

@UserDefault(key: "transformToneMode", defaultValue: ToneMode.neutral.rawValue)
private var transformToneModeRaw: String

var transformToneMode: ToneMode {
    get { ToneMode(rawValue: transformToneModeRaw) ?? .neutral }
    set { transformToneModeRaw = newValue.rawValue }
}

@UserDefault(key: "transformEndpoint", defaultValue: "http://127.0.0.1:1919/v1/chat/completions")
var transformEndpoint: String

@UserDefault(key: "transformModel", defaultValue: "Qwen/Qwen3-14B-MLX-6bit")
var transformModel: String

@UserDefault(key: "transformTimeout", defaultValue: 8.0)
var transformTimeout: Double
```

The `@UserDefault` wrapper stores raw values via `UserDefaults`, so the enum must be stored as its
`String` raw value (as above). Do not store the enum directly.

### 3. Edit `OpenSuperWhisper/Indicator/IndicatorWindow.swift` — hook ordering + cancellation

`insertText(_:)` is at line ~319 and is called from inside the decoding `Task` in
`decodeRecording()` at line ~280, immediately before `finishDecoding(sessionID:)`.

At that call site, replace the direct `insertText(text)` with an awaited transform that preserves
the existing session/cancellation semantics:

```swift
try Task.checkCancellation()
guard self.decodingSessionID == sessionID else { throw CancellationError() }
let finalText = await TranslationService.shared.transformIfEnabled(text)
try Task.checkCancellation()
guard self.decodingSessionID == sessionID else { throw CancellationError() }
insertText(finalText)
```

This is inside the existing `do { … } catch is CancellationError { … }` block, so the throws are
handled by the existing cancel path. Do NOT fire-and-forget. The transform MUST be awaited so the
paste cannot race `finishDecoding(sessionID:)` or the cancel path.

Keep `insertText(_:)` synchronous and unchanged: it still calls `applyPostProcessing` on its input,
so the order is translate-first, then post-process — the trailing space lands on the English
result, not the Polish transcript.

Do NOT change `ClipboardUtil`: the 1.5 s restore timer starts at the paste call, which now happens
after the transform, so there is no collision.

### 4. Edit `OpenSuperWhisper/Settings.swift` — one new section

`Settings.swift` is 1860 LOC. Add ONE section for the settings above, matching the existing section
style/patterns already in the file (find the clipboard/transcription settings area and follow its
`VStack`/`Toggle`/`Picker`/`TextField` markup). Include:

- Toggle for `translateEnabled` ("Translate Polish to English").
- `Picker` for `transformToneMode` over `ToneMode.allCases` (neutral / formal / casual).
- Text fields for `transformEndpoint` and `transformModel`, and a numeric field for
  `transformTimeout`.
- A short caption noting that dictation history keeps the raw (Polish) transcript while the pasted
  text is the translated/tone-adjusted English.

Do not restructure existing sections.

### 5. New tests `OpenSuperWhisperTests/TranslationServiceTests.swift`

Follow the existing test style in that directory (XCTest). Cover:

- `buildRequestBody` prompt/body for each of the three tone modes (include the tone instruction).
- `parseContent`:
  - normal `content`;
  - content containing a ` thinking…<｜end▁of▁thinking｜>` block → block stripped;
  - `reasoning_content` present with empty `content` → throws (fallback);
  - malformed JSON → throws;
  - empty response → throws.
- Fallback: `transformIfEnabled` returns the raw input unchanged when `translateEnabled` is false;
  and (without a live server) returns the raw input unchanged on request failure for a bad endpoint.
- `ToneMode` raw-value round-trip (`ToneMode(rawValue: ToneMode.formal.rawValue) == .formal`).

## Definition of done (mode=local-only)

- The five changes above are committed on branch `fm/fm-20260923-01` in small conventional commits.
- `./run.sh build` exits 0 (`Building successful!`) in the worktree.
- `TranslationServiceTests` pass via the `xcodebuild test` command above.
- No files outside the five listed are modified. `git status` clean after commit.
- E2E/mic permission checks are explicitly NOT required (captain does Phase 6 later).
- Report honestly: outcome, files changed, exact commands run and their decisive output lines,
  branch/commit state, or the precise failure if blocked.

## Closing

You are a crew member of the first mate. Work only in the given worktree. Do not spawn subagents.
Report through your final message: outcome, files changed, tests run, branch state, or honest
failure. Never claim success you did not verify.
