# fork-0.1.0-3 — tagged release, notes only, no installer

**This is a source marker. There is no download** — see *Why no binary* at the end. The code is `main` in
[23n0n/OpenSuperWhisper](https://github.com/23n0n/OpenSuperWhisper); build it with `Scripts/dev-run.sh build`, and the
Readme's *Building locally* section is the entry point.

## What changed in this tag

**Tone rewrites now run on one model for both languages.** Polish and English tone go through a single route — the larger
8B when it is installed — with a deterministic guard that refuses an answer which is an acknowledgement, a label, a
fragment, a language flip, or the prompt's own delimiter instead of the rewritten text. When it refuses, the raw
transcript is delivered **with the reason**, so "tone did nothing" is never silent again.

**Polish is instructed in Polish.** The tone prompt for a Polish dictation is written in Polish, which is measurably
better on the model used here (28 Polish cases, two draws each: untouched 25 vs 15, invented a word 1 vs 2, lost a word
1 vs 4, and 0 of 28 answers differ between identical runs where the previous prompt drifted in 2).

**A long pause ends the sentence.** The VAD timings the decoder was throwing away are used: a pause of at least 0.6 s
between two speech segments is kept as real silence (up to 0.8 s) and closes the sentence the decoder left open. The
threshold comes from the measured band — pauses spoken *across* are ≤ 0.52 s, boundaries *punctuated* are ≥ 0.74 s.
On by default.

**Two words on English audio, accepted and pinned.** With the pause fix on, pause-heavy English speech changes by exactly
`-how -sentence +now +sentences` against the switch off. It is the switch's own audio half: it is there with no decoder
prompt at all and identical for two different prompts, so no prompt can remove it. A test asserts the Polish win and that
English delta so a future change cannot quietly widen it. The switch costs a detect-only language pre-pass (~1.3 s
against a ~3.5 s decode) and only when it is on with no custom prompt.

**The prompt's own marker can no longer reach your text.** Five of the captain's own recordings came back with the
transform's `<<<TRANSCRIPT … TRANSCRIPT>>>` delimiter — in Polish, `<<<TRANSKRYPCJA` — pasted around their words, and
none of the guard's existing rules could see it.

## Measured on the captain's own voice

87 recordings through the app's own chain, his configuration: **0 language flips**; Polish stays Polish, English stays
English, nothing is translated. The 117.8 s Polish dictation is **word-identical** to its raw transcript with punctuation
added; the 131.1 s English one is **byte-identical**. 47 of 87 finals are byte-identical to the raw transcript.

## Why no binary

`dist/*.pkg` is unsigned (`pkgutil --check-signature`: *no signature*; `spctl -a -t install`: *rejected*), and the app
inside is signed by a **locally created** identity with no team identifier — the Accessibility grant is matched against
that certificate's designated requirement, which exists only on the machine that created it. Installing it elsewhere
would be refused by Gatekeeper and could never hold a stable grant. A genuinely publishable binary needs an Apple
Developer ID and notarisation; that would also change the designated requirement and break the existing local grant until
it is re-granted. Not done here, deliberately.

## Verification

The delivery branch carried a full-suite run on the merged tip before this tag; the exact commit and its counts are in
`fleet/data/FLEET-STATE.md`. The delta between the verified commit and this tag is documentation only — two Readme
sentences, corrected so *"no binary releases"* is what the file actually means.
