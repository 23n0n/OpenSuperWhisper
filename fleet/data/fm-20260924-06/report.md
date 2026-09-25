# fm-20260924-06 — the shortcut recorder records, and the key-combination mode can no longer be silent

## Outcome

The captain's two symptoms traced to one place each, both now covered by a test:

1. *"Shortcut recording is not working properly."* The Settings recorder never started listening. The
   library installs its keyboard monitor in `becomeFirstResponder()` and nowhere else, and a click on its
   `NSSearchField` never gets it there: AppKit puts the **field editor** in as the window's first responder
   and never asks the field itself (measured, in the app's own sheet — see below). So the monitor did not exist, and everything the user pressed was typed
   into the field as ordinary text. A small host view around the library's recorder now hands it the first
   responder on the click; the library keeps doing everything else (display, conflict/“taken by the system”
   checks, storage, monitoring).
2. *"Detecting the first shortcut pre-recorded is not working properly. The hook is not monitoring my
   input properly."* The key-combination mode could be selected while **no** combination existed: the
   trigger picker wipes the modifier hotkey, and the library's stored `false` — what it writes when a
   combination is cleared, which is exactly the `KeyboardShortcuts_toggleRecord = 0` on his machine — stops
   `Name.init` from ever applying the initial this app declares for `toggleRecord`. The mode was therefore
   armed with nothing, with no monitor behind it and nothing on screen saying so. `ShortcutManager` now
   arms the declared combination whenever that mode is the live one.

`isRecordingNewShortcut` (declared but never set, with a hint that could never appear) is gone — the
library's own field is the recording indicator.

## The mechanism, measured at file:line

`KeyboardShortcuts.RecorderCocoa.becomeFirstResponder()` is the only place its `LocalEventMonitor` is
created (`SourcePackages/checkouts/KeyboardShortcuts/Sources/KeyboardShortcuts/RecorderCocoa.swift:339-425`,
the monitor at `:363`), and it is the only place that shows “Press Shortcut” instead of “Record Shortcut”.
The app used that recorder as it comes: `Settings.swift:2319` (old) → `KeyboardShortcuts.Recorder("",
name: .toggleRecord)`.

Measured in this process, with the library's own recording notification
(`KeyboardShortcuts_recorderActiveStatusDidChange`) as the detector — it fires exactly when the monitor is
installed and removed — plus the field's value and the window's first responder:

| what was clicked | recording after the click | after ⌥⇧K |
|---|---|---|
| the library's recorder as it comes (the app's old view) | `[false, true, false]` — it starts during window setup and is **not** recording when the click is over | `stored=nil`, the field's value became `K` |
| the same recorder through the host view (`Settings.swift:1164`) | `[false, true]` — recording is on | `stored=⌥⇧K`, the field shows `⌥⇧K` |

The click is delivered, it just never reaches the field's activation path: after it the window's first
responder is an `NSTextView` — the field **editor** — while the field itself is never asked. A vanilla
`NSTextField` in the same window behaves identically (`becomeFirstResponder()` calls: 0), so this is not a
property of the library's field but of how a text field is focused here: the responder is the field editor,
not the control. Making the recorder the first responder — `NSWindow.makeFirstResponder(recorder)`, which is
exactly what the library's own `focus()` helper does — is enough to make it work, and that is the whole of
the fix.

Reproduction without the fix is part of the suite: `testTheLibraryRecorderAsItComesCapturesNothing` clicks
the library's recorder with no host and asserts the user-visible symptom (`stored=nil`, the combination
typed in as text). Neutering the host's hit test (restoring `super.hitTest(point)`, i.e. letting the click
reach the field as before) makes the regression case fail exactly as the captain sees it:
`recording=[false, true, false] stored=nil shown=K` (`raw/recorder-without-host.txt`). The new cases assert
the combination as a carbon key code and modifier set, and the recorder's rendered text against the text
the library renders for that same combination, so nothing in them names this machine's keyboard layout.

Both raw runs are in `raw/recorder-after.txt` and `raw/recorder-without-host.txt`.

## What changed

| file | +/- | change |
|---|---|---|
| `OpenSuperWhisper/Settings.swift` | +68/-7 | `ShortcutRecorderHost` + `ShortcutRecorderField` (NSViewRepresentable) around the library's recorder, `Settings.swift:1164-1209`, used at `:2382`; the dead `isRecordingNewShortcut` state (`:1154` old) and its unreachable hint (`:2327` old) removed, replaced by one caption saying what the field does (`:2390`) |
| `OpenSuperWhisper/ShortcutManager.swift` | +9/-0 | the key-combination branch of `setupRecordingTrigger()` arms the name's declared initial when nothing is stored (`:140-149`) |
| `OpenSuperWhisperTests/ShortcutRecorderTests.swift` | +332 (new) | four cases: the click path in the real sheet, the library's recorder as a control, the mode armed with nothing stored, and mode exclusivity |

## The silent wipe: what was chosen, and why

**The mode is never triggerless** — the key-combination branch arms `toggleRecord`'s declared combination
(`KeyboardShortcuts.reset(.toggleRecord)` → ⌥`, the initial this app's own `Name` extension declares) when
no combination is stored.

The alternative the brief offers — preserve the previously used modifier hotkey from
`lastModifierOnlyHotkey` — cannot be the one here: `triggerMode` is *derived* from the two hotkey
preferences (`Settings.swift:2099-2103`: mouse → modifier → key combination). Keeping `modifierOnlyHotkey`
set while the user picks “Key Combination” would make the segmented control snap straight back to “Single
Modifier Key”, i.e. the mode could never be selected at all, and arming the modifier monitor while the
key-combination mode is the chosen one would break the mutual exclusivity this task says to keep
(`testAModifierHotkeyLeavesTheKeyCombinationUnarmed` pins it). Making the mode *work* is strictly better
than making it *visible*: with a combination stored there is no inert state left to report, and the field
shows it (⌥`) right where the user is looking.

Trade-off, stated plainly: a user who deliberately clears the recorder field keeps it cleared until the
next reconfigure (launch, or an Accessibility change) arms the declared combination again. That is the
price of “the selected mode always has a trigger”, and it is the state a fresh install is in anyway.

## What was not touched

The sampling/seed path, `TransformModelManager.modelID(forOutputLanguage:)`, the prompt text and
`params.noTimestamps` are untouched — `git diff` is two product files, and neither of them is on those
paths. The three trigger modes are still torn down and re-armed one at a time exactly as before; the only
thing added in that function is what the key-combination branch does when it would otherwise have nothing.

## Verification

```
Scripts/dev-run.sh test                      # clean state (build/ removed), full suite
TEST_RUNNER_OSW_TEST_EVIDENCE=/tmp/fleet-recorder-after.txt \
  Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/ShortcutRecorderTests
```

Commit `058d08a` on `fm/shortcut-recorder`, base `ffda358` — three files, +409/-7, nothing else touched.
The full suite from a clean state (`build/` removed), read from the run's own `xcresult` summary, which is
authoritative — log-line counting undercounts when parallel test processes interleave:

```
result: Passed     450 total = 396 passed / 0 failed / 54 skipped      exit 0
Failing tests: none
Signature OK.  identity: OpenSuperWhisper Local Dev
  designated requirement: identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
Unit suite passed and the app is signed for the next launch.
```

The four cases added by this task are the whole delta in the test files — `git show --stat` is the two
product files plus `OpenSuperWhisperTests/ShortcutRecorderTests.swift`, and no other test file was edited,
so the 54 skips are the ones the suite already had. Full log at `raw/suite.log` (and `/tmp/fmshort-suite.log`).

No existing case was deleted, weakened or re-pinned: the suite's totals move by exactly the four new cases
(and nothing else was edited outside the two product files above).

## Unverified, or deliberately left alone

- **The key-window variant of the click path is not measured.** This process cannot own a key window:
  `NSApp.activate()`, `NSRunningApplication.current.activate(options: [.activateAllWindows])` and
  `makeKeyAndOrderFront` all leave `NSApp.isActive == false` and every window `isKey == false` (measured).
  So both measurements above are in windows that never became key. The fix does not depend on which of the
  two it is — it makes the app hand the recorder the first responder itself, and that is measured to work in
  the real Settings sheet.
- The captain's own build was not driven (headless rule), so his app's behaviour is covered by the control
  measurement plus his report, not by a run of his bundle.
- `NSApp.postEvent` reaches nothing in an inactive process (measured: neither a probe monitor nor the field
  editor saw a posted key), so the suite delivers its keystroke with `NSApp.sendEvent`. The window server's
  routing of a real key press to the app is the one step no headless test can take.
- The library itself was not patched or forked.
- For the first mate: this branch is based on `ffda358`, the delivery tip at dispatch; the primary
  checkout has since moved on (`58d3744 Merge fm-20260924-08`), so the local merge happens on top of that,
  not on `ffda358`.
- The mutation run built the bundle from the deliberately broken source. The delivered source was rebuilt
  and re-signed afterwards — a final scoped run of `ShortcutRecorderTests` (green) — so the bundle on disk
  is the committed code, and the last signature check reports the certificate leaf above.
