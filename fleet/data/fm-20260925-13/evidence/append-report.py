#!/usr/bin/env python3
"""Append the measured tables for one run to the report, computed from the raw
JSON so nothing is transcribed by hand.

Usage: append-report.py <report.md> <measure.json> <heading> <variant...>
"""
import importlib.util
import json
import statistics
import sys

HERE = "/".join(__file__.split("/")[:-1])
_spec = importlib.util.spec_from_file_location("a13", f"{HERE}/analyze13.py")
a13 = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(a13)


def main():
    report, path, heading = sys.argv[1:4]
    variants = sys.argv[4:]
    rows = json.load(open(path, encoding="utf-8"))
    a13.classify(rows)
    runs = sorted({r["run"] for r in rows})

    out = [f"\n{heading}\n"]
    out.append(f"Raw answers: `evidence/{path.split('/')[-1]}`; classification tool: "
               f"`evidence/analyze13.py` over the real guard/detector; 28 cases per variant per run.\n")
    out.append("| variant | run | untouched | invented a word | lost a word | guard rejects | "
               "latency median (min–max) |")
    out.append("|---|---|---|---|---|---|---|")
    for v in variants:
        for run in runs:
            sel = [r for r in rows if r["variant"] == v and r["run"] == run]
            if not sel:
                continue
            lat = [r["seconds"] for r in sel]
            out.append(f"| `{v}` | {run} | {sum(1 for r in sel if r['unchanged'])} "
                       f"| {sum(1 for r in sel if r['added'])} | {sum(1 for r in sel if r['dropped'])} "
                       f"| {sum(1 for r in sel if r['guard'] != 'ok')} "
                       f"| {statistics.median(lat):.2f} s ({min(lat):.2f}–{max(lat):.2f}) |")
    out.append("")
    out.append("| variant | run-to-run determinism (identical prompt, two runs) |")
    out.append("|---|---|")
    for v in variants:
        cases = sorted({r["case"] for r in rows if r["variant"] == v})
        diff = [c for c in cases
                if len({r["output"] for r in rows if r["variant"] == v and r["case"] == c}) > 1]
        out.append(f"| `{v}` | {len(diff)} of {len(cases)} answers differ |")
    out.append("")

    out.append("**Which cases failed, and with which words.**\n")
    for v in variants:
        out.append(f"`{v}`:\n")
        for run in runs:
            sel = [r for r in rows if r["variant"] == v and r["run"] == run]
            inv = ", ".join(f"{r['case']} ({' '.join(r['added'])})" for r in sel if r["added"]) or "—"
            los = ", ".join(f"{r['case']} ({' '.join(r['dropped'])})" for r in sel if r["dropped"]) or "—"
            out.append(f"* run {run} — invented: {inv}; lost: {los}")
        out.append("")

    out.append("**Every case where a candidate's answer differs from the control's, verbatim.**\n")
    for v in variants:
        if v == "control":
            continue
        printed = False
        for case in sorted({r["case"] for r in rows}):
            for run in runs:
                c = [r for r in rows if r["variant"] == "control" and r["case"] == case and r["run"] == run]
                o = [r for r in rows if r["variant"] == v and r["case"] == case and r["run"] == run]
                if not c or not o or c[0]["output"] == o[0]["output"]:
                    continue
                printed = True
                out.append(f"* `{case}` / {c[0]['tone']} / run {run}:")
                out.append(f"  * control: `{c[0]['output']!r}`")
                out.append(f"  * `{v}`: `{o[0]['output']!r}`")
        if not printed:
            out.append(f"* `{v}`: identical to the control on every case in every run.")
        out.append("")

    with open(report, "a", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print(f"appended {heading!r} to {report}")


if __name__ == "__main__":
    main()
