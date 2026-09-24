# Remediation round 4 — fm-20260923-01 — keypress output hardening

Review of the keypress change found real defects. Fix the following on the same worktree and branch.
Touch only the four files named.

Worktree: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260923-01`
Branch: `fm/fm-20260923-01`, current HEAD `59dc79e`.

## S1 (blocking) — clear event flags so held modifiers cannot hijack typing

File: `OpenSuperWhisper/Utils/KeyboardSimulator.swift`.

Events created from `.combinedSessionState` can inherit the modifier state of a still-held hotkey,
so a chunk could fire a shortcut (e.g. Command+A) instead of inserting text, and Return/Tab could
become modified keys. On EVERY event built in `makeUnicodeEvents(for:)` and `makeKeyEvents(for:)`,
set `flags = []` explicitly (e.g. `keyDown.flags = []; keyUp.flags = []`). This replaces the
inherited-state behavior with plain typing.

## S2 (blocking) — preserve the "keep in clipboard" toggle

File: `OpenSuperWhisper/Indicator/IndicatorWindow.swift`, `insertText(_:)`.

The earlier version honored `autoCopyToClipboard` while pasting (`insertTextAndKeepInClipboard`).
The keypress change silently dropped it. Restore it: when `autoPasteTranscription` is on and
`autoCopyToClipboard` is also on, copy the final text to the clipboard FIRST, then type it. When
`autoPasteTranscription` is on and `autoCopyToClipboard` is off, only type (clipboard untouched).
The `autoCopyToClipboard`-only branch is unchanged.

```
if prefs.autoPasteTranscription {
    if prefs.autoCopyToClipboard { ClipboardUtil.copyToClipboard(finalText) }
    KeyboardSimulator.typeText(finalText)
} else if prefs.autoCopyToClipboard {
    ClipboardUtil.copyToClipboard(finalText)
}
```

## S3 (blocking) — never emit a chunk above the cap

File: `OpenSuperWhisper/Utils/KeyboardSimulator.swift`, `chunks(of:maxUTF16:)`.

Round 3 split on `Character` boundaries, so a single grapheme longer than `maxUTF16` UTF-16 units
(a family/skin-tone ZWJ emoji) produced an over-cap chunk that `keyboardSetUnicodeString` truncates,
losing text. Change the chunker to walk **UTF-16 code units** and pack up to `maxUTF16` units per
chunk, never splitting a surrogate pair (keep a high surrogate with its following low surrogate).
Every returned chunk must satisfy `chunk.utf16.count <= maxUTF16`. Do not drop any code unit; a
long grapheme may be split across chunks (acceptable — truncation is not). If `maxUTF16 <= 0`,
return `[]` rather than `[text]`.

Update `KeyboardSimulatorTests`: assert every chunk is `<= maxUTF16`; add a case with a single
grapheme longer than 20 UTF-16 units (e.g. a multi-person ZWJ sequence or many combining marks) and
assert the concatenated UTF-16 of all chunks equals the input's UTF-16 and no chunk exceeds the cap.
Replace the tautological surrogate assertion with a check that each chunk's UTF-16 decodes cleanly.

## S4 (small) — check the libomp copy in run.sh

File: `run.sh`.

The `cp -f /opt/homebrew/opt/libomp/lib/libomp.dylib ./build/libomp.dylib` line ignores failure, so a
failed copy leaves a stale/missing dylib while the script continues to install_name_tool/codesign.
Check it, e.g. `|| { echo "libomp copy failed"; exit 1; }`.

## S5 (small) — surface the untrusted-input case

File: `OpenSuperWhisper/Utils/KeyboardSimulator.swift`.

When the process is not trusted for Accessibility, posting events is a silent no-op and the
transcription is lost. At the start of `typeText`, if `AXIsProcessTrusted()` is false, log a clear
warning (the codebase uses `print`). Still attempt to post. Do not add a clipboard fallback.

## Accepted (no change)

- `virtualKey 0` on Unicode events: apps that read the keycode instead of the unicode string may see
  'a'; this is the standard approach and is accepted.
- No inter-event pacing: noted; not required for v1.

## Definition of done

- `./run.sh build` exits 0 (`Building successful!`).
- `KeyboardSimulatorTests` and `TranslationServiceTests` pass.
- Only these files changed since `59dc79e`: `OpenSuperWhisper/Utils/KeyboardSimulator.swift`,
  `OpenSuperWhisper/Indicator/IndicatorWindow.swift`,
  `OpenSuperWhisperTests/KeyboardSimulatorTests.swift`, `run.sh`.
- Committed on `fm/fm-20260923-01`; `git status` clean.

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
