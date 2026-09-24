#!/usr/bin/env python3
"""Collapse `OpenSuperWhisper-fork/(repo-fork/)+` -> `OpenSuperWhisper-fork/` in every git metadata
text file, then verify the whole worktree set again.

The corruption comes from applying a prefix substitution to a path that already contains the new
prefix; it must be collapsed everywhere it was applied, and the collapse is idempotent.
"""
import pathlib
import re

ROOT = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork")
REPO = ROOT / "repo"
BAD = re.compile(r"(OpenSuperWhisper-fork)/(?:repo-fork/)+")

targets = [REPO / ".git" / "config"]
for name in ("HEAD", "ORIG_HEAD", "FETCH_HEAD", "MERGE_HEAD", "gitdir", "commondir"):
    targets += list(REPO.glob(f".git/worktrees/*/{name}"))
targets += list(REPO.glob(".git/worktrees/*/modules/*/config"))
targets += list(REPO.glob(".git/worktrees/*/modules/*/*/config"))
targets += [p for p in (ROOT / "worktrees").glob("*/.git") if p.is_file()]
targets += list(ROOT.glob("worktrees/*/*/.git"))
targets += list(ROOT.glob("worktrees/*/*/*/.git"))

fixed = 0
for p in targets:
    if not p.is_file():
        continue
    text = p.read_text()
    new = BAD.sub(r"\1/", text)
    if new != text:
        p.write_text(new)
        fixed += 1
        print("canonicalised", p)
print("files rewritten:", fixed)

print("\n== verification ==")
for p in targets:
    if p.is_file() and "gitdir" in p.name or p.name == "config":
        pass
