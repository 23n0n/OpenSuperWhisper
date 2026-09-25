# fm-20260924-08 — interference safety: a transcript never lands in the wrong flow

## Outcome

Delivery stops itself the moment it stops being safe. Two things end it: the application the delivery was
aimed at is no longer frontmost, or a keystroke arrives that this process did not post. In both cases the
remaining chunks are never posted, and the callers learn which interference ended the delivery and how many
characters had gone out, through `InjectionResult` and the reporting path the untrusted-Accessibility case
already uses.

Nothing about *how* text is delivered changed: same chunking (`maxUTF16PerEvent = 20`), same
`keyboardSetUnicodeString` events, no delays, clipboard untouched, Accessibility the only grant, and the
same event count for the same text (38 events for 200 characters, 200 for 1000 — measured below, before and
after). `KeyboardSimulatorDeliveryTests` (fm-20260923-26) is not touched, not weakened, and green.

Commit `407821f` on `fm/keypress-streamline`, base `ffda358`. Worktree
`worktrees/OpenSuperWhisper-fm-keypress`. Nothing pushed, nothing merged.

## Files changed

| file | +/- | change |
|---|---|---|
| `OpenSuperWhisper/Utils/KeyboardSimulator.swift` | +180/-15 | `DeliveryInterruption` (the two kinds), `DeliveryWatch` + `DeliveryWatch.live()` (the two session probes), `typeText(_:trusted:watch:post:)` consulting the watch before every pair of events and stopping cleanly, `InjectionResult.interruptedBy` / `.deliveredCharacters`, two new fields on the one-line dictation log |
| `OpenSuperWhisper/Indicator/IndicatorWindow.swift` | +42/-2 | the production call site passes `watch: .live()`; `insertText(_:)` logs the new fields and, when a delivery was interrupted, reports it to the user with `reportInterruptedInjection(_:delivered:total:)` (same `AppErrorCenter` path as the trust warning) |
| `OpenSuperWhisperTests/KeyboardSimulatorInterferenceTests.swift` | +277 (new) | the two interference cases, each run guarded *and* unguarded, plus the live watch's arithmetic, its quiet case, the control-character accounting and the empty-text case |
| `OpenSuperWhisperTests/DictationInjectionTests.swift` | +69/-0 | `testInterruptedInjectionIsReportedToTheUser()` — both kinds reach the user, with the delivered count and where the rest of the dictation is |

Of `KeyboardSimulator.swift`'s 180 added lines, 86 are the doc comments that carry the reasoning for the
discriminator (the brief asks for that reasoning to be defensible, and the code is where it is read);
the behavioural change is ~80 lines, most of it the `emit`/`flushBuffer` restructure.

## The discriminator for a real user keystroke, and why it cannot misfire

**Chosen: the login session's own key-down counter, minus the key-downs this delivery posted.**

```
CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
```

The delivery reads it once as it begins and again before every pair of events. A surplus over the key-downs
the delivery itself has posted is a keystroke this process did not make, and it ends the delivery. The
counter is documented as counting what the window server has seen, and the combined-session table, in
CoreGraphics' words, "reflects the combined state of all event sources posting to the current user login
session"; this process is one of them (it creates its events from a `combinedSessionState` source, exactly
as the header recommends for a program posting inside a login session), so its own key downs are part of the
number and the subtraction leaves what somebody else did. A keystroke is interference whether it came from
the keyboard or from another process typing into the same application — the delivery cannot tell those
apart, and should not: both corrupt the flow.

**Why a monitor or an event tap was not used, even though the brief offers them.** The delivery is one
uninterrupted main-thread turn: `IndicatorWindow.insertText` reaches `KeyboardSimulator.typeText`
synchronously and the loop never returns to the run loop (measured: a 1000-character transcript is posted
in ~0.16 ms). An `NSEvent` monitor or a `CGEventTap` is run-loop driven, so its callback cannot run inside
that turn — it would deliver "the user typed" *after* the delivery was already over. Only synchronous
session queries can be read between chunks, and both probes are cheap enough to be free: measured on this
machine, `NSWorkspace.frontmostApplication` costs 0.23 µs per read and the key-down counter 0.01 µs.

**Why it cannot misfire on the empty case — both senses of "empty".**

1. *Nothing competing.* With no other keystrokes, the session's count rises by exactly the key downs the
   delivery posted, so the surplus is zero and the watch is silent. This is not only argued but run: with
   stand-in probes, `testTheLiveWatchTellsItsOwnKeystrokesFromTheUsers` asserts a delivery's own key down is
   `nil` at the very checkpoint where the next one is `.userTyping`; with the real probes,
   `testTheLiveWatchDoesNotStopADeliveryThatNothingInterferesWith` delivers the whole payload and asserts
   `result.interruptedBy == nil`.
2. *Empty transcript.* `typeText("")` returns before the loop, so the watch is never asked —
   `testEmptyTextNeverConsultsTheWatch` asserts the check count is 0 with a watch that would always answer
   `.userTyping`.

The arithmetic is deliberately fail-safe in the direction that matters: if the session did **not** count
this process's posts, the surplus would go negative and every delivery would simply continue (today's
behaviour, no damage), and a counter that went backwards is treated as "no evidence" rather than as
interference. Both shapes are asserted. For the watch to stop a *healthy* delivery, the session must have
seen more key downs than the delivery posted, which is exactly the condition that means somebody else
typed — its failure mode is a missed stop, never a stopped dictation.

The focus half cannot misfire either: the target is the frontmost application captured as the delivery
begins, and an unreadable frontmost application (or a session with none) counts as "unchanged", never as a
change. That the capture cannot be the app itself was checked, not assumed: the indicator panel is
`.nonactivatingPanel` (`IndicatorWindowManager.swift:205`) and the app activates itself only in
`showMainWindow()`, so during a delivery the frontmost application is the user's.

## The two interference modes, the tests that produce them, and what they assert

Both cases host two/one `TypingReceiverView`s (the smallest receiver that can host real key events, reused
from `KeyboardSimulatorTests.swift`) and route each posted event to whichever receiver is frontmost when it
arrives; a competing keystroke is fed to the receiver outside the delivery's sink. The one step a headless
test must not take — posting through the HID event tap for the window server to route — is the only step
replaced, exactly as the delivery contract test does.

Payload: five chunks of twenty UTF-16 units, `AAAA…BBBB…CCCC…DDDD…EEEE…`. Each chunk is a letter no other
chunk uses, so "the tail is absent" is a real assertion rather than an accident of a repetitive payload in
which the tail happens to sit inside the typed prefix — a flaw the first version of this test had, and the
test failed because of it (`XCTAssertFalse failed - the tail of the transcript was typed after the user's
keystroke: "abcdefghij…abcdefghijQ"`), which is why the payload is what it is now.

### 1. The frontmost application changes mid-delivery

`KeyboardSimulatorInterferenceTests.testDeliveryStopsWhenTheFrontmostApplicationChanges()` — after three
chunks the frontmost receiver changes; what the live watch reads as a different frontmost process id is
what the stand-in watch reports.

```swift
        XCTAssertEqual(result.interruptedBy, .focusChanged, "the result must name the interference")
        XCTAssertEqual(result.deliveredCharacters, Self.typedBeforeInterference.count)
        XCTAssertEqual(result.eventsPosted, 6, "three chunks were posted, and not one event more")
        XCTAssertEqual(
            intended.editor.string, Self.typedBeforeInterference,
            "what was typed before the switch must have arrived intact and in order"
        )

        // The acceptance for this mode: the tail of the transcript is absent
        // from the new target — not merely a flag saying the delivery stopped.
        XCTAssertEqual(
            otherApplication.editor.string, "",
            "nothing may reach the application that came to the front"
        )
        XCTAssertFalse(
            otherApplication.editor.string.contains(Self.tail),
            "the tail of the transcript reached the newly frontmost application: "
                + "\"\(otherApplication.editor.string)\""
        )
```

The new target holds **nothing at all** — a stronger claim than the acceptance asks for — and the same test
runs the identical switch at the identical point with no watch, which is this task's "before":

```swift
        XCTAssertEqual(
            unfixedOtherApplication.editor.string, Self.tail,
            "control: without a watch the remaining chunks go to the new application"
        )
```

What it catches: a delivery that keeps posting after the application changed (the control proves it lands
the whole remaining tail in the new application), and a stop that is one chunk late or reports the wrong
delivered count (the `eventsPosted == 6` and `deliveredCharacters` assertions).

### 2. The user types mid-delivery

`KeyboardSimulatorInterferenceTests.testDeliveryStopsWhenTheUserTypesInsteadOfInterleaving()` — the user's
own keystroke is fed to the focused receiver through the window server's side, between the third and the
fourth chunk, at the exact delivery point where the control run feeds it too.

```swift
        XCTAssertEqual(result.interruptedBy, .userTyping, "the result must name the interference")
        XCTAssertEqual(result.eventsPosted, 6, "three chunks were posted, and not one event more")

        // Both streams did not mix: the transcript is one contiguous run, and the
        // user's own keystroke sits after it rather than between its characters.
        XCTAssertEqual(
            receiver.editor.string, Self.typedBeforeInterference + "Q",
            "expected the typed prefix and then the user's own keystroke, nothing between them"
        )
        XCTAssertFalse(
            receiver.editor.string.contains(Self.tail),
            "the tail of the transcript was typed after the user's keystroke: "
                + "\"\(receiver.editor.string)\""
        )
```

and the control, which is what the test would have caught:

```swift
        XCTAssertTrue(
            unfixed.editor.string.contains(Self.typedBeforeInterference + "Q" + Self.tail),
            "control: without a watch the user's keystroke lands between transcript characters: "
                + "\"\(unfixed.editor.string)\""
        )
```

The guarded run asserts the transcript arrives as *one contiguous run* with the user's character after it
(not spliced between transcript characters) and the tail absent; the unguarded run shows the interleaving
that used to happen, in the same process, in the same run.

### Supporting cases

- `testTheLiveWatchTellsItsOwnKeystrokesFromTheUsers()` — the live arithmetic against stand-ins: own key
  down is silent, a surplus is `.userTyping`, a changed frontmost process is `.focusChanged` (and wins over
  the count), a counter that does not move and one that went backwards are both silent, and an unreadable
  frontmost application is not a focus change.
- `testTheLiveWatchCountsTheKeyDownsOfControlCharacters()` — `ab\ncd\tef` delivered through a stand-in
  session that counts what it is handed: if the Return/Tab key downs were not counted, the delivery would
  blame itself and stop, so this case fails on that regression.
- `testTheLiveWatchDoesNotStopADeliveryThatNothingInterferesWith()` — the real probes, quiet end to end.
- `testEmptyTextNeverConsultsTheWatch()` — the empty transcript.
- `DictationInjectionTests.testInterruptedInjectionIsReportedToTheUser()` — both kinds reach the user: the
  title says the transcription was not typed in full, the message names the interference ("Another
  application came to the front" / "You started typing"), carries the delivered count ("3 of the
  dictation's"), and points at History, where the whole transcription is.

## Delivery cost, measured once, before and after

Same machine, same session, minimum of 7 interleaved batches per configuration (the machine is shared, so
the minimum is the honest cost of the work). Both binaries compile `KeyboardSimulator.swift` from source;
the sink is a capture closure, because posting for real would type into whatever is frontmost on this
machine — the one step the headless rule forbids.

```
$ ./bench-baseline            # keyboard simulator at ffda358
baseline payload- 200 chars:  38 events |   31.1 us
baseline payload-1000 chars: 200 events |  148.0 us
$ ./bench-current             # this commit
current payload- 200 chars:  38 events, 200 delivered | no watch   31.8 us | live watch   33.9 us
current payload-1000 chars: 200 events, 1000 delivered | no watch  156.8 us | live watch  163.7 us
```

| payload | events | baseline | this commit, no watch | this commit, live watch |
|---|---|---|---|---|
| 200 characters | 38 | 31.0–31.1 µs | 31.8–33.1 µs | 33.9–34.2 µs |
| 1000 characters | 200 | 144.5–149.1 µs | 156.7–156.8 µs | 163.5–170.7 µs |

Read: the event count is identical before and after (38 / 200 — the chunking and the event production are
untouched), the posting loop is unchanged apart from counting what it posts (~5% on the 1000-character
payload, ~8 µs, from the bookkeeping, not from any delay), and the live watch adds ~0.15 µs per checkpoint
(~2 µs on a 200-character dictation, ~7 µs on 1000). `deliveredCharacters` equals the character count when
nothing interferes.

For the record, since the brief asked for it: a 1000-character dictation is 200 events in ~0.16 ms. There
is no throughput problem to report.

## Verification

**Suite, headless, from a clean state** (`rm -rf build libllama/build libwhisper/build`, the same clean
state the fleet's previous crew used), whole unit bundle:

```
$ Scripts/dev-run.sh test > /tmp/fm2408-suite.log 2>&1        # exit 0
$ xcrun xcresulttool get test-results summary --path build/Logs/Test/Test-OpenSuperWhisper-2026.09.24_16-19-23-+0200.xcresult
  "failedTests" : 0, "passedTests" : 399, "skippedTests" : 54, "result" : "Passed"
```

453 cases: **399 passed / 0 failed / 54 skipped**, `** TEST SUCCEEDED **`, exit 0, and the log ends with
`Unit suite passed and the app is signed for the next launch.` The 54 skips are the same 54 the fleet
recorded for the base (51 layout-gated + microphone + 2 turbo); no case was deleted, weakened or
re-pinned, and `KeyboardSimulatorDeliveryTests.testTypesTheExactTextThroughTheActiveInputSource()` passed
in the same run (0.020 s). Every new case passed:

```
KeyboardSimulatorInterferenceTests.testDeliveryStopsWhenTheFrontmostApplicationChanges() passed (0.024 seconds)
KeyboardSimulatorInterferenceTests.testDeliveryStopsWhenTheUserTypesInsteadOfInterleaving() passed (0.005 seconds)
KeyboardSimulatorInterferenceTests.testTheLiveWatchTellsItsOwnKeystrokesFromTheUsers() passed (0.001 seconds)
KeyboardSimulatorInterferenceTests.testTheLiveWatchCountsTheKeyDownsOfControlCharacters() passed (0.001 seconds)
KeyboardSimulatorInterferenceTests.testTheLiveWatchDoesNotStopADeliveryThatNothingInterferesWith() passed (0.003 seconds)
KeyboardSimulatorInterferenceTests.testEmptyTextNeverConsultsTheWatch() passed (0.001 seconds)
DictationInjectionTests.testInterruptedInjectionIsReportedToTheUser() passed (0.029 seconds)
```

No case failed, so nothing here needs the "fails in the full suite, passes alone" caveat. Two instruments
notes, both of which the previous crew hit as well: counting `^Test case '` lines in the log gives 398
`passed` where the xcresult says 399, because one case line was split by a timestamped `xcodebuild` message
written into the middle of it (0 ` failed on '` lines in both instruments, `** TEST SUCCEEDED **`, exit 0);
and the case *total* differs by 2 from the fleet's recorded 444 for the base, which my sources cannot cause
— `git grep -c "func test"` is 447 at `ffda358` and 454 here, exactly the 7 methods this commit adds (6 in
the new class, 1 in `DictationInjectionTests`), each of which appears as a passed case above. I did not
re-run the suite on the bare base, so I do not attribute the remaining 2-case difference between the two
runs' totals; the delta between the *revisions* is exactly those 7 methods.

**The tested revision is the committed one.** `build/` was wiped immediately before the run, and every
object post-dates its source:

```
Sep 24 16:19:17  build/…/OpenSuperWhisper.build/Objects-normal/arm64/KeyboardSimulator.o
Sep 24 16:19:31  build/…/OpenSuperWhisperTests.build/Objects-normal/arm64/KeyboardSimulatorInterferenceTests.o
2026-09-24 16:16:05  OpenSuperWhisper/Utils/KeyboardSimulator.swift
2026-09-24 16:12:18  OpenSuperWhisper/Indicator/IndicatorWindow.swift
2026-09-24 16:14:42  OpenSuperWhisperTests/DictationInjectionTests.swift
2026-09-24 16:19:28  OpenSuperWhisperTests/KeyboardSimulatorInterferenceTests.swift
```

**Bundle identity-signed afterwards, `certificate leaf`, not a bare cdhash:**

```
$ codesign -d -r- build/Build/Products/Debug/OpenSuperWhisper.app
designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
```

`dev-run.sh`'s own assertion agrees (`satisfies its Designated Requirement`, identity
"OpenSuperWhisper Local Dev"); the `.dev` bundle id is the worktree's, so a crew build cannot take over the
shipped bundle's grant.

**The reporting path, observed from a running process** (not the app — a probe that compiles
`KeyboardSimulator.swift` and calls the log function, then `log show`):

```
$ log show --last 2m --predicate 'subsystem == "ru.starmel.OpenSuperWhisper"' --style compact
… dictation-injection trusted=1 chars=42 injected=1 events=6 delivered=40 interrupted=focus-changed
… dictation-injection trusted=1 chars=42 injected=1 events=6 delivered=40 interrupted=user-typing
… dictation-injection trusted=1 chars=42 injected=1 events=10 delivered=42 interrupted=none
```

**Probes run while designing the discriminator** (throwaway, `/tmp`, nothing posted into the login session):

```
counter combinedSession keyDown=15944 flagsChanged=1314
counter hidSystem  keyDown=15937
200 frontmostApplication reads: 0.045 ms        200 keyDown counter reads: 0.002 ms
```

The combined-session counter reads 7 key downs above the hardware one on this machine — consistent with the
session table counting events injected at the session level that the hardware table never saw, which is the
assumption the discriminator rests on. A second probe (`CGEventPostToPid(getpid())`, an event handed to this
process alone) moved neither counter, so it neither confirmed nor refuted that assumption for the HID path.

## Unverified, or deliberately left alone

- **The one assumption the typing discriminator rests on is not exercised on this machine:** that an event
  posted to `.cghidEventTap` increments the combined-session key-down counter exactly once. It cannot be
  exercised without posting real keystrokes into the live session, which the headless rule forbids. What is
  verified: the documented meaning of that table (header quote in the code), the combined-vs-hardware
  probe above, and — most importantly — the *harmless* direction of being wrong (a negative surplus is
  silence; only a surplus from somebody else's keystroke can stop a delivery). If it were wrong the other
  way, the arithmetic would still require a surplus, so a healthy delivery still could not stop itself.
- **The window the check covers is the delivery's own turn.** Interference that begins after the last
  checkpoint cannot be acted on by any in-process guard: the loop is over in ~0.16 ms for 1000 characters,
  and the window server then hands the queued events to the target at its own pace. A monitor or an event
  tap would not change that (see above); a delay between chunks would, and delays are explicitly out of
  scope. What the guard does cover is every keystroke or focus change that reaches the session while the
  delivery is posting, and it stops the delivery before the next event goes out.
- **The delivery target is captured when delivery begins, as the brief specifies** — so a switch that
  happens *earlier*, while whisper is still decoding, is not covered: the transcript is typed into whatever
  is frontmost when delivery starts. Capturing at recording start instead would be a different product
  decision and was left alone.
- **A focus change within the same application** (a window, a sheet) is not detected: the check compares the
  frontmost *application*, which is the wording the brief uses. Element-level focus would mean an AX query
  per chunk (each a synchronous IPC round trip with a timeout), which is the kind of cost this task must
  not add.
- **`deliveredCharacters` counts over the normalised text** (CR/CRLF collapsed), while the user-facing
  sentence compares it with the post-processed text's character count. A CR in a transcript would show the
  count off by one per line break; whisper output plus the app's own post-processing does not produce CRs,
  so the discrepancy is theoretical and is documented in the code rather than special-cased.
- **The interference kind is reported, not the offending application's identity** — `DeliveryInterruption`
  stays a plain two-case enum, so the indicator says "another application came to the front" without naming
  it. Naming it would mean carrying a bundle id into the result for a sentence the user has already
  experienced.
- **Not verified, by rule:** the HID event tap and the window server's routing of posted events — the same
  boundary `KeyboardSimulatorDeliveryTests` documents — and anything about the app's live behaviour, since
  no OpenSuperWhisper build was launched, no `open`/`osascript`/`screencapture` was used, and the tests only
  host AppKit views offscreen.
- **The live quiet-case test reads the real session counter**, so a human typing on this machine during its
  ~3 ms window would fail it spuriously. It ran green in the clean-state run.
