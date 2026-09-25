# fm-20260925-14 — does a deliberate decoder prompt pair with the pause switch?

Branch `fm/pause-pairing`, worktree
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pairing`, base `eaecd28` (the
delivery tip, which already holds the pause work). Headless throughout: no app launch, no `osascript`, no
`screencapture`, no bare `xcodebuild test`, every run detached with a log under `/tmp/fm2414-*`.

**STATUS: PLACEHOLDER**

## What was asked, and what was already measured

The pause fix is landed with the switch **off**, because with the decoder prompt this app sent — none — the switch
on invented a fragment in the English control at every cap tried (`fleet/data/fm-20260924-12/report.md`). This task
is the half between the two workstreams: pair the switch with a deliberate decoder prompt, and flip the two
defaults only if on the captain's own recordings, through the app's own decode path, **the English control stays
clean and the Polish win survives**.

Re-derived from `fm-20260924-12` (not re-measured here): with no prompt at all the switch on turns the English
control into "Basically, now it creates,. **based, no,** now it creates a sentences…" (where the switch off is
"Basically how it creates a sentence…"), while the Polish win is real: `pl-1` gains the boundary at the 0.74 s
pause ("…inną drogą. Bo tu chodzi…"), `pl-2` recovers **Open Super Whisper** and **Dodałem**.

## The arm matrix, through the app's own decode path

`OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests.swift` (opt-in twice over: `OSW_TEST_CAPTAIN_RECORDINGS`
and a multilingual model; with either missing the cases skip, as CI runs them). His three recordings — `pl-1`
(12.1 s), `pl-2` (23.3 s) and the English control (33.0 s) — decoded through `transcribeAudioDetailed`, his
`ggml-large-v3-turbo`, his settings (greedy, temperature 0, no-speech 0.6, blank suppression on, no timestamps),
with the VAD the app ships.

Per recording, every arm decoded once:

* `off / none (control)` — the switch off with no prompt: **the app as it ships today**, upstream's 0.1 s of zeros
  at every pause. Every arm below is a word-level delta against it.
* `on / none`, `on / attributed`, `on / c1 (pl)`, `on / c2 (pl)`, `on / c3 (pl, no commas)`, `on / c1 EN` — the
  switch on with each decoder prompt.
* `off / attributed`, `off / c1 (pl)`, `off / c2 (pl)`, `off / c3 (pl, no commas)`, `off / c1 EN` — the prompt on
  its own, so a change can be attributed to the prompt rather than to the switch.
* `on / none (repeated)` — the determinism anchor.

The prompts, verbatim:

* *attributed* — the instruction-shaped string an earlier brief reported finding in his preferences
  ("You are a transcriber. Your role is just to clean up the text and make it look pretty and attractive. Do not
  change the sense of the sentences."). It is **not** in the app and this brief forbids shipping it as a default.
* *c1 (pl)* — "Dobra, jeszcze raz: wysłałem raport w poniedziałek, ale Anna nie odpowiedziała. Możesz to
  sprawdzić?"
* *c2 (pl)* — "Tak, zgadza się. Kiedy? Nie wiem, ale sprawdzę to jutro."
* *c3 (pl, no commas)* — "Zrobiłem to wczoraj. Sprawdzę to jutro. Możesz na to spojrzeć? Nie ma problemu." — a
  knock-out probe for the comma hypothesis: c1 and c2 are comma-heavy and on `pl-1` both add commas and trade the
  boundary away, so a comma-free prompt tells "instruction" apart from "comma priming".
* *c1 EN* — "Okay, one more time: I sent the report on Monday, but Anna hasn't replied. Can you check?"

Every prompt was run against **both** languages, because the pairing has to hold for whatever audio arrives: a
prompt's language is not the audio's language in a bilingual install.

### PLACEHOLDER: the arm tables

### PLACEHOLDER: the pairing table

## PLACEHOLDER: the verdict

## What a new install would get, and what of the captain's changes

Both are defaults for installs that never opened Settings; **his stored preferences are not written** — the app
only reads, and the values below were read out of his domain, not set.

| | a new install | the captain's install today | after this change |
|---|---|---|---|
| `longPausesEndSentences` | absent → **on** | **absent** (`defaults read ru.starmel.OpenSuperWhisper longPausesEndSentences` → "Could not find key") | reads **on**: his dictation starts keeping long pauses |
| `initialPrompt` | absent → "" stored, and the language's default is sent | `""` (empty) | still `""` in his domain; his Polish dictations send the Polish default, his English ones the English default |
| `whisperLanguage` | absent | `pl` (a removed key nothing reads) | untouched, still unread |

PLACEHOLDER: the pre-pass cost and the user-visible effects.

## Verification

PLACEHOLDER: the focused runs, the full suite with real counts, the identity-signed bundle.

## Unverified, or deliberately left alone

PLACEHOLDER
