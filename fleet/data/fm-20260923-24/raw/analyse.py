#!/usr/bin/env python3
"""fm-24: find the load/unload STEPS in a wired-memory trace.

Single before/after samples on this machine are worthless: the baseline drifts
by ~±0.5 GB (and up to 2 GB over minutes) because other agents are building.
A model load, by contrast, is a step in one or two samples. So report the
biggest jumps and the local level on either side of each.
"""
import sys, statistics

def load(path):
    rows = []
    for line in open(path):
        parts = line.split()
        if len(parts) != 3:
            continue
        rows.append((float(parts[0]), int(parts[2]) / 1073741824.0))
    return rows

def main(path, launch=None, stop=None):
    rows = load(path)
    if not rows:
        print(f"{path}: empty")
        return
    print(f"== {path} ==")
    print(f"samples={len(rows)}  span={rows[-1][0]-rows[0][0]:.0f}s")
    vals = [v for _, v in rows]
    print(f"level: min={min(vals):.2f} median={statistics.median(vals):.2f} max={max(vals):.2f} GB")
    # biggest jumps
    jumps = []
    for i in range(1, len(rows)):
        t0, v0 = rows[i - 1]
        t1, v1 = rows[i]
        jumps.append((v1 - v0, t1, v0, v1))
    jumps.sort()
    print("--- 6 largest rises ---")
    for d, t, v0, v1 in jumps[-6:][::-1]:
        print(f"  t={t:.1f}  +{d:.2f} GB  ({v0:.2f} -> {v1:.2f})")
    print("--- 6 largest drops ---")
    for d, t, v0, v1 in jumps[:6]:
        print(f"  t={t:.1f}  {d:.2f} GB  ({v0:.2f} -> {v1:.2f})")
    if launch and stop:
        before = [v for t, v in rows if launch - 20 <= t <= launch]
        after = [v for t, v in rows if launch + 10 <= t <= launch + 60]
        post = [v for t, v in rows if stop + 15 <= t <= stop + 60]
        if before and after:
            b = statistics.median(before); a = statistics.median(after)
            print(f"--- step across launch: before(median {len(before)} samples)={b:.2f}  after={a:.2f}  delta={a-b:+.2f} GB")
        if post:
            p = statistics.median(post)
            print(f"--- after stop (median {len(post)})={p:.2f}  delta vs loaded={p-a:+.2f} GB")

if __name__ == "__main__":
    main(sys.argv[1],
         float(sys.argv[2]) if len(sys.argv) > 2 else None,
         float(sys.argv[3]) if len(sys.argv) > 3 else None)
