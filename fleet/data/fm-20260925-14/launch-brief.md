# Task fm-20260925-14 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

*"Also add a feature to ignore pauses… The issue lies solely with polish."* — and, today, the measurement that says
the fix cannot ship alone:

> "Ships OFF, and that is a measured decision: with the decoder prompt this app sends (none) the switch invents a
> fragment in the English control at every silence cap tried (0.2/0.4/0.6/0.8 s)."

The captain was asked which prompt he meant by "write better prompt than…" and chose **both**. This task is the half
that is missing between the two workstreams: pair the pause switch with a deliberate **decoder prompt**, so the
Polish win can be shipped without the English damage, then decide the two defaults on evidence.

## What is already measured — do not re-derive

`fleet/data/fm-20260924-12/{report.md,status.log}` and `/tmp/fm2412-pauses-evidence-iter3.log` hold the four decoder-prompt
arms (empty, the instruction-shaped string an earlier brief attributed to his preferences, and the two deliberate
candidates), the cap sweep and the threshold sweep. Their findings, verbatim in spirit:

- With **no** prompt, switching pauses on invents `based, no,` in the **English** control at **every** cap.
- The **attributed string** is the best of the four for `pl-2`'s words (`-3 +2`: recovers `fork`, `swój`), and for
  English it removes the invention (`-5`: `based, creates, it, no, now`).
- Candidate 1's English counterpart also removes it.
- Threshold `0.6 s` (pauses he talks across are `<= 0.52 s`; boundaries he punctuates are `>= 0.74 s`), cap `0.8 s`.

The pause work itself is landed in the delivery tip (`eaecd28`): `PauseBoundaryPolicy.upstream` is the old audio byte
for byte, `.restored` is the fix, `AppPreferences.longPausesEndSentences` defaults to **false** at `:192`, and
`AppPreferences.initialPrompt` defaults to **empty** at `:193`.

## The task

1. **Measure the pairing, not the parts.** Through the app's own decode path, the captain's own recordings, his
   `ggml-large-v3-turbo` and his settings, for **both languages**: arms = switch on × prompt {none, candidate 1,
   candidate 2, attributed} plus the switch-off controls. For each arm report sentences, fragments, punctuation marks,
   **word-level deltas against the switch-off/none control**, and — the pass/fail criterion — whether the **English
   control stays clean** while the **Polish win survives** (`pl-1` gains its boundary; `pl-2` recovers `Open Super
   Whisper`, `Dodałem`).
2. **Only if a pairing passes**, implement it minimally: `longPausesEndSentences` default → true, and the decoder
   prompt chosen **by the configured whisper language** (the app's `initialPrompt` is one string, so it needs a
   language-aware default, not a per-user value). Keep it small, tested, and reversible in one line each.
3. **Never set his stored preference.** His domain currently holds no `initialPrompt` and no
   `longPausesEndSentences`; a default is for installs that never opened Settings, and the app must not overwrite what
   he later chooses. Say in the report exactly which values a *new* install would get and which of his would change.
4. **Do not use the instruction-shaped string as a shipped default** however well it scores: it is instruction-shaped
   decoder context that this project has just documented as a hallucination trigger, and it was never in the code. If
   it wins the measurement, report that and recommend it for *his* preference, not the default.

## Constraints

- Do not touch the tone rewrite path or `TransformService`/`TransformGuard`/`TransformRuntime` (a sibling crew owns a
  tone-prompt round in `worktrees/OpenSuperWhisper-fm-toneprompt`), the delivery path, or `params.noTimestamps`.
- **Machine contention:** a sibling crew is measuring on `llama-server` (port 1919) right now. Before any build, model
  load or decode, confirm no `xcodebuild` and no `llama-server` is alive, twice a minute apart. Design, write the arms
  and the tests meanwhile; one `sleep 60` loop, never a busy-wait.
- Detach long runs (`python3 -c "subprocess.Popen([...], start_new_session=True, stdout=open(log,'w'), stderr=subprocess.STDOUT)"`;
  macOS has no `setsid`). A harness-backgrounded job is torn down with its session — that already cost this fleet a build.
- Headless only: never launch the app, never `osascript`, never `screencapture`, never a bare `xcodebuild test`
  (it breaks the Accessibility grant), never `pkill`/`killall` anything you did not start. Leave no `llama-server` resident.
- Defaults are user-visible product changes: report them prominently (they go to the captain before anything is published).

## Definition of done

Committed branch only if a pairing passed; the arm tables with verbatim differing outputs and word-level deltas; the
English-clean/Polish-win verdict; the flip (or an evidence-backed refusal) with the exact values a new install gets;
the full suite green with real counts and an identity-signed bundle (`certificate leaf`); `report.md` and a UTC-stamped
`status.log`; an honest list of what remains unverified.

## CAPTAIN'S DECISION — option (a) accepted: pause fix everywhere, with a language-keyed decoder prompt

The crew's verdict was `REFUSED_WITH_EVIDENCE` (no prompt fixes the English audio half; best case a two-word change).
That verdict is accepted as a *measurement*, and the captain was given the three options with their costs. His choice:
**"Pause fix everywhere, English takes a 2-word change."** So the implementation proceeds, with these conditions:

1. **The switch ships ON** (`AppPreferences.longPausesEndSentences` default `true`) and the decoder prompt is chosen by the
   language actually spoken, via the detect-only pre-pass the crew built and measured (+1343/1314 ms against a
   3522/3391 ms decode — 38-39% of a decode, on every dictation whose switch is on and whose user prompt is empty).
2. **The AppPreferences comment must be corrected before it lands.** The preserved draft says the switch "leaves the
   English control word-for-word what the switch off gives" — that is **false**, and it is the crew's own verdict that
   falsifies it (best case `-how -sentence +now +sentences`, present with no prompt and identical across prompts). The
   comment must state the accepted change honestly: English audio takes a two-word change on pause-heavy speech, accepted
   by the captain on 2026-09-25 with the numbers in front of him. A comment that contradicts the measurement it cites is
   worse than no comment.
3. **The criterion test pins the accepted behaviour, not a clean one** — the shipped configuration must be asserted as
   "Polish win present, English delta equal to the measured two-word change", so a future change that silently widens the
   English damage fails the suite.
4. **The Readme and the Settings copy must state the same caveat** in the same words as the comment, including the
   pre-pass cost and that the pause behaviour is keyed to the spoken language.
5. **The ingredients are preserved in the fleet records** (`fleet/data/fm-20260925-14/evidence/`):
   `fm2414-WhisperEngine-wired.swift` (the wired engine: `measureLanguage(of:nThreads:)`, `Self.decoderPrompt(...)`,
   and the gating that keeps a switch-off byte-for-byte upstream), `fm2414-appprefs-switch.txt` (the draft comment —
   **must be corrected per 2**), `fm2414-base-*.swift` (the pre-change copies to diff against),
   `DecoderPromptDefaultTests.swift`, `WhisperPauseBoundaryPairingTests.swift`,
   `WhisperPauseBoundaryPairingTests-phase2.swift`, and the measurement logs `arms-iter*.txt`.
   The crew claimed `evidence/pairing-implementation.patch`; **no such file exists anywhere** — do not go looking for
   it, build from the preserved sources and commit the result.
6. **Nothing is written to his preferences**; only defaults change, and the report must state exactly what a new install
   gets versus what his domain would change to (his `initialPrompt` stays empty unless he sets it; the pre-pass runs on
   the default prompt only).
