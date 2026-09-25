# Task fm-20260925-15 — OpenSuperWhisper — ship (measurement) — mode=local-only

## Captain's authorisation (verbatim)

> "I check if my recordings are in good condition, and it's okay to test them."

He recorded the material for this himself. The library holds **86 completed recordings** (30 Polish, 56 English by
heuristic on the stored text), and the two anchors are the ones he made *for this purpose*:

| when | length | language | opening of the stored text |
|---|---|---|---|
| 2026-09-25 09:03:01 | **117.8 s** | Polish | "Ok, więc teraz muszę przez dwie minuty coś dyktować w języku polskim…" |
| 2026-09-25 09:06:40 | **131.1 s** | English | "Okay, now I'm recording in English. So we can have some reference material…" |
| 2026-09-25 09:07:32 | 29.0 s | English | "I check if my recordings are okay, if it's good to test with them." |

## What this settles

The captain's original requirement, in his words: *"The app should also understand if I'm using Polish or English,
because I'm sometimes speaking English and I don't need always a translate feature… sometimes use Polish without
translate."* Two properties, on his own voice, with no cherry-picking:

1. **Language in → language out.** Polish dictation comes back Polish, English comes back English, and **nothing is
   translated anywhere in the chain**.
2. **The transform does not damage it.** With the transform as configured (tone and/or clean-up), the output keeps the
   speaker's words: measure invented and dropped words per recording, and report every guard rejection with its notice.

## Method

- Decode each recording through the **app's own engine path**, exactly as `fm-20260924-12` did: its harness is in the
  delivery tip you are based on (`OpenSuperWhisperTests/CaptainRecordingPauseBoundaryTests.swift`, driven by
  `TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS`, `TEST_RUNNER_OSW_TEST_MULTILINGUAL_MODEL`,
  `TEST_RUNNER_OSW_TEST_EVIDENCE`). Reuse it; extend it only where it cannot answer the two properties.
- Language decision must use the app's own `LanguageDetector`, not a heuristic of your own.
- **The two anchors first, in full:** raw transcript, detected language of input and of output, the transform's output,
  every word added or dropped against the raw transcript, the guard's verdict and notice, and any single word that
  arrived from the other language. Verbatim, no summarising.
- **Then the whole library** (all recordings whose audio is present): per recording — detected language, whether the
  output language matches, the guard's verdict, added/dropped word counts. A per-recording table, plus aggregates.
- **Bounded runtime:** if decoding all 86 exceeds a sane budget, do the anchors in full, then as many others as fit,
  and say exactly which were skipped and why. Never silently sample.
- **No ground truth exists** for his clips, so say so: sense-fidelity beyond word-level deltas and language
  consistency is his ears, not yours. End with a short list of recordings worth his listening, with the reason.

## Constraints

- Own worktree only: `worktrees/OpenSuperWhisper-fm-bilingual` (branch `fm/bilingual-check` @ `eaecd28`). Do not touch
  the other worktrees (`fm-toneprompt`, `fm-pairing`) or the primary checkout.
- **Do not change application behaviour.** This task measures. If you find a real defect, report it with evidence and
  leave the code alone — a fix is a separate decision for me and the captain.
- Machine contention: two sibling crews are measuring (`llama-server`). Before any build, model load or decode,
  confirm no `xcodebuild` and no `llama-server` is alive, twice a minute apart.
- Detach long runs (`python3 -c "subprocess.Popen([...], start_new_session=True, ...)"`, log to `/tmp/fm2415-*.log`;
  macOS has no `setsid`). A harness-backgrounded job is torn down with its session — that already cost this fleet a build.
- Headless only: never launch the app, never `osascript`, never `screencapture`, never a bare `xcodebuild test`,
  never `pkill`/`killall` anything you did not start. Leave no `llama-server` resident.

## Definition of done

The two anchors' full verbatim texts and deltas; the library-wide per-recording table with aggregates; the language
flip count (with every flip quoted); the guard rejections with notices; the list of clips worth the captain's ear; raw
evidence under `fleet/data/fm-20260925-15/evidence/`; `report.md` and a UTC-stamped `status.log`; an honest list of
what remains unverified — including any recording you could not decode.
