# Addendum to scout fm-20260923-02 — Ant Labs on-device models

Captain follow-up (verbatim): "I specially investigate tiny antlabs models
https://ai-tldr.dev/releases/desert-ant-labs-on-device-models/"

Extend the existing scout report — do NOT start a new one, do NOT touch the repo.

Artifact to update: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260923-02/report.md`

## What to do

1. Fetch that page (and, if it links out, the Ant Labs / Desert Ant Labs model pages — e.g. a Hugging
   Face org/repo or a GitHub release). Start with:
   `curl -sL --max-time 30 "https://ai-tldr.dev/releases/desert-ant-labs-on-device-models/"`
   and strip HTML to text if needed. Follow any linked model repos.
2. Extract, for every model announced there:
   - exact name, parameter count, weight size, and file format/runtime (GGUF, MLX, CoreML, ONNX,
     ExecuTorch, etc.);
   - modalities (text-only? speech-in / text-out? translation?);
   - license;
   - any published latency/throughput or quality numbers;
   - where to download (HF repo id, GitHub release asset) with real byte sizes from the HF API
     (`/api/models/{repo}?blobs=true`) or a `curl -sI` Content-Length.
3. Answer the actual question: **are any of these a better fit than the current leading candidate for
   PL→EN, `gaudi/opus-mt-pl-en-ctranslate2` at 154 MB / ~62 ms median?** Specifically:
   - If an Ant Labs model does speech-in → text-out, note it could collapse STT+translate into one
     model (compare against whisper.cpp `--translate`).
   - If it is text-only translation, compare size/quality/runtime to opus-mt and NLLB.
   - Check whether it supports Polish at all (many tiny multilingual models do not).
4. If a model is small (< ~1.5 GB) and downloadable, and a runtime for it is already on this machine,
   do a real smoke test on the same four Polish sentences from the main brief and record outputs +
   latency. If not runnable here, say so and mark unverified.
5. Add a new section "## Ant Labs (Desert Ant Labs) on-device models" to the report with a table, the
   fetched evidence (quote the page's own claims, marked as vendor claims), the download locations,
   and a clear verdict: better / comparable / worse than opus-mt for this use case, and why.

## Rules

- Evidence-based: separate **vendor claims** (from the page) from **verified here**.
- If the page cannot be fetched or the models cannot be found, say so plainly in the report; do not
  invent specs.
- Read-only: no repo changes, no branch, no PR, no subagents.
- Report the new report path/status in your final message with the decisive fetch output and any
  smoke-test numbers.
