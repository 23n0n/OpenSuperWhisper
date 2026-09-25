#!/usr/bin/env python3
"""Mechanical analysis of the measurement runs.

For every (case, model, variant): the app's own LanguageDetector verdict on the
input and on the output, the guard verdict, whether the output is byte-identical
to the input, and the words the output ADDS to / DROPS from the input.

The word comparison is deliberately mechanical (case-folded, diacritics kept):
it is a screen for drift, not a judgement — a legitimate register rewrite may
change a word, and this tool cannot tell that from an invented one. It exists so
that every output in the table has been looked at by something other than a
human skim.

Usage: analyze.py <measure-*.json> ...
"""
import json
import subprocess
import sys

import re

GUARD = "/tmp/fm11r/guard-classify"
VERDICT = "/tmp/fm11r/lv/lang-verdict"


def words(text):
    return [w.lower() for w in re.split(r"[^0-9A-Za-zĄĆĘŁŃÓŚŹŻąćęłńóśźż]+", text) if w]


def detector(texts):
    path = "/tmp/fm11r/verdict-input.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump([{"tag": str(i), "text": t} for i, t in enumerate(texts)], fh)
    out = subprocess.run([VERDICT, path], capture_output=True, text=True, check=True).stdout
    return {int(line.split("\t")[0]): line.split("\t")[1] for line in out.splitlines()}


def guards(rows):
    path = "/tmp/fm11r/guard-input.json"
    with open(path, "w", encoding="utf-8") as fh:
        json.dump([{"tag": str(i), "language": r["language"], "input": r["input"], "output": r["output"]}
                   for i, r in enumerate(rows)], fh, ensure_ascii=False)
    out = subprocess.run([GUARD, path], capture_output=True, text=True, check=True).stdout
    return {int(line.split("\t")[0]): line.split("\t")[1] for line in out.splitlines()}


def main():
    rows = []
    for path in sys.argv[1:]:
        rows.extend(json.load(open(path, encoding="utf-8")))
    g = guards(rows)
    inputs = detector([r["input"] for r in rows])
    outputs = detector([r["output"] for r in rows])

    print("| model | lang | case | tone | prompt | input lang | output lang | guard | unchanged | added | dropped |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for i, r in enumerate(rows):
        inw, outw = words(r["input"]), words(r["output"])
        inset, outset = set(inw), set(outw)
        added = sorted(outset - inset)
        dropped = sorted(inset - outset)
        print(f"| {r['model']} | {r['language']} | {r['case']} | {r['tone']} | {r['variant']} | "
              f"{inputs[i]} | {outputs[i]} | {g[i]} | "
              f"{'yes' if r['output'].strip() == r['input'].strip() else 'no'} | "
              f"{' '.join(added) or '—'} | {' '.join(dropped) or '—'} |")

    print()
    for model in dict.fromkeys(r["model"] for r in rows):
        for language in dict.fromkeys(r["language"] for r in rows if r["model"] == model):
            for variant in ("old", "new"):
                sel = [i for i, r in enumerate(rows)
                       if r["model"] == model and r["language"] == language and r["variant"] == variant]
                if not sel:
                    continue
                rejects = [g[i] for i in sel if g[i] != "ok"]
                flips = [i for i in sel if outputs[i] != inputs[i]]
                print(f"{model} / {language} / {variant}: {len(sel)} outputs, "
                      f"{len(rejects)} guard rejections {rejects if rejects else ''}, "
                      f"{len(flips)} detector-verdict changes "
                      f"{[rows[i]['case'] for i in flips] if flips else ''}")


if __name__ == "__main__":
    main()
