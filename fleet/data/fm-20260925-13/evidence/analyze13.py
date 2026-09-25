#!/usr/bin/env python3
"""Mechanical screen + guard verdicts for the fm-20260925-13 tone round.

Every answer is classified with the REAL TransformGuard.swift and the real
LanguageDetector.swift (compiled from the worktree head, see bin/), and the same
mechanical word screen the landed measurement used: case-folded, diacritics kept,
words only (numbers are not words).

Usage: analyze13.py <measure.json> [...]
"""
import json
import re
import subprocess
import sys
import statistics

HERE = "/".join(__file__.split("/")[:-1])
GUARD = f"{HERE}/bin/guard-classify"
VERDICT = f"{HERE}/bin/lang-verdict"

VARIANTS = ["control", "winner", "pl-instruction", "pl-no-echo", "pl-no-echo-named", "example", "selfcheck"]


def words(text):
    return [w.lower() for w in re.split(r"[^0-9A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]+", text) if w]


def detector(texts):
    path = "/tmp/fm13-verdict-input.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump([{"tag": str(i), "text": t} for i, t in enumerate(texts)], fh)
    out = subprocess.run([VERDICT, path], capture_output=True, text=True, check=True).stdout
    return {int(line.split("\t")[0]): line.split("\t")[1] for line in out.splitlines()}


def guards(rows):
    path = "/tmp/fm13-guard-input.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump([{"tag": str(i), "language": r["language"], "input": r["input"], "output": r["output"]}
                   for i, r in enumerate(rows)], fh, ensure_ascii=False)
    out = subprocess.run([GUARD, path], capture_output=True, text=True, check=True).stdout
    return {int(line.split("\t")[0]): line.split("\t")[1] for line in out.splitlines()}


def classify(rows):
    g = guards(rows)
    inputs = detector([r["input"] for r in rows])
    outputs = detector([r["output"] for r in rows])
    for i, r in enumerate(rows):
        inw, outw = words(r["input"]), words(r["output"])
        r["guard"] = g[i]
        r["input_lang"] = inputs[i]
        r["output_lang"] = outputs[i]
        r["unchanged"] = r["output"].strip() == r["input"].strip()
        r["added"] = sorted(set(outw) - set(inw))
        r["dropped"] = sorted(set(inw) - set(outw))


def tally(rows, label):
    unchanged = sum(1 for r in rows if r["unchanged"])
    invented = sum(1 for r in rows if r["added"])
    lost = sum(1 for r in rows if r["dropped"])
    rejects = [r for r in rows if r["guard"] != "ok"]
    flips = [r for r in rows if r["output_lang"] != r["input_lang"]]
    lat = [r["seconds"] for r in rows]
    print(f"{label}: n={len(rows)} unchanged={unchanged} invented={invented} lost={lost} "
          f"guard_rejects={len(rejects)} detector_flips={len(flips)} "
          f"latency median={statistics.median(lat):.2f}s "
          f"({min(lat):.2f}-{max(lat):.2f})")
    for r in rejects:
        print(f"    REJECT {r['case']} {r['tone']} {r['variant']} r{r['run']}: {r['guard']}")
    return dict(n=len(rows), unchanged=unchanged, invented=invented, lost=lost,
                rejects=len(rejects), flips=len(flips), median=round(statistics.median(lat), 2),
                low=min(lat), high=max(lat))


def main():
    rows = []
    for path in sys.argv[1:]:
        rows.extend(json.load(open(path, encoding="utf-8")))
    classify(rows)
    variants = [v for v in VARIANTS if any(r["variant"] == v for r in rows)]
    runs = sorted({r["run"] for r in rows})

    print("\n## per variant")
    summary = {}
    for v in variants:
        for run in runs:
            sel = [r for r in rows if r["variant"] == v and r["run"] == run]
            if sel:
                summary[f"{v}/r{run}"] = tally(sel, f"{v} run{run}")

    print("\n## per variant, both runs pooled")
    for v in variants:
        tally([r for r in rows if r["variant"] == v], v)

    print("\n## determinism: identical prompt, two runs")
    for v in variants:
        diff = 0
        cases = sorted({r["case"] for r in rows if r["variant"] == v})
        for case in cases:
            outs = [r["output"] for r in rows if r["variant"] == v and r["case"] == case]
            if len(outs) > 1 and len(set(outs)) > 1:
                diff += 1
        print(f"{v}: {diff} of {len(cases)} answers differ between run1 and run2")

    print("\n## per-case table (run 1): case | tone | variant | guard | unchanged | added | dropped | output")
    for r in rows:
        if r["run"] != 1:
            continue
        print(f"| {r['case']} | {r['tone']} | {r['variant']} | {r['guard']} | "
              f"{'yes' if r['unchanged'] else 'no'} | {' '.join(r['added']) or '—'} | "
              f"{' '.join(r['dropped']) or '—'} | `{r['output']}` |")

    print("\n## where a candidate differs from the control (run 1), verbatim")
    for v in variants:
        if v == "control":
            continue
        for case in sorted({r["case"] for r in rows}):
            c = [r for r in rows if r["variant"] == "control" and r["case"] == case and r["run"] == 1]
            o = [r for r in rows if r["variant"] == v and r["case"] == case and r["run"] == 1]
            if not c or not o or c[0]["output"] == o[0]["output"]:
                continue
            print(f"[{case} / {c[0]['tone']}]")
            print(f"  control : {c[0]['output']}")
            print(f"  {v:9s}: {o[0]['output']}")
            print(f"  control added={c[0]['added']} dropped={c[0]['dropped']} | "
                  f"{v} added={o[0]['added']} dropped={o[0]['dropped']}")


if __name__ == "__main__":
    main()
