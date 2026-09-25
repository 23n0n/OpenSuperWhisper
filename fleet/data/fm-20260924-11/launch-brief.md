# Task fm-20260924-11 — OpenSuperWhisper — ship — mode=local-only

## Captain's intent

> "Tone transcription is not working as intended. Probably it is a matter of a system prompt. Because all other
> things are working properly, the whole mechanism or pipeline is working. The only thing that is lacking is the
> correct output. So prepare a system prompt for a tone change."

Then, on the evidence produced before this brief: **"Both tasks A and B should be completed."**

**A** — run the tone transform on the 8B for **both** languages while it is installed.
**B** — adopt the tightened tone prompt **and** add a deterministic guard, so the failure he hit cannot reach the
transcript.

## What was measured before this brief (do not re-derive; extend it)

Full method and tables: `fleet/data/fm-20260924-10/tone-prompt.md`. Harness: `/tmp/tone-ab.py`, real weights via
`llama-server` with the app's sampling (temperature 0.2, top-k 40, top-p 0.95, min-p 0.05,
`chat_template_kwargs.enable_thinking = false`).

Seven adversarial cases (imperative, question, "already formal", run-on, numbers, filler) × three prompt variants:

- **The model is the dominant variable.** Every failure a user would notice on `qwen2.5-1.5b-instruct-q4_k_m` —
  an added `"Sure,"`, a preamble (`"Sure, here's the rewritten text in a casual register:"`), dropped articles
  (`"invoice number is 423, amount is…"`), an invented noun (`"the product"`), and at temperature 0 an outright
  `"Understood."` instead of a rewrite — **is absent on `qwen3-8b-q4_k_m` with the same prompt.**
- **Temperature 0 is worse than 0.2** on both models (the small one collapses into chat; the 8B becomes verbose).
  Keep 0.2.
- **The new prompt is equal-or-better than the current one on the 8B, not a win by itself on the 1.5B**
  (it introduced the preamble there). That is why A and B ship together: the prompt makes good output likelier,
  the 8B makes it possible, the guard makes the bad case impossible.
- **Casual and neutral legitimately return the text unchanged** when it is already in that register. The card's
  copy must not promise a visible difference in that case.

## Firstmate spec

### A — routing

1. A tone transform (`.tone` and `.cleanUpWithTone` policies) uses **`qwen3-8b-q4_k_m` when it is installed,
   regardless of the language**; `qwen2.5-1.5b-instruct-q4_k_m` otherwise. Clean-up alone keeps the language-based
   preference the cutover landed (Polish → 8B when installed, English → 1.5B), because grammar repair does not need
   the larger model.
2. Nothing is refused and nothing is substituted silently: the Settings card states, per job, which model will run
   and whether the 8B is present — extending the sentence the cutover already added.
3. The 10-minute idle unload and the record-start warm-up stay exactly as they are; the card keeps stating the RAM
   cost of the model in use (~5.6 GB wired for the 8B).

### B — prompt and guard

4. Replace the tone wording in `TransformService.systemPrompt` with the version in
   `fleet/data/fm-20260924-10/tone-prompt.md`: register defined by *what may change*, an explicit
   "you are not an assistant" rule, the must-not-change list (facts, speaker, order, completeness, language), and
   the output rules (no preamble/labels/markdown, keep line breaks, already-in-register ⇒ unchanged, fragment ⇒
   unchanged). Keep `/no_think` and the reasoning strip.
5. Frame the user turn instead of sending the transcript bare:
   `Rewrite this dictated text in a {TONE} register …` + `<<<TRANSCRIPT … TRANSCRIPT>>>`. Dictated text is often an
   imperative or a question, and an unframed turn makes the model obey or answer it.
6. **Guard, deterministic and tested.** A tone result is rejected and the raw transcript is delivered instead —
   with a visible notice, using the same reporting path the injection interruptions use — when it:
   - opens with an assistant frame or acknowledgement (`Sure`, `Certainly`, `Of course`, `Understood`, `Here is`,
     `Here's`, `I've`, `Oczywiście`, `Oto`, `Jasne`), or contains `rewritten text` / `rewritten version` /
     a `Register:`/`Output:` label line;
   - is a stub: the input carries a sentence but the output is a small fragment of it (threshold chosen from the
     measured cases, stated in the report);
   - **flips language**: the output contains no word of the language the input was written in while the input had
     content words (checked with the app's own `LanguageDetector`).
   The guard works on text alone — no model call, no second pass — so it cannot itself hallucinate. It must not fire
   on the legitimate cases: an already-in-register output equal to the input, a genuinely short dictation, a
   fragment, or a text mixing a technical term from another language.
7. Keep the honest limits visible in the report: the guard catches frames, stubs and language flips; it cannot
   catch subtle content drift (an article dropped, a noun invented). Those are the prompt's and the 8B's job.

## Verification

- Re-run the seven adversarial cases in **both languages** on the 8B with the new prompt and the framing, and quote
  input → output; state explicitly which of the measured 1.5B failures the guard would have caught, by feeding those
  exact strings through it.
- Prove the guard's negative cases too: already-in-register text unchanged, a two-word dictation, a fragment, and a
  mixed-language technical term — all delivered as-is, none flagged.
- Prove A by execution: with the 8B installed, an English tone transform runs on `qwen3-8b-q4_k_m`; with it renamed
  away, the same transform runs on the 1.5B and the card says so; clean-up alone on English still runs the 1.5B.
- `Scripts/dev-run.sh test` headless from a clean state, green, output at `/tmp/fm2411-suite.log`; bundle
  identity-signed afterwards (`certificate leaf`, never a bare `cdhash`).
- The Readme's tone and model-routing text updated to match; the card copy updated.

## Worktree isolation assertion

```
git -C /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo worktree add \
  /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-tone \
  -b fm/tone-output <delivery tip>
git -C <worktree> -c protocol.file.allow=always submodule update --init --recursive
```

Work in that worktree ONLY. Do not touch `Utils/KeyboardSimulator.swift` or the injection path in
`Indicator/IndicatorWindow.swift` (delivery safety landed there today).

## Delegation guard

You are a crew member. Do not spawn subagents. No push, no merge, no branch deletion. **Headless only:** never launch
the app, never `osascript`, never `screencapture`, never `Scripts/dev-run.sh` without a mode argument. `llama-server`
from Homebrew is available and is how the measurements above were taken.

## Definition of done

Committed branch; A and B both implemented; the measured tables for both languages; the guard's positive and negative
cases proven by tests, including the exact failure strings measured on the small model; the suite green; the card and
Readme matching the new behaviour; `fleet/data/fm-20260924-11/report.md` and a UTC-stamped `status.log` line; an honest
note of what the guard cannot catch and anything else left unverified.
