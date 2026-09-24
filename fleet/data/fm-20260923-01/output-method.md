# Captain-directed change — fm-20260923-01 — output method = keypress simulation

Captain directive (verbatim): "Only acceptable output method is keypress simulation."

This supersedes the plan's paste-based injection. The app must deliver text to the focused app by
simulating keystrokes (`CGEvent` that carry a Unicode string), NOT by writing to `NSPasteboard` and
synthesizing Cmd+V. The clipboard must never be touched on the injection path.

Context: an earlier draft study contrasted "synthetic Cmd+V" with "per-character typing". The captain
requires per-character/keystroke simulation. Work on the existing worktree and branch.

Worktree: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-01`
Branch: `fm/fm-20260923-01` (current HEAD `e428306`). Continue on this branch; add commits.

## What "keypress simulation" means here

- Build `CGEvent`s of type keyDown/keyUp with
  `CGEvent(keyboardEventSource:virtualKey:keyDown:)`, then set the characters with
  `event.keyboardSetUnicodeString(stringLength:unicodeString:)`, then post them. Posting keeps the
  existing tap: `.cghidEventTap`.
- This carries arbitrary Unicode (Polish diacritics included) and is layout-independent, unlike
  keycode mapping. Do not attempt per-character keycode lookup for output.
- Do not use `NSPasteboard` anywhere in the injection path.

## K1 — new `OpenSuperWhisper/Utils/KeyboardSimulator.swift`

- `enum KeyboardSimulator` (no instance state).
- `static func typeText(_ text: String, post: (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) })`:
  - Splits the text into chunks of at most 20 UTF-16 code units so a single event never exceeds a
    safe `keyboardSetUnicodeString` length. Never split a surrogate pair across chunks.
  - For each chunk: create a keyDown event (virtualKey 0), set the chunk's UTF-16 string on it,
    create a matching keyUp event with the same unicode string, and send both via `post` (keyDown
    then keyUp).
  - Handle control characters explicitly instead of embedding them in a Unicode chunk:
    `\n` → Return keycode `0x24`, `\t` → Tab keycode `0x30` (keyDown/keyUp, no unicode string).
    Any other newline form (`\r\n`, `\r`) maps to a single Return.
  - Empty text → post nothing.
  - Guard: if `CGEvent` creation fails for a chunk, skip that chunk and continue (never crash).
- Expose pure helpers for tests:
  - `static func chunks(of text: String, maxUTF16: Int = 20) -> [String]` (surrogate-pair safe).
  - A way to assert what was posted; simplest is that `typeText` takes the `post` closure, so tests
    capture events. Also expose `static func makeUnicodeEvents(for chunk: String) -> [CGEvent]` or
    equivalent if useful.
- This file is auto-included by the Xcode synchronized group; do NOT edit `project.pbxproj`.

## K2 — `OpenSuperWhisper/Indicator/IndicatorWindow.swift`

`insertText(_:)` currently (around lines 322-340):

```
if prefs.autoPasteTranscription {
    if prefs.autoCopyToClipboard { ClipboardUtil.insertTextAndKeepInClipboard(finalText) }
    else { ClipboardUtil.insertText(finalText) }
} else if prefs.autoCopyToClipboard {
    ClipboardUtil.copyToClipboard(finalText)
}
```

Change the injection branch to type the text with `KeyboardSimulator.typeText(finalText)`. The
`autoCopyToClipboard`-only branch (no auto-paste) may keep using `ClipboardUtil.copyToClipboard`,
since that is an explicit copy action, not an output method. Result:

```
if prefs.autoPasteTranscription {
    KeyboardSimulator.typeText(finalText)
} else if prefs.autoCopyToClipboard {
    ClipboardUtil.copyToClipboard(finalText)
}
```

Do not change the transform/await/cancellation logic from the earlier rounds; `insertText(finalText)`
is still called the same way. Leave `ClipboardUtil` itself in place (other code/menus use
`copyToClipboard`); just stop calling its paste functions from this path.

## K3 — tests `OpenSuperWhisperTests/KeyboardSimulatorTests.swift` (new)

- `chunks(of:)` splits long ASCII text into ≤20 UTF-16-unit chunks that reconstitute the original in
  order, and does not split a surrogate pair (use an emoji plus diacritics).
- A short string posts the expected number of events in order: for each chunk, one keyDown then one
  keyUp; assert the keyDown carries the chunk via `keyboardGetUnicodeString` (read it back).
- Newline posts Return keycode `0x24` (keyDown+keyUp) and Tab posts `0x30`.
- Empty string posts nothing.
- No `NSPasteboard` interaction: assert `NSPasteboard.general.changeCount` is unchanged across a
  `typeText` call.
- Follow the existing XCTest style in `OpenSuperWhisperTests/`.

## Definition of done

- `./run.sh build` exits 0 (`Building successful!`).
- `KeyboardSimulatorTests` pass and the existing `TranslationServiceTests` still pass.
- Only these files changed since `e428306`: `OpenSuperWhisper/Utils/KeyboardSimulator.swift` (new),
  `OpenSuperWhisper/Indicator/IndicatorWindow.swift`, `OpenSuperWhisperTests/KeyboardSimulatorTests.swift`
  (new).
- Committed on `fm/fm-20260923-01` with conventional messages; `git status` clean.

Build/test env:

```
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="/Volumes/home/zenon/.gem/ruby/2.6.0/bin:$PATH"
```

```
xcodebuild test -scheme OpenSuperWhisper -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
  -clonedSourcePackagesDirPath SourcePackages \
  -skipPackagePluginValidation -skipMacroValidation \
  -only-testing:OpenSuperWhisperTests/KeyboardSimulatorTests \
  -only-testing:OpenSuperWhisperTests/TranslationServiceTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO
```

Report the new HEAD sha and decisive output. Never claim success you did not verify.
