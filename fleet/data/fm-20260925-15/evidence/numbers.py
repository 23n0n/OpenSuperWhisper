#!/usr/bin/env python3
"""The numbers the report quotes, re-derived from the raw evidence blocks.

Deliberately independent of build-report.py: this walks the same log with its own
small parser so an error in one path cannot hide in both.
"""
import ast
import re
import sys
from collections import Counter

import analyse

ANCHORS = {
    "9039BAB0-CBA2-49B2-82E1-432FF7B94589.wav": "pl anchor (117.8 s)",
    "29EA0AEA-06B0-4FE1-B189-18A21822F35A.wav": "en anchor (131.1 s)",
    "FD7B4C64-0AD7-4431-84D6-6F9EAFC77512.wav": "en short (29.0 s)",
}


def words_of(delta_text, which):
    match = re.search(which + r" \d+ (\[.*?\])", delta_text or "")
    if not match:
        return []
    try:
        return [str(w) for w in ast.literal_eval(match.group(1))]
    except (ValueError, SyntaxError):
        return []


def counts(delta_text):
    dropped = Counter(w.lower() for w in words_of(delta_text, "dropped"))
    added = Counter(w.lower() for w in words_of(delta_text, "added"))
    return dropped - added, added - dropped  # genuinely lost, genuinely new


def main():
    _, raw_rows = analyse.parse("decode-evidence.log")
    rows = [dict(r, fields=analyse.table_fields(r)) for r in raw_rows]
    measured = [r for r in rows if r["fields"]]
    out = []

    def say(line=""):
        out.append(line)

    say(f"recordings in the log: {len(rows)} | measured: {len(measured)}")
    summary = [r for r in raw_rows if "SUMMARY" in " ".join(r["lines"])]
    say()

    say("== the two anchors, and the short English clip beside them ==")
    for row in measured:
        f = row["fields"]
        if f.get("file") not in ANCHORS:
            continue
        lost, new = counts(row.get("delta_whole"))
        say(f"{ANCHORS[f.get('file')]} | {f.get('timestamp')} | {f.get('duration')} s")
        say(f"  engine={f.get('engine')} detector raw={f.get('raw')} final={f.get('final')} "
            f"flip={f.get('flip')} policy={f.get('policy')} guard={f.get('guard')}")
        say(f"  raw->final dropped {f.get('dropped')} added {f.get('added')} | genuinely lost {sum(lost.values())} "
            f"{sorted(lost.elements())} | genuinely new {sum(new.values())} {sorted(new.elements())}")
        say(f"  scrub: {row.get('scrub')}")
        say(f"  model: {row.get('delta_model')}")
    say()

    say("== library aggregates ==")
    total_dropped = sum(int(r["fields"].get("dropped", 0)) for r in measured)
    total_added = sum(int(r["fields"].get("added", 0)) for r in measured)
    scrub_drop = sum(len(words_of(r.get("scrub"), "dropped")) for r in measured)
    model_drop = sum(len(words_of(r.get("delta_model"), "dropped")) for r in measured)
    model_add = sum(len(words_of(r.get("delta_model"), "added")) for r in measured)
    lost_total = Counter()
    new_total = Counter()
    for row in measured:
        lost, new = counts(row.get("delta_whole"))
        lost_total += lost
        new_total += new
    say(f"ordered diff raw->final: dropped {total_dropped}, added {total_added}")
    say(f"  of the drops, by the deterministic scrub: {scrub_drop}")
    say(f"  model diff (cleaned->final): dropped {model_drop}, added {model_add}")
    say(f"multiset difference raw->final: genuinely lost {sum(lost_total.values())} {dict(lost_total)}")
    say(f"                                genuinely new  {sum(new_total.values())} {dict(new_total)}")
    net = new_total - lost_total
    say(f"net word change across the library: {sum(net.values())} {dict(net)}")
    say()

    say("== how many recordings each stage changed ==")
    say(f"scrub changed something: {sum(1 for r in measured if words_of(r.get('scrub'), 'dropped'))}")
    say(f"model changed something: {sum(1 for r in measured if r.get('delta_model') and 'dropped 0 [] | added 0 []' not in r['delta_model'])}")
    say(f"final differs from the raw transcript at all: "
        f"{sum(1 for r in measured if (r.get('final_text') or '') != (r.get('raw_text') or ''))}")
    say(f"final is byte-identical to the raw transcript: "
        f"{sum(1 for r in measured if (r.get('final_text') or '') == (r.get('raw_text') or ''))}")
    say()

    say("== language ==")
    say(f"language flips (detector raw vs final, both placed): "
        f"{sum(1 for r in measured if r['fields'].get('flip') == 'YES')}")
    say(f"output language differs from the input language: "
        f"{sum(1 for r in measured if r['fields'].get('match') == 'no')}")
    for row in measured:
        f = row["fields"]
        if f.get("match") == "no":
            say(f"  {f.get('file')} {f.get('duration')} s engine={f.get('engine')} raw={f.get('raw')} "
                f"final={f.get('final')} flip={f.get('flip')}")
            say(f"     raw  : {row.get('raw_text')!r}")
            say(f"     final: {row.get('final_text')!r}")
    say()
    engine_counts = Counter(r["fields"].get("engine") for r in measured)
    say(f"engine language across the library: {dict(engine_counts)}")
    disagree = [r for r in measured
                if r["fields"].get("engine") in ("pl", "en")
                and r["fields"].get("raw") in ("pl", "en")
                and r["fields"].get("engine") != r["fields"].get("raw")]
    say(f"engine and detector disagree on the raw transcript: {len(disagree)}")
    for row in disagree:
        f = row["fields"]
        say(f"  {f.get('file')} engine={f.get('engine')} detector={f.get('raw')} :: {row.get('raw_text')!r}")
    say()

    say("== guard ==")
    guards = [r for r in measured if r["fields"].get("guard") != "none"]
    say(f"guard rejections: {len(guards)}")
    for row in guards:
        say(f"  {row['fields'].get('file')}: {row['fields'].get('guard')} — {row.get('guard_notice')}")
    say()

    say("== the transform's own prompt delimiter in the output (not caught by the guard) ==")
    leaks = [r for r in measured
             if any(m in (r.get("final_text") or "") and m not in (r.get("raw_text") or "")
                    for m in ("TRANSCRIPT", "TRANSKRYPCJA"))]
    say(f"recordings: {len(leaks)}")
    for row in leaks:
        say(f"  {row['fields'].get('file')} {row['fields'].get('duration')} s guard={row['fields'].get('guard')}")
        say(f"     raw  : {row.get('raw_text')!r}")
        say(f"     final: {row.get('final_text')!r}")
    say()

    say("== calls that did not run ==")
    for row in measured:
        f = row["fields"]
        if f.get("didRunModel") == "false":
            say(f"  {f.get('file')} {f.get('duration')} s engine={f.get('engine')} policy={f.get('policy')} "
                f":: {row.get('raw_text')!r}")

    text = "\n".join(out)
    print(text)
    with open("numbers.txt", "w", encoding="utf-8") as handle:
        handle.write(text + "\n")


if __name__ == "__main__":
    sys.exit(main())
