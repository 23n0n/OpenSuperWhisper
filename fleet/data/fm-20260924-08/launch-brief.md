# Task fm-20260924-08 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

> "Create also streamlining key-presses as the feature."

Asked which aspects he wanted, he chose exactly one: **interference safety — "never corrupt a flow"**. So this
task is about making delivery *safe*, not faster: the chunking, the event count and the throughput stay as
they are (≤20 UTF-16 units per event, no artificial delay), and the paced/typewriter variant and the
trigger-edge timing are **not** in scope. If you find a throughput problem while measuring the interference
behaviour, report it; do not change it here.

## What the delivery path does today (measured baseline, verify it yourself before changing anything)

`OpenSuperWhisper/Utils/KeyboardSimulator.swift`:

- `maxUTF16PerEvent = 20` — the transcript is split into chunks of at most 20 UTF-16 units, and each chunk
  costs one `keyDown` + one `keyUp` carrying the text through `keyboardSetUnicodeString`
  (`KeyboardSimulator.swift:15`, `:115`, `:200-201`). A 200-character dictation is therefore ~10 events a
  half; a paragraph is dozens.
- There is a second, slower path around `:109` for the case where the receiver cannot take the Unicode
  payload.
- `InjectionResult` reports `trusted` and `eventsPosted` (`:23-30`), and the indicator drives it through a
  single closure (`Indicator/IndicatorWindow.swift:65-66`, called at `:420`).

The delivery path never touches the clipboard, needs Accessibility only, and is covered by the
layout-independence work of `fm-20260923-26` (`KeyboardSimulatorDeliveryTests`, which types a payload
carrying CJK, Cyrillic, emoji, Polish diacritics, Return and Tab into a real `NSTextView` and asserts it
arrives character for character). **That test is the contract: it must stay green, unweakened.**

## Required work

1. **Interference safety is the whole feature.** Two failure modes, both real:
   - **The frontmost application changes mid-delivery** (you switch apps, a window steals focus, a
     notification takes it). Today every remaining chunk is posted to whatever is in front — the tail of
     your dictation lands in the wrong window. Required: capture the delivery target when delivery starts,
     check it as delivery proceeds, **stop cleanly** the moment it differs, and report it so the indicator
     can say what happened. Nothing goes to the new frontmost app.
   - **Your own typing interleaves with the injected events.** Today the two streams are mixed
     character-by-character and the result is garbage in both. Required: detect a real user keystroke
     during delivery and stop cleanly rather than interleaving. A user keystroke is not an injected one —
     the injected events are posted by this process and, with Accessibility granted, can be recognised;
     find a discriminator you can defend (a monitor on key events during delivery, the event's own
     provenance, or an equivalent) and say in the report which you chose and why it cannot misfire on the
     empty case.
2. **Report, do not swallow.** Extend `InjectionResult` (or add a sibling type) so the caller learns
   *which* interference ended delivery and how much was delivered, and make the indicator's existing
   reporting path surface it. Keep `trusted` and `eventsPosted` semantics.
3. **Keep the delivery contract exactly as it is** otherwise: ≤20 UTF-16 units per event, `keyboardSetUnicodeString`,
   no artificial delay, the clipboard untouched, Accessibility the only grant, and the payload arriving
   character for character (`KeyboardSimulatorDeliveryTests`, `fm-20260923-26`). Do not change the chunking."<
5. **Keep unchanged:** the clipboard is never read or written, Accessibility remains the only grant,
   dropped-keystroke reporting survives, and the existing delivery semantics (exact text, chunk boundaries
   invisible to the receiver) are preserved.
4. **Do not change throughput.** Measure it once for the record (events and wall time for a 200- and a
   1000-character payload) only so the report can state that the delivery cost is untouched by this task.

## Verification

- The two interference cases, each with a test that produces them: what the test does, what it asserts, and
  what it would have caught. The focus-change case must assert that the *tail* of the transcript is absent
  from the new target, not merely that a flag was set.
- `KeyboardSimulatorDeliveryTests` and the whole suite green: `Scripts/dev-run.sh test` headless from a
  clean state, output at `/tmp/fm2408-suite.log`, bundle identity-signed afterwards
  (`certificate leaf`, never a bare `cdhash`). If a case fails that passes when its class runs alone, say
  so and show both runs — three crews run concurrently today and XCTest parallelizes classes, so
  contention is a real possibility; do not paper over it.
- The interference test, with the quoted assertion and what it would have caught.

## Worktree isolation assertion

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-keypress \
  -b fm/keypress-streamline <delivery tip>
git -C <worktree> -c protocol.file.allow=always submodule update --init --recursive
```

Work in that worktree ONLY. Do not edit `Settings.swift`, `ShortcutManager.swift`,
`ModifierKeyMonitor.swift` or `TranslationService.swift`: two other crews own those files today. If the
indicator needs a visible message for the new outcome, prefer the smallest change to `IndicatorWindow.swift`
over anything new.

## Delegation guard

You are a crew member. Do not spawn subagents. No push, no merge, no branch deletion. **Headless only:**
never launch the app, never `osascript`, never `screencapture`, never `Scripts/dev-run.sh` without a mode
argument.

## Definition of done

Committed branch; both interference modes handled and tested (including the focus-change assertion on the
tail); the outcome reported through the result type and surfaced by the indicator; the delivery contract and
its tests unchanged and green; `fleet/data/fm-20260924-08/report.md` and a
UTC-stamped `status.log` line; an honest note of what you could not measure or deliberately left out.
