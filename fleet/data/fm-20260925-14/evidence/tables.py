#!/usr/bin/env python3
"""Turn the pairing run's evidence log into the report's markdown tables.

The harness writes one block per arm:

    [pair] <recording> | <arm> | <ms> ms
    [pair]   language X | decoder segments N | ...
    [pair]   sentences S | fragments F | punctuation .a ,b ...
    [pair]   word delta vs the switch-off/none control: -a [...] +b [...] | unchanged BOOL
    [pair]   text: <the transcript>

This joins them back into one row per arm and prints markdown.
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fm2414-pairing-evidence.log"
only = sys.argv[2] if len(sys.argv) > 2 else None

header = re.compile(r"^\[pair\] (?P<rec>.+?) \| (?P<arm>.+?) \| (?P<ms>\d+) ms$")
sentences = re.compile(r"^\[pair\]   sentences (?P<s>\d+) \| fragments \(<=2 words\) (?P<f>\d+) \| punctuation (?P<p>.+)$")
delta = re.compile(r"^\[pair\]   word delta vs the switch-off/none control: -(\d+) \[(.*?)\] \+(\d+) \[(.*?)\] \| unchanged (\w+)$")

rows = []
current = None
for line in open(path, encoding="utf-8"):
    line = line.rstrip("\n")
    m = header.match(line)
    if m:
        current = {
            "rec": m.group("rec"),
            "arm": m.group("arm"),
            "ms": int(m.group("ms")),
            "sentences": "",
            "fragments": "",
            "punctuation": "",
            "removed": "",
            "added": "",
            "unchanged": "",
            "text": "",
        }
        rows.append(current)
        continue
    if current is None:
        continue
    m = sentences.match(line)
    if m:
        current["sentences"] = m.group("s")
        current["fragments"] = m.group("f")
        current["punctuation"] = m.group("p")
        continue
    m = delta.match(line)
    if m:
        current["removed"] = "-{} {}".format(m.group(1), m.group(2)) if m.group(1) != "0" else ""
        current["added"] = "+{} {}".format(m.group(3), m.group(4)) if m.group(3) != "0" else ""
        current["unchanged"] = m.group(5)
        continue
    if line.startswith("[pair]   text: "):
        current["text"] = line[len("[pair]   text: "):]
        continue

for row in rows:
    if only and only not in row["rec"]:
        continue
    delta = " ".join(x for x in [row["removed"], row["added"]] if x) or "—"
    print("| {} | {} | {} s / {} f | {} | {} | {} | {} |".format(
        row["arm"], row["sentences"], row["fragments"], row["punctuation"],
        delta, row["unchanged"], row["ms"], row["text"].replace("|", r"\|")))
