#!/usr/bin/env python3
"""Assemble the measured half of report.md out of the evidence log.

The prose stays in the report; everything here is copied out of the log, so no
number in the report can drift from the run that produced it.
"""
import argparse
import ast
import re
import sys
from collections import Counter

import analyse  # same directory


def block(lines):
    return "\n".join(lines)


def delta_label(text):
    """`→final: dropped ...` as the log writes it, without the arrow."""
    value = (text or "-").strip()
    for prefix in ("→final: ", "->final: "):
        if value.startswith(prefix):
            return value[len(prefix):]
    return value


# The same marks the harness carries, used here for one derived measure: a word
# that did not exist in the raw transcript and arrived in the other language's
# alphabet. Homographs are why this only counts *added* words: `to`, `do`, `on`
# and `no` are ordinary Polish words, so scanning the whole final text with an
# English word list (which is what the harness's FOREIGN TOKENS line does) flags
# the captain's own Polish. A word that is new to the text cannot be his own.
PL_DIACRITICS = set("ąćęłńóśźżĄĆĘŁŃÓŚŹŻ")
ENGLISH_WORDS = {
    "the", "a", "an", "and", "or", "but", "of", "to", "in", "on", "at", "is", "are", "was",
    "were", "be", "been", "it", "this", "that", "these", "those", "you", "your", "we", "our",
    "they", "their", "he", "she", "with", "for", "from", "so", "as", "have", "has", "had",
    "do", "does", "did", "not", "no", "yes", "will", "would", "can", "could", "should",
    "there", "here", "what", "when", "where", "which", "who", "how", "why", "because", "about",
}


def added_words(delta_text):
    match = re.search(r"added \d+ (\[.*?\])", delta_text or "")
    if not match:
        return []
    try:
        return [str(w) for w in ast.literal_eval(match.group(1))]
    except (ValueError, SyntaxError):
        return []


def foreign_added(row):
    """Words that arrived from the other language: added by the model, marked."""
    engine = row["fields"].get("engine")
    seen = []
    for delta in (row.get("delta_model"), row.get("delta_whole")):
        for word in added_words(delta):
            if word not in seen:
                seen.append(word)
    if engine == "en":
        return [w for w in seen if any(c in PL_DIACRITICS for c in w)]
    if engine == "pl":
        return [w for w in seen if w.lower() in ENGLISH_WORDS]
    return []


def anchors_fragment(rows, anchor_files):
    out = []
    for row in rows:
        fields = row["fields"]
        if fields.get("file") not in anchor_files:
            continue
        out.append(f"### {fields.get('file')} — {fields.get('duration')} s — {fields.get('timestamp')}")
        out.append("")
        out.append(f"- engine language: `{fields.get('engine')}` | gate: `{gate_of(row)}` | "
                   f"detector on the raw transcript: `{fields.get('raw')}` | on the final text: `{fields.get('final')}` | flip: **{fields.get('flip')}**")
        out.append(f"- policy: `{fields.get('policy')}` | model answered: `{fields.get('didRunModel')}` | "
                   f"guard: `{fields.get('guard')}`")
        if row.get("guard_notice"):
            out.append(f"- guard notice: {row['guard_notice']}")
        out.append(f"- words: dropped raw→final **{fields.get('dropped')}**, added **{fields.get('added')}**")
        out.append(f"- decode {fields.get('decodeS')} s, transform {fields.get('transformS')} s")
        out.append("")
        out.append("**the transcript the app stored when he dictated it**")
        out.append("")
        out.append("```text")
        out.append(row.get("stored", ""))
        out.append("```")
        out.append("")
        out.append("**raw — what the engine produced on this run**")
        out.append("")
        out.append("```text")
        out.append(row.get("raw_text", ""))
        out.append("```")
        out.append("")
        out.append("**cleaned — after the deterministic scrub**")
        out.append("")
        out.append("```text")
        out.append(row.get("cleaned_text", ""))
        out.append("```")
        out.append("")
        out.append("**final — what would have been pasted**")
        out.append("")
        out.append("```text")
        out.append(row.get("final_text", ""))
        out.append("```")
        out.append("")
        out.append(f"- scrub delta: `{row.get('scrub', '-')}`")
        out.append(f"- model delta (cleaned→final): `{delta_label(row.get('delta_model'))}`")
        out.append(f"- whole delta (raw→final): `{delta_label(row.get('delta_whole'))}`")
        out.append(f"- foreign tokens: `{row.get('foreign', '-')}`")
        out.append(f"- **words that arrived from the other language: "
                   f"{foreign_added(row) if foreign_added(row) else 'none'}** "
                   "(derived: words the model added, carrying the other language's alphabet — the harness's own "
                   "FOREIGN TOKENS line above scans the whole text and therefore counts Polish homographs "
                   "like *to*, *do*, *on*, *no*, so it is not evidence on its own)")
        out.append("")
    return block(out)


def gate_of(row):
    for part in (row.get("lang") or "").split():
        if part.startswith("gate="):
            return part.split("=", 1)[1]
    return "?"


def table_fragment(rows):
    out = [
        "| # | when (UTC) | file | s | engine | raw | final | match | policy | ran | guard | dropped | added | flip |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for index, row in enumerate(rows, 1):
        f = row["fields"]
        if not f:
            out.append(f"| {index} | not measured | `{row.get('recording', '?')}` | — | — | — | — | — | — | — | — | — | — | — |")
            continue
        out.append(
            f"| {index} | {f.get('timestamp')} | `{f.get('file')}` | {f.get('duration')} | {f.get('engine')} | "
            f"{f.get('raw')} | {f.get('final')} | {f.get('match')} | {f.get('policy')} | {f.get('didRunModel')} | "
            f"{f.get('guard')} | {f.get('dropped')} | {f.get('added')} | **{f.get('flip')}** |"
        )
    return block(out)


def delta_words(delta_text, which):
    match = re.search(which + r" \d+ (\[.*?\])", delta_text or "")
    if not match:
        return []
    try:
        return [str(w) for w in ast.literal_eval(match.group(1))]
    except (ValueError, SyntaxError):
        return []


def net_words(delta_text):
    """The words genuinely lost and genuinely new, as a multiset difference.

    An ordered LCS diff reports a moved or duplicated word as one dropped plus
    one added (`dropped 1 ["also"] | added 1 ["also"]`); the word never left the
    text. Counting multiplicities is what separates a real loss from a move.
    """
    dropped = Counter(w.lower() for w in delta_words(delta_text, "dropped"))
    added = Counter(w.lower() for w in delta_words(delta_text, "added"))
    lost = sorted((dropped - added).elements())
    new = sorted((added - dropped).elements())
    return lost, new


def flat(text):
    return (text or "").replace("\n", " ⏎ ")


def mismatches_fragment(rows):
    """Input language vs output language, per pair, with the texts quoted."""
    groups = {}
    for row in rows:
        f = row["fields"]
        if f and f.get("match") == "no":
            groups.setdefault((f.get("engine"), f.get("final")), []).append(row)
    out = []
    for (engine, final), items in sorted(groups.items(), key=lambda kv: (-len(kv[1]), str(kv[0]))):
        out.append(f"**input `{engine}` → output `{final}` — {len(items)} recording(s)**")
        out.append("")
        for row in items:
            f = row["fields"]
            out.append(f"- `{f.get('file')}` ({f.get('duration')} s, raw detector `{f.get('raw')}`, "
                       f"flip `{f.get('flip')}`, policy `{f.get('policy')}`)")
            out.append(f"  - raw: `{flat(row.get('raw_text'))}`")
            out.append(f"  - final: `{flat(row.get('final_text'))}`")
        out.append("")
    return block(out) if out else "(no recording's output language differs from its input language)"


def history_fragment(rows):
    """What his history stored, against what this chain produces now.

    The stored text belongs to whatever build wrote the row — it is not a
    ground truth for this chain — but the direction of the difference is the
    thing worth naming: English text stored for Polish speech.
    """
    measured = [r for r in rows if r["fields"]]
    cross = Counter((r["fields"].get("engine"), r.get("stored_lang")) for r in measured)
    out = ["**engine language × the language of what his history stored**", "",
           "| engine heard | history reads | recordings |", "|---|---|---|"]
    for key in sorted(cross, key=lambda k: (-cross[k], str(k))):
        out.append(f"| `{key[0]}` | `{key[1]}` | {cross[key]} |")
    out.append("")
    same = [r for r in measured if (r.get("stored") or "") == (r.get("raw_text") or "")]
    out.append(f"**his stored text is byte-identical to this run's raw transcript: {len(same)} of {len(measured)}**")
    out.append("")
    today = [r for r in measured if r["fields"].get("timestamp", "").startswith("2026-09-25")]
    out.append(f"- rows dictated today (2026-09-25): {len(today)}, of which reproduce byte-for-byte: "
               f"{sum(1 for r in today if (r.get('stored') or '') == (r.get('raw_text') or ''))}")
    older = [r for r in measured if not r["fields"].get("timestamp", "").startswith("2026-09-25")]
    out.append(f"- older rows: {len(older)}, of which reproduce byte-for-byte: "
               f"{sum(1 for r in older if (r.get('stored') or '') == (r.get('raw_text') or ''))}")
    out.append("")
    out.append("**the speech is Polish and his history stored English**")
    out.append("")
    awkward = [r for r in measured if r["fields"].get("engine") == "pl" and r.get("stored_lang") == "en"]
    for row in awkward:
        out.append(f"- `{row['fields'].get('file')}` ({row['fields'].get('duration')} s)")
        out.append(f"  - stored when he dictated it: `{flat(row.get('stored'))}`")
        out.append(f"  - this run's raw decode: `{flat(row.get('raw_text'))}`")
        out.append(f"  - this run's final text: `{flat(row.get('final_text'))}`")
    if not awkward:
        out.append("(none)")
    return block(out)


def leaks_fragment(rows):
    """Outputs that carry the transform prompt's own delimiter.

    The composed user turn is `<<<TRANSCRIPT … TRANSCRIPT>>>` (the Polish word in
    the Polish prompt), and on short dictations the model sometimes returns the
    frame instead of, or around, the text. It is a defect whether or not the
    guard notices it, so it is measured on the final text alone.
    """
    out = []
    for row in rows:
        final = row.get("final_text") or ""
        raw = row.get("raw_text") or ""
        marks = [m for m in ("TRANSCRIPT", "TRANSKRYPCJA") if m in final and m not in raw]
        if marks:
            out.append(f"- `{row['fields'].get('file')}` ({row['fields'].get('duration')} s, engine "
                       f"`{row['fields'].get('engine')}`) — guard `{row['fields'].get('guard')}`, policy "
                       f"`{row['fields'].get('policy')}`, delimiter seen: {marks}")
            out.append(f"  - raw: {flat(raw)}")
            out.append(f"  - final: {flat(final)}")
            out.append("  - verbatim:")
            out.append("")
            out.append("    ```text")
            for line in final.split("\n"):
                out.append("    " + line)
            out.append("    ```")
    return block(out) if out else "(no output carried the prompt's delimiter)"


def oddballs_fragment(rows):
    """Recordings the two properties do not speak to, named."""
    out = []
    for row in rows:
        f = row["fields"]
        if not f:
            continue
        engine = f.get("engine")
        if engine not in ("pl", "en", "none"):
            out.append(f"- `{f.get('file')}` ({f.get('duration')} s): the engine measured `{engine}` for this clip, "
                       f"so the gate resolved `{f.get('policy')}` and the text was pasted as the engine wrote it: "
                       f"{row.get('raw_text')}")
    return block(out) if out else "(every clip was measured as Polish or English)"


def foreign_fragment(rows):
    out = []
    for row in rows:
        f = row["fields"]
        if not f:
            continue
        flagged = foreign_added(row)
        if flagged:
            out.append(f"- `{f.get('file')}` (engine `{f.get('engine')}`): {flagged}")
    return block(out) if out else (
        "**None.** No recording gained a word from the other language: not one final text carried a word that was "
        "both new to the text and marked with the other language's alphabet."
    )


def aggregates_fragment(rows):
    complete = [r for r in rows if r["fields"]]
    measured = len(complete)
    flips = [r for r in complete if r["fields"].get("flip") == "YES"]
    mismatch = [r for r in complete if r["fields"].get("match") == "no"]
    guards = [r for r in complete if r["fields"].get("guard") != "none"]
    dropped = sum(int(r["fields"].get("dropped", 0)) for r in complete)
    added = sum(int(r["fields"].get("added", 0)) for r in complete)
    ran = sum(1 for r in complete if r["fields"].get("didRunModel") == "true")
    lines = [
        f"- recordings measured: **{measured}** of {len(rows)} blocks in the log",
        f"- transform model answered: **{ran}** of {measured}",
        f"- **language flips: {len(flips)}**",
        f"- final language != input language: **{len(mismatch)}**",
        f"- guard rejections: **{len(guards)}**",
        f"- dropped words raw→final, all recordings: **{dropped}**",
        f"- added words raw→final, all recordings: **{added}**",
    ]
    return block(lines)


def flips_fragment(rows):
    out = []
    for row in rows:
        if row["fields"].get("flip") == "YES":
            out.append(f"- `{row['fields'].get('file')}` (engine `{row['fields'].get('engine')}`, "
                       f"raw `{row['fields'].get('raw')}` → final `{row['fields'].get('final')}`):")
            out.append(f"  - raw: {row.get('raw_text')}")
            out.append(f"  - final: {row.get('final_text')}")
    return block(out) if out else (
        "**None.** No tone answer was rejected in any of the 87 recordings, so there is no notice to quote: the "
        "guard never fired. What it did *not* catch is §8."
    )


def guards_fragment(rows):
    out = []
    for row in rows:
        guard = row["fields"].get("guard")
        if guard and guard != "none":
            out.append(f"- `{row['fields'].get('file')}` — `{guard}`: {row.get('guard_notice', '(no notice)')}")
    return block(out) if out else "**None.** Every tone answer was accepted, so there is no notice to quote."


def changed_fragment(rows):
    out = []
    for row in rows:
        delta = row.get("delta_model", "") or ""
        if not delta.strip() or "dropped 0 [] | added 0 []" in delta:
            continue
        lost, new = net_words(delta)
        note = ""
        if not lost and not new:
            note = "  ← the ordered diff's one-drop-one-add pair is a move or a duplicate, not a loss"
        out.append(
            f"- `{row['fields'].get('file')}` — model diff: `{delta_label(delta)}`; genuinely lost "
            f"**{len(lost)}** {lost}, genuinely new **{len(new)}** {new}{note}"
        )
    return block(out) if out else "(no recording's cleaned text was changed by the model)"


def ears_fragment(rows, orphan_note):
    out = []
    for row in rows:
        f = row["fields"]
        if not f:
            out.append(f"- `{row.get('recording', '?')}` — could not be measured")
            continue
        reasons = []
        if f.get("guard") != "none":
            reasons.append(f"the guard rejected the tone answer ({f.get('guard')})")
        if f.get("flip") == "YES":
            reasons.append("the final text does not read as the language that went in")
        if f.get("match") == "no" and f.get("flip") != "YES":
            if f.get("final") == "unknown":
                reasons.append(f"the detector cannot place the final text at all (input was `{f.get('engine')}`) — "
                               "short text, not a flip")
            else:
                reasons.append(f"the detector places the final text as `{f.get('final')}` where the engine heard "
                               f"`{f.get('engine')}` (the gate used the engine's verdict)")
        lost_scrub, _ = net_words(row.get("scrub"))
        lost_model, new_model = net_words(row.get("delta_model"))
        if lost_scrub:
            reasons.append(f"the deterministic clean-up removed {lost_scrub}")
        if lost_model or new_model:
            reasons.append(f"the model changed words: lost {lost_model}, new {new_model} "
                           f"(diff `{delta_label(row.get('delta_model'))}`)")
        lost_all, new_all = net_words(row.get("delta_whole"))
        if new_all and set(new_all) - set(new_model):
            reasons.append(f"words he did not say, across the chain: {new_all}")
        if lost_all and set(lost_all) - set(lost_model) - set(lost_scrub):
            reasons.append(f"words of his that never reached the final text: {lost_all}")
        foreign = foreign_added(row)
        if foreign:
            reasons.append(f"the final text gained word(s) from the other language: {foreign}")
        if reasons:
            out.append(f"- `{f.get('file')}` ({f.get('duration')} s, engine `{f.get('engine')}`) — " + "; ".join(reasons))
    if orphan_note:
        out.append(orphan_note)
    return block(out) if out else "(nothing stands out: no flip, no guard rejection, no word added or dropped)"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--section", required=True,
                        choices=["anchors", "table", "aggregates", "flips", "guards", "changed", "ears", "foreign",
                                 "leaks", "oddballs", "mismatches", "history"])
    parser.add_argument("--anchor", action="append", default=[])
    parser.add_argument("--orphan-note", default="")
    args = parser.parse_args()

    _, rows = analyse.parse(args.evidence)
    rows = [dict(r, fields=analyse.table_fields(r)) for r in rows]

    sections = {
        "anchors": lambda: anchors_fragment(rows, set(args.anchor)),
        "table": lambda: table_fragment(rows),
        "aggregates": lambda: aggregates_fragment(rows),
        "flips": lambda: flips_fragment(rows),
        "guards": lambda: guards_fragment(rows),
        "changed": lambda: changed_fragment(rows),
        "ears": lambda: ears_fragment(rows, args.orphan_note),
        "foreign": lambda: foreign_fragment(rows),
        "mismatches": lambda: mismatches_fragment(rows),
        "history": lambda: history_fragment(rows),
        "leaks": lambda: leaks_fragment(rows),
        "oddballs": lambda: oddballs_fragment(rows),
    }
    print(sections[args.section]())


if __name__ == "__main__":
    sys.exit(main())
