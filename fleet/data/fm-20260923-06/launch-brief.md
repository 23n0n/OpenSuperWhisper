# Task fm-20260923-06 — OpenSuperWhisper — scout

## Captain's intent

Captain (verbatim): "https://desertant.com/models/ear/ check if you can use this model."

Context: the captain wants dictation to be language-aware — English speech must not be sent to the
Polish→English transform, Polish must translate only when the translation toggle is on. Desert Ant
Labs' **Ear** is a candidate spoken-language detector: 99 languages (Polish included), Core ML,
13.7 MB of weights, ~250 ms per identification, Swift SDK (`desert-ant-core`, product `Ear`, 3.1.0).
The question is whether it is actually usable **for our dictation**, where clips are short.

Already read by the first mate (verify, do not re-derive):
- Model page `https://desertant.com/models/ear/`, docs `https://desertant.com/docs/ear/`,
  license `https://license.desertant.com/1.0`.
- Vendor-stated limits: recordings **shorter than thirty seconds get a single window**, "so there is
  nothing to average and the answer is less certain than the number suggests"; Nordic languages are
  not separated; speech under louder music reads ~60%.
- API: `Ear()`, `try await ear.identify(contentsOf: url)` or `identify(samples:sampleRate:)`,
  returning `language`, `confidence`, `isReliable`, `candidates`. Weights download on first use;
  `Ear(directory:)` runs fully offline from weights you ship; `Ear.isDownloaded()`,
  `download(progress:)`.
- License is source-available, not open source (DAL Source-Available 1.0): free below 100,000 monthly
  active devices per platform per model, attribution ("Powered by Desert Ant Labs", linked where
  possible, in an about/settings/licenses surface), no standalone redistribution, and **the SDK sends
  MAD-counting telemetry** which must not be disabled.
- The repo's own acceptance criterion (plan §10) says "Fully offline with local backends; no external
  requests".

## Firstmate spec

Read-only investigation, **no repo changes, no branch**. Deliverable is a self-contained report with
measurements. Work in `/tmp`; a throwaway SwiftPM package there is fine.

1. **Can it run here at all.** Add `desert-ant-core` (from `3.1.0`) to a throwaway SwiftPM executable
   in `/tmp`, build it, and run Ear on a WAV file. Report the exact build/run commands, the resolved
   package version, and any failure. If the package cannot build on this machine, say so with the
   error text and stop that path.
2. **Weights and offline shipping.** Where does the first-use download land on disk, how big is it,
   and does `Ear(directory:)` work with weights copied there (test it, network-independent)? State
   whether the app can ship the weights bundled for a fully offline install, and what the SDK does
   differently in that mode.
3. **Accuracy on our clip lengths — the decisive measurement.** Generate a test set and run Ear on
   every clip:
   - Polish with `say -v Zosia` and English with `say -v Samantha` (both installed), each at roughly
     2 s, 5 s, 10 s and 30 s of speech (4 lengths x 2 languages, >= 2 distinct sentences each).
   - If real dictation recordings exist locally (look under the app's recordings directory, e.g.
     `~/Library/Application Support/OpenSuperWhisper`), include them; they are the most representative
     input. Do not copy them anywhere outside the machine and do not quote their content beyond what
     is needed for the finding.
   - Record per clip: `language`, `confidence`, `isReliable`, the top-2 candidates, and latency.
   - Report accuracy **split by clip length**; the 2-10 s band is what dictation actually produces.
     Call out how often `isReliable` was false, and whether a false `isReliable` would have caused a
     wrong routing decision.
   - Convert formats as needed (`afconvert` is available; ffmpeg if present).
4. **Is a detector even needed from Ear?** On the same test set, measure the free alternative the app
   already contains: whisper.cpp language detection (the fork has a Whisper build under
   `libwhisper/build`; the app calls it through `WhisperEngine`, `params.detectLanguage` is currently
   forced off at `WhisperEngine.swift:351`). Use whatever whisper CLI or tiny Swift harness you can
   stand up in `/tmp`; if that is not practical, say so plainly and give the cost of not having it.
   Also report the transcript-text heuristic option only as a one-line comparison, since the sibling
   scout `fm-20260923-04` owns the gate design (do not design the gate).
5. **Footprint and integration cost.** Model size on disk, resident memory while loaded, load time on
   first use versus warm, and what the app would need to add: SwiftPM dependency, bundled weights,
   attribution surface, and whether the telemetry to count monthly active devices is sent by
   `identify` in normal use (read the SDK source at `github.com/Desert-Ant-Labs/desert-ant-core`,
   and state the exact code path or say it was not verifiable).
6. **Verdict.** A direct answer to the captain's question: usable for this app or not, at which clip
   lengths, on what evidence, and what it would cost (license obligations, telemetry versus the plan's
   "no external requests" criterion, integration work). If the honest answer is "usable only for
   long recordings, not for dictation", say exactly that.

## Delegation guard

You are a crew member. Do not spawn subagents. If you need more depth, say so in your final report.

## Definition of done (scout)

- `data/fm-20260923-06/report.md` — question, method, per-clip measurements with the raw values,
  verdict, and an explicit list of what you did not verify. Every claim traceable to a command you
  ran or a source you read.
- No branch, no commit, nothing modified under `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`.

Report through your final message: outcome, probes run, the verdict, honest failure.
