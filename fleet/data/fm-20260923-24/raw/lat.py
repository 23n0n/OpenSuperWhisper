#!/usr/bin/env python3
"""fm-24: warm-latency stats per measured TSV (cols: n, seconds, http, input, output)."""
import glob, statistics, sys

def stats(path):
    ns, ts = [], []
    for line in open(path):
        p = line.rstrip("\n").split("\t")
        if len(p) < 3:
            continue
        ns.append(int(p[0])); ts.append(float(p[1]))
    if not ts:
        return None
    return ns, ts

paths = sys.argv[1:] or sorted(glob.glob("/tmp/fm24/out_*.tsv"))
print(f"{'file':52s} {'n':>3s} {'mean':>6s} {'min':>6s} {'max':>6s}  {'all':s}")
for p in paths:
    r = stats(p)
    if not r:
        continue
    ns, ts = r
    alls = " ".join(f"{t:.2f}" for t in ts)
    print(f"{p.split('/')[-1]:52s} {len(ts):3d} {statistics.mean(ts):6.2f} {min(ts):6.2f} {max(ts):6.2f}  {alls}")
