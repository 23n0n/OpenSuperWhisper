# Addendum 2 to scout fm-20260923-02 — Desert Ant Labs exact catalog page

Captain follow-up (verbatim): "Here is the exact page of our tiny models lab
https://desertant.com/models/"

The first addendum fetched this page as a secondary source and concluded none of the 18 Ant Labs
models perform PL→EN translation. The captain is now pointing at the catalog page itself, which may
mean something was missed. Re-examine that EXACT page, thoroughly, and reconcile.

Artifact to update: `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260923-02/report.md` (extend the
existing "## Ant Labs (Desert Ant Labs) on-device models" section; do not replace the report).

## What to do

1. Fetch `https://desertant.com/models/` directly and capture the full rendered content (the page may
   load data from a JSON/JS endpoint — also try `curl -sL` on any linked `catalog.json`, `models.json`,
   API route, or the docs). Save the raw text you relied on into the report as quoted evidence.
2. Enumerate EVERY model on that page, one row each: name, task/purpose, parameter count, on-disk
   size, runtime/format, languages, license, and — explicitly — whether it can produce English text
   from Polish input.
3. Look specifically for anything translation-adjacent the first pass may have skipped:
   - a model whose task is "translate"/"translation"/"NMT"/"seq2seq";
   - a text model (e.g. a small instruct/LLM) that could be prompted to translate even if translation
     is not its headline task — if so, note its size and whether a runtime exists here;
   - a speech model that outputs English for non-English input (speech translation), or a pipeline
     the docs describe (e.g. ASR + a language step) that yields English;
   - any "translate" subcommand in their CLI/docs.
   Quote the page for every such claim.
4. If a model genuinely can translate PL→EN and is < ~1.5 GB with a runtime available here, run the
   same four Polish sentences and record outputs + latency. Otherwise state why translation is not
   possible with that model (e.g. ASR-only, classification-only, emits same language).
5. Reconcile with the prior verdict: if translation IS possible and was missed, say so prominently and
   correct the table; if it is truly not, restate the verdict with the stronger direct-page evidence
   (including the exact list of tasks the page advertises).

## Rules

- Separate **vendor claims** from **verified here**.
- If the page cannot be fetched, say so plainly; do not invent specs.
- Read-only: no repo changes, no branch, no PR, no subagents.
- Report the decisive evidence (quoted page lines) and any smoke-test numbers in your final message.
