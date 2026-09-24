#!/usr/bin/env python3
"""Point every worktree submodule link at its real admin dir, now that the tree has moved.

git stores these as relative paths, which the move invalidated. The admin dirs live under
repo/.git/worktrees/<wt>/modules/<full submodule path> (nested, not basename-only), so write
absolute paths: unambiguous and verifiable.
"""
import pathlib
import re

ROOT = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork")
REPO = ROOT / "repo"

mods = [re.search(r"path = (.+)", b).group(1).strip()
        for b in (REPO / ".gitmodules").read_text().split("[submodule ")[1:]]

for wt in sorted((ROOT / "worktrees").iterdir()):
    if not wt.is_dir():
        continue
    print(f"== {wt.name}")
    for path in mods:
        sub_git = wt / path / ".git"
        want = f"gitdir: {REPO}/.git/worktrees/{wt.name}/modules/{path}"
        if sub_git.is_file():
            have = sub_git.read_text().strip()
            if have != want:
                sub_git.write_text(want + "\n")
                print(f"  {path}/.git: {have}\n     -> {want}")
        cfg = REPO / ".git" / "worktrees" / wt.name / "modules" / path / "config"
        if cfg.is_file():
            have = cfg.read_text()
            want_wt = f"worktree = {ROOT}/worktrees/{wt.name}/{path}"
            new = re.sub(r"(\n\tworktree = ).*\n", r"\g<1>" + want_wt + "\n", have)
            if new != have:
                cfg.write_text(new)
                print(f"  modules/{path}/config -> {want_wt}")
        else:
            print(f"  modules/{path}/config MISSING (admin dir absent)")
