#!/usr/bin/env python3
"""Turn the bilingual harness's evidence log into the report's tables.

The harness writes `[bilingual] ...` lines; this reads them back and prints
markdown fragments plus aggregates. Nothing here is a language decision: every
label below is copied out of the log, which is where the app's own
`LanguageDetector` and `TransformPolicy.resolve` wrote it.
"""
import argparse
import json
import re
import sys


def parse(path):
    recordings = []
    current = None
    header = []
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("[bilingual] RECORDING "):
            current = {"lines": [line], "raw": line}
            recordings.append(current)
        elif current is not None:
            current["lines"].append(line)
        else:
            header.append(line)
    # A transcript can carry its own newlines (the model sometimes echoes a
    # delimiter on a line of its own), so a line that does not open a new record
    # field continues the last text value instead of being dropped.
    text_keys = {
        "STORED: ": "stored",
        "RAW: ": "raw_text",
        "CLEANED: ": "cleaned_text",
        "FINAL: ": "final_text",
    }
    for rec in recordings:
        continuation = None
        for line in rec["lines"]:
            if not line.startswith("[bilingual] "):
                if continuation:
                    rec[continuation] = rec[continuation] + "\n" + line
                continue
            body = line[len("[bilingual] "):]
            if body.startswith("RECORDING "):
                rec["recording"] = body[len("RECORDING "):]
            elif body.startswith("DECODE "):
                rec["decode"] = body[len("DECODE "):]
            elif body.startswith("STORED LANG: "):
                rec["stored_lang"] = body[len("STORED LANG: "):]
            elif body.startswith("STORED: "):
                rec["stored"] = body[len("STORED: "):]
            elif body.startswith("RAW: "):
                rec["raw_text"] = body[len("RAW: "):]
            elif body.startswith("SCRUB "):
                rec["scrub"] = body[len("SCRUB "):]
            elif body.startswith("CLEANED: "):
                rec["cleaned_text"] = body[len("CLEANED: "):]
            elif body.startswith("TRANSFORM "):
                rec["transform"] = body[len("TRANSFORM "):]
            elif body.startswith("GUARD NOTICE: "):
                rec["guard_notice"] = body[len("GUARD NOTICE: "):]
            elif body.startswith("FINAL: "):
                rec["final_text"] = body[len("FINAL: "):]
            elif body.startswith("DELTA cleaned"):
                rec["delta_model"] = body[len("DELTA cleaned"):]
            elif body.startswith("DELTA raw"):
                rec["delta_whole"] = body[len("DELTA raw"):]
            elif body.startswith("LANG "):
                rec["lang"] = body[len("LANG "):]
            elif body.startswith("FOREIGN TOKENS"):
                rec["foreign"] = body[len("FOREIGN TOKENS"):]
            elif body.startswith("TABLE | "):
                rec["table"] = body[len("TABLE | "):]
            elif body.startswith("UNDECODABLE | "):
                rec["undecodable"] = body[len("UNDECODABLE | "):]
            elif body.startswith("SKIPPED"):
                rec["skipped"] = body
            continuation = None
            for prefix, key in text_keys.items():
                if body.startswith(prefix):
                    continuation = key
                    break
    return header, recordings


def table_fields(rec):
    if "table" not in rec:
        return {}
    fields = {}
    for part in rec["table"].split(" | "):
        if "=" in part:
            key, value = part.split("=", 1)
            fields[key.strip()] = value.strip()
        else:
            fields.setdefault("_lead", []).append(part.strip())
    lead = fields.pop("_lead", [])
    if len(lead) >= 3:
        fields["timestamp"], fields["file"], fields["duration"] = lead[0], lead[1], lead[2]
    return fields


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("evidence")
    parser.add_argument("--json", dest="json_out")
    parser.add_argument("--table", action="store_true")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--extras", action="store_true")
    args = parser.parse_args()

    header, recordings = parse(args.evidence)
    rows = []
    for rec in recordings:
        row = dict(rec)
        row["fields"] = table_fields(rec)
        rows.append(row)

    if args.table:
        print("| # | when | file | s | engine | raw | final | match | policy | model/ran | guard | dropped | added | flip |")
        print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for index, row in enumerate(rows, 1):
            f = row["fields"]
            if not f:
                print(f"| {index} | — | {row.get('recording', '?')} | — | — | — | — | — | — | — | — | — | — | — |")
                continue
            print(
                "| {i} | {ts} | `{file}` | {dur} | {engine} | {raw} | {final} | {match} | {policy} | "
                "ran={ran} | {guard} | {dropped} | {added} | {flip} |".format(
                    i=index, ts=f.get("timestamp", "?"), file=f.get("file", "?"),
                    dur=f.get("duration", "?"), engine=f.get("engine", "?"),
                    raw=f.get("raw", "?"), final=f.get("final", "?"), match=f.get("match", "?"),
                    policy=f.get("policy", "?"), ran=f.get("didRunModel", "?"),
                    guard=f.get("guard", "?"), dropped=f.get("dropped", "?"),
                    added=f.get("added", "?"), flip=f.get("flip", "?"),
                )
            )

    if args.summary:
        complete = [r for r in rows if r["fields"]]
        flips = [r for r in complete if r["fields"].get("flip") == "YES"]
        mismatches = [r for r in complete if r["fields"].get("match") == "no"]
        guard = [r for r in complete if r["fields"].get("guard") != "none"]
        dropped = sum(int(r["fields"].get("dropped", 0)) for r in complete)
        added = sum(int(r["fields"].get("added", 0)) for r in complete)
        print(f"recordings in log: {len(rows)}")
        print(f"measured: {len(complete)}")
        print(f"language flips: {len(flips)}")
        print(f"output language != input language: {len(mismatches)}")
        print(f"guard rejections: {len(guard)}")
        for r in guard:
            print(f"  {r['fields'].get('file')}: {r['fields'].get('guard')}")
            if "guard_notice" in r:
                print(f"    notice: {r['guard_notice']}")
        print(f"dropped words (raw -> final), total: {dropped}")
        print(f"added words (raw -> final), total: {added}")
        for r in rows:
            if "undecodable" in r:
                print(f"  UNDECODABLE {r['undecodable']}")
            if "skipped" in r:
                print(f"  {r['skipped']}")

    if args.extras:
        complete = [r for r in rows if r["fields"]]
        print("== stored text vs this decode ==")
        same = sum(1 for r in complete if r.get("stored") == r.get("raw_text"))
        print(f"stored == raw: {same} of {len(complete)}")
        census = {}
        for r in rows:
            verdict = r.get("stored_lang")
            if verdict:
                census[verdict] = census.get(verdict, 0) + 1
        print(f"stored-text census: {census}")
        print("== recordings where the model changed the cleaned text ==")
        for r in complete:
            delta = r.get("delta_model", "")
            if re.search(r"dropped [1-9]", delta or "") or re.search(r"added [1-9]", delta or ""):
                print(f"  {r['fields'].get('file')}: {delta}")
        print("== language flips, quoted ==")
        for r in complete:
            if r["fields"].get("flip") == "YES":
                print(f"  {r['fields'].get('file')} ({r['fields'].get('engine')}):")
                print(f"    raw:   {r.get('raw_text', '')}")
                print(f"    final: {r.get('final_text', '')}")
        print("== guard rejections ==")
        for r in complete:
            guard = r["fields"].get("guard")
            if guard and guard != "none":
                print(f"  {r['fields'].get('file')}: {guard}")
                print(f"    notice: {r.get('guard_notice', '(none)')}")
        print("== per-recording deltas ==")
        for r in complete:
            print(
                f"  {r['fields'].get('file')} | scrub: {r.get('scrub', '-')} | model: {r.get('delta_model', '-')}"
                f" | whole: {r.get('delta_whole', '-')}"
            )

    if args.json_out:
        json.dump({"header": header, "rows": rows}, open(args.json_out, "w"), indent=1)


if __name__ == "__main__":
    main()
