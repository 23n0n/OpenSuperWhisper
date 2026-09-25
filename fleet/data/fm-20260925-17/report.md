# fm-20260925-17 — the prompt frame the guard could not see is now rejected

Worktree `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-frame`, branch
`fm/frame-guard`, base `d960bb7` (the delivery tip), commit `d0bf5d4`. Headless throughout: no app
launch, no `osascript`, no `screencapture`, no bare `xcodebuild test`.

**Task:** `fleet/data/fm-20260925-17/launch-brief.md`. **Defect measured by** `fm-20260925-15/report.md` §8, from
the full-library run through the app's own decode + transform chain (87 recordings, the captain's live
configuration): the transform's own user-turn delimiter came back as the answer on five short dictations, none of
the guard's four rules could see it, and it reached his pasted text.

## Verdict

The rule exists, it fires on all five measured finals, and it costs the two negative cases nothing. The change is
`OpenSuperWhisper/TransformGuard.swift` (one new rejection case, one new rule, notices and prose), its two test
files, and the `Readme.md` sections that enumerate the guard's rules. Nothing about the prompt, the routing, the
warm-up, `WhisperEngine`, `AppPreferences` or `Settings` was touched — the sibling crew's surface
(`worktrees/OpenSuperWhisper-fm-pauseimpl`) is untouched by this branch. Committed as `d0bf5d4` and landed into the
delivery branch by Main. **The evidence behind those sentences is the standalone probe of the committed guard
described under Verification; the XCTest suite for this commit has not been run** (see the same section — the only
project run on this branch died on a compile error before the fix, and the rerun was still gated when the task
stopped). The suite is batched onto the merged tip by Main.

## The rule, as implemented

`TransformGuard.rejection(of:for:language:)` now checks the frame **first**, before the assistant frame, the
label, the stub and the language flip:

```swift
if let marker = promptMarker(in: answer) {
    return .promptMarker(marker)
}
```

and the rule itself reads every line of the answer:

```swift
static func promptMarker(in answer: String) -> String? {
    for line in answer.components(separatedBy: .newlines) {
        let stripped = stripMarkup(line).trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { continue }
        if promptMarkerWords.contains(stripped) { return stripped }
        if let bracketed = bracketedPromptMarker(in: stripped) { return bracketed }
    }
    return nil
}
```

with

```swift
static let promptMarkerWords: [String] = ["TRANSCRIPT", "TRANSKRYPCJA"]
static let promptMarkerMinimumLetters = 2
```

Two shapes are matched, and they are the two that were measured:

- **a line whose whole content is an all-caps marker word** — `promptMarkerWords.contains(stripped)`, checked
  after the existing `stripMarkup` handling, so a bulleted `- TRANSCRIPT` or a quoted `"TRANSCRIPT"` line is the
  same marker. This is the shape of three of the five measured finals — `0D5AA205`, `4B614AE1` and `880D1B22`
  end `\nTRANSCRIPT` on a line of its own — and it is the case sensitivity, not the whitespace, that keeps
  `I need the transcript by Friday.` out;
- **an all-caps word attached to `<<<` or `>>>`** — `bracketedPromptMarker(in:)` walks the line, consumes the
  whole bracket run, and takes the word after an opening bracket or before a closing one
  (`<<<TRANSCRIPT`, `TRANSKRYPCJA>>>`). It accepts any all-caps word there, not just the two the prompt names:
  the brackets cannot arrive in dictated speech, and a model that invents a different all-caps word inside them
  has still returned the frame rather than the text.

**What keeps the negatives safe.** The bare-line shape is case-sensitive and demands the *whole* line: the
ordinary lowercase word in `I need the transcript by Friday.` or `Send the transcript.` is the user's own
sentence and is delivered, as is a line that merely starts with a capital (`Transcript`). The prompt writes
`TRANSCRIPT` in both languages, but a Polish dictation was measured coming back with `TRANSKRYPCJA`, so both
spellings are listed.

**On rejection nothing else changed.** The rejection joins the existing enum with its own notice —

> The model returned the transform prompt's own marker ("TRANSCRIPT") instead of the text, so your own words were
> used instead.

— and the existing behaviour applies untouched: the raw transcript is delivered, `AppErrorCenter` reports
"Tone rewrite was not used" with that notice, and `DictationReport.guardRejection` records it, so the surface that
shows the last dictation says *answer rejected, transcript kept*. That path is exercised by a new service-level
test, not just by the guard's own unit tests.

## The five measured cases, before and after

Raw strings are the evidence log's bytes (`fleet/data/fm-20260925-15/evidence/decode-evidence.log`), including
the two trailing spaces case 1 carries. "Before" is the `guard` column that run printed; "after" is
`TransformGuard.rejection(of:for:language:)` on this branch, from the test that feeds each string in verbatim.

| recording | dictation (raw) | the final that reached his text (before) | guard before | guard after |
|---|---|---|---|---|
| `0D5AA205-7FC2-4F53-AA7B-C2E17A3A33B6` | `<redacted: captain dictation, 38 chars>` | `<redacted: captain dictation, 38 chars>  \nTRANSCRIPT` | none | `.promptMarker("TRANSCRIPT")` |
| `4B614AE1-E769-4776-859E-1BD969B3F8E2` | `Now speaking English` | `Now speaking English\nTRANSCRIPT` | none | `.promptMarker("TRANSCRIPT")` |
| `DC187FEA-7E34-4EA3-A8A7-D38482BCD2B5` | `font` (engine `pl`) | `<<<TRANSKRYPCJA\nfont\nTRANSKRYPCJA>>>` | none | `.promptMarker("TRANSKRYPCJA")` |
| `880D1B22-6A4C-4BD6-B718-06D01F55AEBD` | `Use of pickguard` | `Use of pickguard\nTRANSCRIPT` | none | `.promptMarker("TRANSCRIPT")` |
| `81B50264-1B06-4D5A-95BA-1A88821B90CC` | `Continue with fixes.` | `<<<TRANSCRIPT\nContinue with fixes.\nTRANSCRIPT>>>` | none | `.promptMarker("TRANSCRIPT")` |

The Polish case is the one a check for the English word alone would have missed: the model answered a Polish
dictation with the Polish marker.

**Mid-answer**, pinned separately because the rule reads every line rather than the last one:

- `Now speaking English\nTRANSCRIPT\nAnd the microphone works.` → `.promptMarker("TRANSCRIPT")`
- `The plan <<<TRANSCRIPT is ready.` → `.promptMarker("TRANSCRIPT")`

## The negatives, pinned

Both required negatives pass with an answer that *differs* from the dictation, so the rule — not the
"answer is the dictation" shortcut — is what leaves them alone:

- `I need the transcript by Friday.` for `i need the transcript by friday if possible` → delivered, untouched
- `Send the transcript.` for `send the transcript please` → delivered, untouched
- `Transcript\nof the meeting.` for `transcript of the meeting` → delivered (a capitalised line is not the marker)

**The whole library, counted** (`evidence/decode-evidence.log`): the all-caps marker appears in exactly the five
recordings above — `grep` for a `TRANSCRIPT`/`TRANSKRYPCJA` add finds five blocks and nothing else. One further
recording (`8BF93E24-77F8-4F88-BB9B-9E908308CEC5`, 4.9 s, Polish) gained the *capitalised* word
`added 1 ["Transkrypcja"]`; the rule leaves that alone on purpose, because a capitalised word is a word a rewrite
may legitimately produce and the measured leaks are all-caps.

## A residual false positive, documented and deliberately not changed

The bracketed shape accepts **any** all-caps word beside a bracket, not only the two the prompt names. That
widening is deliberate (a model that invents `<<<SEGMENT` has still returned a frame rather than the text), and it
costs this: a technical dictation is rejected when an all-caps acronym sits **attached** to a bracket. Measured on
the committed guard (same probe and hash as above — these are the probe's own verdicts, not a reading of the code):

| answer | verdict |
|---|---|
| `CPU>GPU` | rejected `.promptMarker("CPU")` |
| `GPU>CPU` | rejected `.promptMarker("GPU")` |
| `CPU<GPU` | rejected `.promptMarker("GPU")` |
| `The limit is 5<GPU` | rejected `.promptMarker("GPU")` |
| `The limit is 5<OK` | rejected `.promptMarker("OK")` — the ≥2-letter guard does not save a two-letter acronym |
| `See GPU>CPU on the chart.` | rejected `.promptMarker("GPU")` |
| `move CPU<RAM` | rejected `.promptMarker("RAM")` |
| `CPU > GPU` | **delivered** — the word must be *attached* to the bracket; a space stops the scan |
| `GPU > CPU` | **delivered** |
| `Read chapter <A>` | delivered (one letter, under the minimum) |
| `email <bob>` | delivered (not all-caps) |
| `VALUES: 10<20` | delivered (not letters) |

**The cost when it fires** is the raw transcript with the notice: the tone rewrite is silently not applied, nothing
is corrupted and no data is lost. It needs an acronym glued to a bracket in one line — the spaced comparison form
(`CPU > GPU`, `GPU > CPU`) does **not** trigger it, which is the shape a spoken technical sentence is far more
likely to produce.

**The precise tightening, if it is ever wanted** (not done here — the brief specifies the widening and Main has
ruled it stays): restrict the bracketed match to `promptMarkerWords`, or require a bracket run of two or more.
Either one still catches every measured case, because all three measured frames carry `<<<`/`>>>` and the prompt's
own words (`<<<TRANSCRIPT`, `<<<TRANSKRYPCJA`, `TRANSKRYPCJA>>>`); the first would also stop the rule catching an
invented marker word inside brackets, which is the price of closing this hole.

## What this rule still cannot catch

Stated rather than implied:

- **A marker in a spelling neither prompt uses, arriving as a bare line.** Only `TRANSCRIPT`/`TRANSKRYPCJA` are
  listed. A model that later invents `AUDIO`, `TEXT`, or a Polish synonym as a standalone all-caps line would
  pass — unless it arrives inside `<<<`/`>>>`, which *is* caught for any all-caps word (at the cost documented in
  the section above). Widening the bare-line shape to "any all-caps line" was rejected: it
  would reject a dictation of an acronym, a heading or a name.
- **An all-caps marker word inside a sentence.** `Make sure the TRANSCRIPT marker is gone from the output.` is a
  real sentence and is delivered; the measured leaks are all the marker standing alone on its own line.
- **A marker decorated with punctuation.** The bare-line shape compares the whole stripped line, and `stripMarkup`
  removes markdown emphasis, bullets and surrounding quotes but not punctuation: on the probe, `**TRANSCRIPT**`,
  `"TRANSCRIPT"` and `- TRANSCRIPT` **are** rejected, while `TRANSCRIPT.` and `TRANSCRIPT:` are delivered. A period
  or a colon on the marker is not one of the measured shapes, and no proof here says the model produces one.
- **Clean-up-only dictations are not guarded at all.** The guard is the tone path's (`policy.promptTone != nil`,
  `fm-20260924-11`); all five measured cases ran tone + clean-up, so they are covered, but a clean-up-only install
  has no guard on this class. Changing that is a routing decision this task was told not to make.
- Unchanged from before: subtle content drift (an article dropped, a noun invented) is text the guard does not
  judge.

## Verification

### What was executed, and what was not

**Executed: the committed guard itself, on a standalone probe.** `OpenSuperWhisper/TransformGuard.swift` was copied
byte-for-byte out of commit `d0bf5d4` (`shasum -a 256` = `d908deed66b52b0a89ad06f46940bebf52f234f2bbd35c36d571d66648116d8d`,
the same hash as `git show HEAD:OpenSuperWhisper/TransformGuard.swift`) and compiled with the real
`LanguageDetector.swift` and the real `TransformLanguage` enum next to it (`swiftc -Onone`, no project build, no
`xcodebuild`, no model, probe at `/tmp/fm2417-probe`). Its verdicts, verbatim:

```text
REJECTED promptMarker(TRANSCRIPT)      [0D5AA205] "<redacted: captain dictation, 38 chars>  \nTRANSCRIPT"
REJECTED promptMarker(TRANSCRIPT)      [4B614AE1] "Now speaking English\nTRANSCRIPT"
REJECTED promptMarker(TRANSKRYPCJA)    [DC187FEA] "<<<TRANSKRYPCJA\nfont\nTRANSKRYPCJA>>>"
REJECTED promptMarker(TRANSCRIPT)      [880D1B22] "Use of pickguard\nTRANSCRIPT"
REJECTED promptMarker(TRANSCRIPT)      [81B50264] "<<<TRANSCRIPT\nContinue with fixes.\nTRANSCRIPT>>>"
REJECTED promptMarker(TRANSCRIPT)      [bare mid] "Now speaking English\nTRANSCRIPT\nAnd the microphone works."
REJECTED promptMarker(TRANSCRIPT)      [inline bracket] "The plan <<<TRANSCRIPT is ready."
delivered                              [lowercase 1] "I need the transcript by Friday."
delivered                              [lowercase 2] "Send the transcript."
delivered                              [capitalised line] "Transcript\nof the meeting."
delivered                              [all-caps in sentence] "Make sure the TRANSCRIPT marker is gone from the output."
```

**Not executed: the XCTest cases on this commit.** The only project run on `fm/frame-guard` was the pre-fix
attempt, which died on the compile error below (exit 65) — the tests added in
`OpenSuperWhisperTests/TransformGuardTests.swift` and `OpenSuperWhisperTests/TransformServiceTests.swift` have not
been run, and the gated rerun (`/tmp/fm2417-gate.sh` → `/tmp/fm2417-guard2.log`) was still waiting for the machine
when the task stopped. **Say this plainly: the tests are written and unproven, and the probe above is what is
proven.** Main landed `d0bf5d4` into the delivery branch (`delivery == main`) and batched the full clean-state
suite onto the merged tip (the pause work plus this), so the suite counts and the identity-signed bundle
(`certificate leaf`) belong to that run, not to this worktree — this report does not claim them.

### A note on reading `dev-run.sh` failures

`Scripts/dev-run.sh` captures the app build into a variable
(`BUILD_OUTPUT=$(xcodebuild … build 2>&1)`) under `set -euo pipefail`, so when that `xcodebuild` fails the script
exits at the assignment with xcodebuild's status **before** it prints the captured output: the run's log simply
stops after `Building OpenSuperWhisper… / worktree build: bundle id …`, with no error and no exit line of its own.
That is what the first attempt of this task looked like, and it is what a compile error in the new code looks
like. The reason lives in `build/Logs/Build/*.xcactivitylog`:

```text
gunzip -c build/Logs/Build/<newest>.xcactivitylog | strings | grep -E "error:"
/…/OpenSuperWhisper/TransformGuard.swift:258:59: error: cannot convert value of type 'Int' to expected argument
type 'String.Index'
```

(The first attempt's real failure: `String.insert(_:at:)` takes a `String.Index`, and the bracket reader was
building `String` directly — fixed by collecting `[Character]` and reversing.) Worth knowing for any crew here:
the absence of output is not the absence of a failure.

## Integrity

- The prompt wording, the routing, the warm-up, `WhisperEngine`, `AppPreferences` and `Settings` are untouched;
  `git show --stat` on the commit lists exactly the guard, its two test files and the Readme.
- Nothing was launched, no model file was moved, copied or deleted, no preference was written, and the sibling
  worktree was not touched.
- Machine gate: no `xcodebuild` and no `llama-server` alive twice, one minute apart (0/0 at
  `2026-09-25T09:37:28Z` and `0/0` at `2026-09-25T09:38:22Z`) before the first build was launched at
  `2026-09-25T09:39:32Z`, and the same two-observation gate before the second attempt (`0/0` at
  `2026-09-25T09:51:24Z` and `0/0` at `2026-09-25T09:52:24Z`). **Both gates crossed the sibling crew's window** and
  that is worth naming rather than hiding: `Fm14Impl` (a separate worktree, `OpenSuperWhisper-fm-pauseimpl`) went
  live at `09:39:30Z`, two seconds before this task's first launch, and again at `09:48Z` for its full clean suite,
  whose first ten minutes are the native engines — during which no `xcodebuild` exists, so the gate's own test
  ("no `xcodebuild`") reads the machine as free while a heavy build is under way. Separate worktrees, separate
  `-derivedDataPath build`, separate `SourcePackages`, so no output is shared and nothing of theirs was touched or
  killed; the two runs competed for CPU. A stricter gate (watching `dev-run.sh`/`cargo`/`cmake` too) is the fix,
  but it is not this task's to make, and the rule as written was followed exactly.
- Native submodules were initialised before the first build
  (`git -c protocol.file.allow=always submodule update --init --recursive`), and this worktree needed none of the
  repairs the sibling worktree did (no stale module `gitdir:` files, no stale `libllama`/`libwhisper`
  `CMakeCache.txt`) — its native configure ran from scratch.
