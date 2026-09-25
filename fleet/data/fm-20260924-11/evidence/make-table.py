#!/usr/bin/env python3
"""Build the verbatim evidence tables from the measurement runs.

Reads the per-run JSON written by tone-measure.py (old/new prompt × case, model,
latency) and classifies every output with the real TransformGuard
(guard-classify). Writes markdown to stdout:
  * one compact table per model × language (newlines shown as the escape ⏎),
  * a verbatim section for every output that is not a single line.

Usage: make-table.py <run.json> [<run.json> ...]
"""
import json
import subprocess
import sys

GUARD = "/tmp/fm11r/guard-classify"


def guard_verdicts(rows):
    items = [{"tag": f"{i}", "language": r["language"], "input": r["input"],
              "output": r["output"]} for i, r in enumerate(rows)]
    path = "/tmp/fm11r/guard-input.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(items, fh, ensure_ascii=False)
    out = subprocess.run([GUARD, path], capture_output=True, text=True, check=True).stdout
    verdicts = {}
    for line in out.splitlines():
        tag, verdict = line.split("\t", 1)
        verdicts[int(tag)] = verdict
    return [verdicts[i] for i in range(len(rows))]


def inline(text):
    return text.replace("\n", "⏎")


def main():
    rows = []
    for path in sys.argv[1:]:
        rows.extend(json.load(open(path, encoding="utf-8")))
    for row, verdict in zip(rows, guard_verdicts(rows)):
        row["guard"] = verdict

    order = []
    for row in rows:
        if row["case"] not in order:
            order.append(row["case"])
    by = {(r["case"], r["model"], r["variant"]): r for r in rows}
    models = []
    for row in rows:
        if row["model"] not in models:
            models.append(row["model"])

    for model in models:
        languages = []
        for row in rows:
            if row["model"] == model and row["language"] not in languages:
                languages.append(row["language"])
        for language in languages:
            print(f"### {model} — {language}\n")
            print("| case | register | prompt | latency | guard | output |")
            print("|---|---|---|---|---|---|")
            for case in order:
                for variant in ("old", "new"):
                    row = by.get((case, model, variant))
                    if row is None:
                        continue
                    registry = row["tone"]
                    cell = inline(row["output"]).replace("|", "\\|")
                    print(f"| {case} | {registry} | {variant} | {row['seconds']}s | "
                          f"{row['guard']} | `{cell}` |")
            print()

    print("\n=== verbatim, every output that is not one line ===\n")
    for row in rows:
        if "\n" in row["output"]:
            print(f"[{row['model']} / {row['language']} / {row['case']} / {row['tone']} / {row['variant']}] "
                  f"guard: {row['guard']}")
            print(f"  in : {row['input']!r}")
            print(f"  out: {row['output']!r}")
            print()


if __name__ == "__main__":
    main()
