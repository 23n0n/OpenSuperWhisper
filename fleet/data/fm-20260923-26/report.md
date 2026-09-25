# fm-20260923-26 — the delivery path now runs on this machine, layout or no layout

## Outcome

The suite's layout-gated families no longer go silent on a normal machine. Three cases were added, one
per family, and each of them resolves the input source that is *active* at run time instead of naming
one, so the delivery contract — the text actually reaching the focused application — is exercised here
instead of skipping.

No existing case was deleted, weakened or re-pinned. No product code was touched: the only product file
ever modified during this task was temporarily mutated on purpose to prove the new case bites, and that
mutation was reverted before committing (`git status` shows two test files, nothing else).

## Files changed

| file | +/- | change |
|---|---|---|
| `OpenSuperWhisperTests/KeyboardSimulatorTests.swift` | +148 | `TypingReceiverView` (the smallest receiver that can host real key events) and the new class `KeyboardSimulatorDeliveryTests.testTypesTheExactTextThroughTheActiveInputSource()` |
| `OpenSuperWhisperTests/OpenSuperWhisperTests.swift` | +74/-4 | `ClipboardUtilPasteIntegrationTests.testPasteWithActiveInputSource()`, `KeyboardLayoutProviderTests.testResolveInfo_ActiveLayout_returnsInfo()`, the shared paste body split out of the layout-named helper, and class comments cross-referencing the cases that always run |

Commit: `62eb921` on `fm/fm-20260923-26`, base `c6f9546`.

## What the skipped cases prove, and what each skip cost

The 54 skips of a full run are three environmental accidents, not 54 different conditions:

| class | cases | skipped | reason | what a skip cost |
|---|---|---|---|---|
| `ClipboardUtilPasteIntegrationTests` | 38 | 36 | `XCTSkip("<id> layout not available")` | `ClipboardUtil.sendCmdV` resolves the key code for ⌘V per layout: QWERTY-command layouts hard-code key code 9, Dvorak Left/Right look it up with `findKeycodeForCharacter("v")`, non-Latin layouts fall back to 9. With the layout-named cases gated shut, only the `Polish`-shaped substring match and `testPasteAllAvailableLayouts` ran — the branch that picks the key code was never chosen here. |
| `ClipboardUtilKeyboardLayoutTests` | 11 | 9 | `XCTSkip("<id> layout not available")` | `findKeycodeForCharacter` and `isQwertyCommandLayout` — the two functions `sendCmdV` decides with — untested on this machine. |
| `KeyboardLayoutProviderTests` | 9 | 6 | `XCTSkip("<id> layout not available")`, `XCTSkip("This machine has ANSI keyboard…")` | `resolveInfo()` for a named layout; only the active layout's label count was covered. |
| `PCMRecordingTests` | 1 | 1 | `XCTSkipUnless(OSW_TEST_MICROPHONE == "1")` + mic authorization | muted-recording capture. Unchanged, and unrelated to layout. |
| `WhisperTurboRegressionTests` | 2 | 2 | `XCTSkip("Set OSW_TEST_TURBO_MODEL to large-v3-turbo")` | the turbo model path. Unchanged. |

51 of the 54 are the same accident. The instrument (not the product) is the cause: this machine has
exactly one selectable keyboard layout — `com.apple.keylayout.PolishPro`, plus three non-keyboard input
methods — and `ClipboardUtil.switchToInputSource` matches by substring, so out of the 37 hard-coded ids
only `"Polish"` finds anything. Verified with a standalone probe that mirrors
`TISCreateInputSourceList(nil, false)` + the three-way substring test:

```
selectable input sources (TISCreateInputSourceList(nil, false)):
  com.apple.keylayout.PolishPro
  com.apple.CharacterPaletteIM
  com.apple.PressAndHold
  com.apple.inputmethod.ironwood
match: Polish -> HIT com.apple.keylayout.PolishPro; all 36 other hard-coded ids -> SKIP
```

That is also why this machine reports 36 paste skips where the brief's table says 35: the count depends
on which input sources the machine happens to have enabled, which is the whole point of the finding. The
fleet already corrected that figure (`FLEET-STATE.md`: "51 layout-gated … the older '50 of the 54 are
layout-gated' figure undercounted `ClipboardUtilPasteIntegrationTests` by one") and recorded why the same
tree can read 50 or 51: `testPasteWithTurkishLayout`'s gate, `ClipboardUtil.switchToInputSource(withID:)`,
can return `noErr` without the layout becoming active, so the case skips under load and passes alone —
without the layout ever being in use. The new cases do not share that weakness: they never call
`switchToInputSource`, and they assert the delivered text (and, for the paste case, the key code posted)
rather than the name of a layout.

## Before/after, from the suite's own output lines

Same machine, same base `c6f9546`, both runs headless from the clean state
(`rm -rf build libllama/build libwhisper/build`), whole unit bundle.

| run | log | case lines |
|---|---|---|
| before (changes stashed) | `/tmp/fm26-suite-before.log` | **387 passed / 0 failed / 54 skipped**, 441 cases, `** TEST SUCCEEDED **`, exit 0, 2m41s |
| after (final code) | `/tmp/fm26-suite.log` | **390 passed / 0 failed / 54 skipped**, 444 cases, `** TEST SUCCEEDED **`, exit 0, 2m41s |

Counting method: `grep -c "^Test case '"` for the case total and the verdict token after the closing
`)'` for the split. The after log prints 389 `passed` lines because one line
(`WhisperLongFormLanguageIntegrationTests.testCancellingLongWhisperDecodeStopsNativeOperation`) was split
by a timestamped `xcodebuild` message written into the middle of it — the same case is `passed` in the
before log, `grep -c " failed on '"` is 0 in both logs, and `** TEST SUCCEEDED **` with exit 0 means no
case failed, so 444 − 54 = 390 passes. See the instrument section.

Delta: exactly the three cases added, all `passed`, with the 54 skips unchanged (9 layout + 36 paste +
6 provider + 1 mic + 2 turbo, i.e. the same 51 layout-gated ones).

Focused before/after on the classes this task touched (`/tmp/fm26-before-layouts.log`,
`/tmp/fm26-after-layouts.log`), showing the added cases as `passed` where the family used to skip:

```
before: ClipboardUtilKeyboardLayoutTests 2 passed / 9 skipped   ClipboardUtilPasteIntegrationTests 2 passed / 36 skipped
        KeyboardLayoutProviderTests 3 passed / 6 skipped
after : ClipboardUtilKeyboardLayoutTests 2 passed / 9 skipped   ClipboardUtilPasteIntegrationTests 3 passed / 36 skipped
        KeyboardLayoutProviderTests 4 passed / 6 skipped   KeyboardSimulatorDeliveryTests 1 passed
Test case 'KeyboardSimulatorDeliveryTests.testTypesTheExactTextThroughTheActiveInputSource()' passed on 'My Mac - OpenSuperWhisper (16670)' (0.016 seconds)
Test case 'ClipboardUtilPasteIntegrationTests.testPasteWithActiveInputSource()' passed on 'My Mac - OpenSuperWhisper (16666)' (1.829 seconds)
Test case 'KeyboardLayoutProviderTests.testResolveInfo_ActiveLayout_returnsInfo()' passed on 'My Mac - OpenSuperWhisper (16668)' (0.107 seconds)
```

The 51 layout-gated skips stay 51: they name a layout and are still honest when it is absent, exactly as
the brief requires. What changed is that the delivery contract is no longer among them.

## What the new coverage catches that the old could not

First, an accuracy note that changes how this work should be read: **the layout-gated paste family is not
the captain's delivery path.** `ClipboardUtil`'s paste mechanism (`insertText`, `insertTextAndKeepInClipboard`,
`simulatePaste`, `sendCmdV`, `findKeycodeForCharacter`, `isQwertyCommandLayout`,
`insertTextUsingPasteboard`) has **no caller in the app target**:

```
$ grep -rn "ClipboardUtil\.<symbol>" --include=*.swift OpenSuperWhisper/ | grep -v Utils/ClipboardUtil.swift
ClipboardUtil.copyToClipboard: app=3        (IndicatorWindow.swift:418, :439, OpenSuperWhisperApp.swift:388)
ClipboardUtil.insertText: app=0             ClipboardUtil.sendCmdV: app=0
ClipboardUtil.findKeycodeForCharacter: app=0    ClipboardUtil.isQwertyCommandLayout: app=0
ClipboardUtil.insertTextAndKeepInClipboard: app=0  ClipboardUtil.simulatePaste: app=0
```

Delivery today is `KeyboardSimulator.typeText`, called from `IndicatorWindow.insertText` through
`injectTextOperation` (`IndicatorWindow.swift:66`, `:420`). So the 45 layout-gated cases the brief counted
guard a module the app no longer calls, and the always-running case that actually guards dictation is the
new keyboard-simulator one. (`findKeycodeForCharacter` is called from the new test as an *oracle* — "does
the active layout have a key for this character?" — not as code under test; that is the only new caller.)
Retiring the orphaned paste path is a product decision and was deliberately left alone.

With that said, the concrete defect class the new coverage catches is: **a delivery path that derives the
typed characters from the active keyboard layout instead of carrying the transcript.** On a machine with
one Latin layout, a bug of that kind — resolving key codes through
`TISCopyCurrentKeyboardInputSource`/`UCKeyTranslate` (the shape `ClipboardUtil.sendCmdV` uses) instead of
`keyboardSetUnicodeString`, or dropping the Unicode payload, or chunking text so characters are lost —
delivers either nothing or the layout's own characters, and the transcript never arrives. Every existing
case that would have shown it on the daily path is gated on layouts this machine does not have; the two
cases that did run (`testPasteAllAvailableLayouts`, the `Polish` paste) exercise only a Latin layout, and
a module production does not call.

The new case makes that failure visible without any layout prerequisite, because it types a payload the
active layout *cannot* produce from its keys (CJK, Cyrillic, an emoji, plus Polish diacritics, a newline
and a tab) and asserts the receiver's text character for character, over more UTF-16 units than
`maxUTF16PerEvent`, so the chunk boundaries are exercised too. It also checks the receiving half of the
contract for free: the Return and Tab events go through AppKit's own key bindings
(`insertNewline:`/`insertTab:`) into a real `NSTextView`, so a wrong control key code shows up as a
missing line break rather than as a passing key-code comparison.

The paste side adds the same always-running property for the legacy clipboard path: the ⌘V event the app
posts is asserted to be the Paste key equivalent of a real Edit menu and the text arriving in a text view
is asserted, on the active layout — the branch of `sendCmdV` no layout-named case can reach on this
machine.

## The mutations that prove both new cases bite

**1. The delivered payload.** `OpenSuperWhisper/Utils/KeyboardSimulator.swift`, `makeUnicodeEvents`: the
two `keyboardSetUnicodeString(...)` calls were replaced with `_ = utf16` (deliberate, then reverted).

```
$ Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/KeyboardSimulatorDeliveryTests
** TEST FAILED ** (exit 65)
Test case 'KeyboardSimulatorDeliveryTests.testTypesTheExactTextThroughTheActiveInputSource()' failed
XCTAssertEqual failed: ("aa
	a") is not equal to ("Zažółć gęślą jaźń — 中文測試 Ж їß 😀 ok
	tail") - the focused application must receive the transcript character for character
```

The received text is the active layout's own answer for key code 0 (`a` on Polish Pro) — the mutation
turns the delivery path into exactly the layout-consulting path this test exists to catch. On the
unmodified branch the same command passes (0.016 s).

**2. The ⌘V key code.** `OpenSuperWhisper/Utils/ClipboardUtil.swift`, `sendCmdV`:
`findKeycodeForCharacter("v")` was changed to `findKeycodeForCharacter("x")` — the key code the paste
path posts for the key equivalent, on the branch this machine's layout actually takes.

```
$ Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/ClipboardUtilPasteIntegrationTests/testPasteWithActiveInputSource
** TEST FAILED ** (exit 65), 5.491 s
XCTAssertTrue failed
XCTAssertEqual failed: ("") is not equal to ("Hello from the active input source (com.apple.keylayout.PolishPro)") - Paste failed for the active input source com.apple.keylayout.PolishPro
```

Both assertions fell over — the Edit menu refused ⌘X as Paste, and nothing arrived — so the new paste
case really does check the key code and not just that *something* was posted. A first attempt at this
mutation (`qwertyKeyCodeV = 9` → `7`) is worth recording because it exposed the branch structure rather
than the test: it **passed**, because on this layout `isQwertyCommandLayout()` is false and
`findKeycodeForCharacter("v")` returns 9, so the hard-coded constant is never used — mutating it changes
nothing the machine executes. The mutation was rewritten to target the taken branch.

Both mutations were reverted; the working tree's blobs for `ClipboardUtil.swift` and
`KeyboardSimulator.swift` are byte-identical to the commit (`git diff HEAD` empty, `git hash-object`
equal to `git ls-tree HEAD`), and the committed diff touches only the two test files.

## Determinism soak

`-test-iterations` (Xcode ran 100 repetitions of each selected case), 226 s, exit 0:

```
$ Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/KeyboardSimulatorDeliveryTests \
    -only-testing:OpenSuperWhisperTests/ClipboardUtilPasteIntegrationTests/testPasteWithActiveInputSource \
    -only-testing:OpenSuperWhisperTests/KeyboardLayoutProviderTests/testResolveInfo_ActiveLayout_returnsInfo \
    -test-iterations=5 -run-tests-until-failure
** TEST SUCCEEDED **
testTypesTheExactTextThroughTheActiveInputSource passed: 100
testPasteWithActiveInputSource passed: 99        (the 100th line was split by interleaved output; 0 failures)
testResolveInfo_ActiveLayout_returnsInfo passed: 100
failed lines: 0
```

Nothing is posted, nothing is switched, nothing touches the network, so the cases are offline and
CI-safe; 100 consecutive passes of the delivery case on the same process is the evidence for that.

## It runs where the old cases skip

Established on this machine, which has one keyboard layout and none of the hard-coded ones: the 51
layout-gated cases skip, and the three new cases pass in the same runs (see the case lines above). The
new case is also layout-agnostic by construction rather than by luck: it never switches the input
source, and its payload contains characters that no Latin, Cyrillic or Romaji layout can type from a
key, so it holds for whatever layout a machine has.

## Honest limits

- **Not covered: the HID event tap and the window server's routing.** The new case replaces the `post`
  closure, exactly as the existing `KeyboardSimulatorTests` do — posting real events in a test host that
  *is* the app would land keystrokes in whatever application is focused, which this fleet forbids. So the
  receiver sees the events at the boundary the app hands them to the system, converted to `NSEvent` the
  way the window server would; delivery to a *different* frontmost application is not asserted by any
  test.
- **The composition is covered in two halves, not one chain.** That the transcript reaches the injection
  call is covered by `DictationInjectionTests` with a stubbed injector; that the injector delivers text
  verbatim is covered by the new case. No single test drives a dictation into a receiver; adding one
  would have meant duplicating that class's private harness, and the seam it would cover (the pipeline
  passes `finalText` unchanged) is already asserted there.
- **A second active layout was not exercised.** Switching this machine's layout means changing the
  captain's enabled input sources, so the new case was only seen running under `com.apple.keylayout.PolishPro`.
- **`ClipboardUtilKeyboardLayoutTests` has no always-running case.** Its subject functions are only
  visible through the ⌘V key code, which the new paste case now asserts end-to-end on the active layout
  (mutation 2 above) and which the Dvorak cases still pin for the layouts they name. A layout-independent
  unit assertion on `findKeycodeForCharacter` was considered and dropped: written as a round trip through
  the same `UCKeyTranslate` call it would have re-stated production logic, i.e. been a tautology.
- `testPasteWithActiveInputSource` and `testResolveInfo_ActiveLayout_returnsInfo` `XCTUnwrap` the active
  input source instead of skipping: a GUI session always has one, so a nil there is a real defect, and
  the reasons the other cases skip are all still explicit in their `XCTSkip` strings.

## Instrument failure modes found (check the instrument before blaming the product)

1. **The skip count is an input-source inventory, not a product property.** 36 paste skips here vs the
   brief's 35, because `ClipboardUtil.switchToInputSource(withID:)` substring-matches the ids the machine
   has *enabled*: with `PolishPro` alone, `"Polish"` hits and nothing else does. Any recorded skip count
   is only comparable across machines with the same enabled layouts. `getAvailableInputSources()` and
   `TISCreateInputSourceList(nil, false)` also return three non-keyboard input methods next to the one
   layout, which is why `testPasteAllAvailableLayouts` filters on category + select-capable.
2. **`xcodebuild test` prints no assertion text.** A failing case appears only as `Test case '…' failed
   on 'My Mac - OpenSuperWhisper (pid)'`; the message lives in the run's `.xcresult` and needs
   `xcrun xcresulttool get test-results tests --path …` to read. Anything reporting a failure should quote
   from there, not from the console log.
3. **A test process's `print` does not reach the log.** `TestFixtures.report` only lands in a file when
   `OSW_TEST_EVIDENCE` (forwarded as `TEST_RUNNER_OSW_TEST_EVIDENCE`) is set; the acceptance run above
   was made with both exported, so `/tmp/fm26-evidence.log` carries the `keyboard delivery:` line with
   the active input source and the event count.
4. **The `post` closure is the only safe seam for delivery tests in this suite.** The test host is the
   app (`TEST_HOST = $(BUILT_PRODUCTS_DIR)/OpenSuperWhisper.app/…`), so a test that posted to the HID tap
   would type into whatever application the captain has focused — the hazard this fleet has already been
   burned by.
5. **Per-case lines can be split by concurrent `xcodebuild` output.** In the after run one line reads
   `Test case 'WhisperLongFormLanguageIntegrationTests.testCancellingLongWhisperDecode2026-09-24 14:04:02.420 xcodebuild[…] … Testing started completed.`
   — the case's verdict was written over by a timestamped progress message, so a `grep -oE` over the log
   silently loses one case (my first tally read 437 cases instead of 444). Anchor the pattern at the start
   of the line, and take the failure verdict from `** TEST SUCCEEDED **`/exit status rather than from the
   line count.
6. **The layout-gated classes share the process-wide pasteboard and input source.** The paste cases run in
   parallel with every other class, so any assertion they add about the pasteboard is a race; this is why
   the clipboard-untouched claim stays in the single case that owns it
   (`KeyboardSimulatorTests.testTypeTextDoesNotTouchPasteboard`) and was not repeated in the new delivery
   case.

## Bundle state

Signed by `Scripts/dev-run.sh test`'s signing pass and asserted from disk afterwards:

```
$ codesign -d -r- build/Build/Products/Debug/OpenSuperWhisper.app
designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
$ ls -1 build/Build/Products/Debug/OpenSuperWhisper.app/Contents/MacOS/
OpenSuperWhisper                                   # one binary, 75 670 352 bytes, no *.debug.dylib
$ codesign --verify --strict build/Build/Products/Debug/OpenSuperWhisper.app && echo "strict verify OK"
strict verify OK
```

The identity requirement (not a bare `cdhash`) is what keeps the Accessibility grant, and the
entitlement the delivery path needs is present (`com.apple.security.accessibility = true`). The check was
re-run after the last test invocation, so it describes the bundle on disk now.

## Evidence files

| file | what it is |
|---|---|
| `/tmp/fm26-suite-before.log` | full suite, changes stashed, clean state — 387/0/54, TEST SUCCEEDED |
| `/tmp/fm26-suite.log` | **acceptance** full suite, final code, clean state — 390/0/54, TEST SUCCEEDED, exit 0 |
| `/tmp/fm26-evidence.log` | `TestFixtures.report` channel of the acceptance run (active input source, events) |
| `/tmp/fm26-before-layouts.log`, `/tmp/fm26-after-layouts.log` | focused before/after on the three gated classes |
| `/tmp/fm26-mutation.log`, `/tmp/fm26-mutation-paste2.log` | the two mutation failures |
| `/tmp/fm26-repeat.log` | the 100-iteration soak |
| `/tmp/fm26-KeyboardSimulator.orig.swift`, `/tmp/fm26-ClipboardUtil.orig.swift` | pre-mutation copies of the two product files (reverted) |

Nothing in the worktree is left modified: `git status` is clean at `62eb921`, and the only diff from the
base `c6f9546` is the two test files (+222/−4).
