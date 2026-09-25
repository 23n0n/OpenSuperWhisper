# Task fm-20260925-17 — OpenSuperWhisper — ship — mode=local-only

## The defect, measured on the captain's own recordings (not a hypothesis)

`fleet/data/fm-20260925-15/report.md` §8, from a full-library run through the app's own decode + transform chain
(87 recordings, his live configuration):

> The composed user turn is `<<<TRANSCRIPT … TRANSCRIPT>>>` (the Polish word in the Polish prompt). On short
> dictations the model sometimes returns that frame instead of, or around, the text — and the guard's rules
> (assistant frame, label, stub, language flip) do not see it, so it reaches the pasted text.

**Five recordings, verbatim finals** (durations 1.8-2.8 s, engine `en`/`pl`, guard reported *none*):

| recording | raw | final (what reached his text) |
|---|---|---|
| `0D5AA205-…` | `<redacted: captain dictation, 38 chars>` | `<redacted: captain dictation, 38 chars>  \nTRANSCRIPT` |
| `4B614AE1-…` | `Now speaking English` | `Now speaking English \nTRANSCRIPT` |
| `DC187FEA-…` | (short Polish) | `<<<TRANSKRYPCJA\nfont\nTRANSKRYPCJA>>>` |
| `880D1B22-…` | `Use of pickguard` | `Use of pickguard \nTRANSCRIPT` |
| `81B50264-…` | (short) | `<<<TRANSCRIPT\nContinue with fixes.\nTRANSCRIPT>>>` |

Two things make this worth fixing rather than documenting: the marker is **localised** (the Polish prompt emits
`TRANSKRYPCJA`, so a check for the English word alone misses half the cases), and the guard is the one place in this
codebase whose entire purpose is to keep the model's scaffolding out of the captain's text.

## The fix

1. Add one rejection to `OpenSuperWhisper/TransformGuard.swift` for the **prompt frame in the output**, matching what
   was measured:
   - a bracketed marker: `<<<` or `>>>` followed by/attached to an all-caps word (`<<<TRANSCRIPT`, `TRANSKRYPCJA>>>`),
   - or a *line* whose content, stripped of the existing markup handling, is exactly an all-caps marker word
     (`TRANSCRIPT`, `TRANSKRYPCJA`).
2. **It must not fire on a legitimate dictation.** A sentence containing the lowercase word — `I need the transcript by
   Friday.` or `Send the transcript.` — must pass untouched; pin those as negative cases. Only the all-caps marker, or a
   bracketed one, counts.
3. The rejection joins the existing enum with its own honest notice (the model returned the transcript markers instead
   of the text, so the user's own words were used instead) and the existing behaviour applies: the raw transcript is
   delivered, not the scaffolded answer.
4. Tests: the five measured strings verbatim as positive cases (including the Polish one), the negative cases above, and
   the case where the marker is mid-answer rather than at the end.

## Constraints

- Do not change the prompt wording, the routing, the warm-up, or anything under `WhisperEngine`/`AppPreferences`/
  `Settings` — a sibling crew is editing exactly those for the pause pairing (`worktrees/OpenSuperWhisper-fm-pauseimpl`).
  Your surface is `TransformGuard.swift`, its tests, and — if a notice must reach the report — the same report path the
  guard already uses.
- Work only in `worktrees/OpenSuperWhisper-fm-frame`. Submodules must be initialised before the first build
  (`git -c protocol.file.allow=always submodule update --init --recursive`); a crew already lost time to that.
- Headless only: never launch the app, never `osascript`, never `screencapture`, never `Scripts/dev-run.sh` without a
  mode argument, never a bare `xcodebuild test`, never `pkill`/`killall` anything you did not start.
- Detach long runs (`python3 -c "subprocess.Popen([...], start_new_session=True, ...)"`, logs `/tmp/fm2417-*.log`).
- Machine contention: check twice, a minute apart, that no `xcodebuild` and no `llama-server` is alive before starting a
  build or the suite. Provider is off-peak.

## Definition of done

Committed branch; the five measured strings rejected with the new notice and the negative cases untouched, proven by
tests; the full suite green from a clean state with real counts and an identity-signed bundle (`certificate leaf`);
`fleet/data/fm-20260925-17/report.md` quoting the five before/after cases and the rule as implemented; a UTC-stamped
`status.log` line; an honest note on what the rule cannot catch (a marker a model invents later, in a spelling neither
prompt uses).
