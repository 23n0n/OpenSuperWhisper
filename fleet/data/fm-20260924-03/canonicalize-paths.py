#!/usr/bin/env python3
"""Canonicalise the moved-tree prefixes in every SourcePackages/workspace-state.json.

An earlier, non-idempotent pass ran the old->new substitution twice on the same file, producing
`OpenSuperWhisper-fork/repo-fork/repo/...` and `OpenSuperWhisper-fork/repo-fork/worktrees/<wt>/...`.
This collapses any number of repetitions to the canonical prefix and then verifies that every recorded
absolute path actually exists.
"""
import pathlib
import re

ROOT = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork")
BAD = re.compile(r"(OpenSuperWhisper-fork)/(?:repo-fork/)+")
files = [ROOT / "repo" / "SourcePackages" / "workspace-state.json"]
files += sorted(ROOT.glob("worktrees/*/SourcePackages/workspace-state.json"))

for f in files:
    if not f.is_file():
        print(f"{f}: absent")
        continue
    text = f.read_text()
    fixed = BAD.sub(r"\1/", text)
    if fixed != text:
        f.write_text(fixed)
        print(f"{f.relative_to(ROOT)}: canonicalised")
    else:
        print(f"{f.relative_to(ROOT)}: already canonical")
    missing = [p for p in set(re.findall(r'"(/Volumes/[^"]+)"', fixed)) if not pathlib.Path(p).exists()]
    print(f"  recorded paths: {len(set(re.findall(r'"(/Volumes/[^"]+)"', fixed)))}, missing: {missing or 'none'}")
