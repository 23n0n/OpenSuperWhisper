#!/usr/bin/env python3
"""Repair stale absolute paths in SwiftPM state after the workspace move.

`SourcePackages/workspace-state.json` records binary-artifact paths absolutely, and the SwiftPM
checkouts' `.git` files carry `alternates`/`config`/logs with the pre-move path. cmake and the
app sources are unaffected; this is what makes xcodebuild fail with
"There is no XCFramework found at '<old path>'".
"""
import pathlib

ROOT = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork")
OLD = pathlib.Path("/Volumes/home/zenon/Projects")

trees = [(ROOT / "repo", OLD / "OpenSuperWhisper")]
for wt in sorted((ROOT / "worktrees").iterdir()):
    if wt.is_dir():
        trees.append((wt, OLD / wt.name))

for new, old in trees:
    subs = []
    # worktree prefixes first: `Projects/OpenSuperWhisper` is a prefix of `Projects/OpenSuperWhisper-fm-fm-*`
    for other_new, other_old in trees:
        if other_old != old:
            subs.append((other_old, other_new))
    subs.append((old.parent / "OpenSuperWhisper-fm-fm", new.parent / "OpenSuperWhisper-fm-fm"))
    subs.sort(key=lambda p: len(str(p[0])), reverse=True)
    subs.append((old, new))

    hits = 0
    for path in list(new.rglob("workspace-state.json")) + list(new.glob("SourcePackages/checkouts/*/.git/*")) \
            + list(new.glob("SourcePackages/checkouts/*/.git/logs/**/*")) \
            + list(new.glob("SourcePackages/checkouts/*/.git/objects/info/*")):
        if not path.is_file() or path.is_symlink():
            continue
        try:
            text = path.read_text()
        except (UnicodeDecodeError, PermissionError, OSError):
            continue
        new_text = text
        for o, n in subs:
            new_text = new_text.replace(str(o), str(n))
        if new_text != text:
            try:
                path.write_text(new_text)
            except (PermissionError, OSError) as exc:
                print(f"{new.name}: SKIP {path.relative_to(new)} ({exc.strerror})")
                continue
            hits += 1
            print(f"{new.name}: patched {path.relative_to(new)}")
    print(f"== {new.name}: {hits} files patched (old prefix {old})")

leftovers = []
for new, old in trees:
    for path in new.rglob("workspace-state.json"):
        text = path.read_text()
        if "/Volumes/home/zenon/Projects/OpenSuperWhisper/" in text.replace(
                "/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/", ""):
            leftovers.append(str(path))
print("remaining stale refs:", leftovers or "none")
