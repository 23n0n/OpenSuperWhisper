#!/usr/bin/env python3
"""Compare the arm texts of two pairing runs, arm by arm."""
import re
import sys

def parse(path):
    header = re.compile(r"^\[pair\] (?P<rec>.+?) \| (?P<arm>.+?) \| (?P<ms>\d+) ms$")
    out = {}
    current = None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        m = header.match(line)
        if m:
            current = (m.group("rec"), m.group("arm"))
            out[current] = None
            continue
        if current and line.startswith("[pair]   text: "):
            out[current] = line[len("[pair]   text: "):]
    return out

a, b = parse(sys.argv[1]), parse(sys.argv[2])
shared = sorted(set(a) & set(b))
same = [k for k in shared if a[k] is not None and a[k] == b[k]]
differ = [k for k in shared if a[k] is not None and a[k] != b[k]]
print("arms compared:", len(shared))
print("identical    :", len(same))
print("different    :", len(differ))
for k in differ:
    print("  DIFFER {} | {}\n    iter1: {}\n    iter2: {}".format(k[0], k[1], a[k], b[k]))
only_a = sorted(set(a) - set(b))
only_b = sorted(set(b) - set(a))
print("only in first :", len(only_a), only_a[:5])
print("only in second:", len(only_b), only_b[:5])
