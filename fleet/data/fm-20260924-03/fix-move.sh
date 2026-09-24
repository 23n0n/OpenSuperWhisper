#!/usr/bin/env bash
# Repair the parts left by move-workspace.sh: worktree submodule gitdir pointers (relative,
# so the move broke them), then the fleet-record path rewrite, archive copy, and verification.
set -uo pipefail

NEW=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo-fork

echo "== A. rewrite worktree submodule gitdir pointers =="
python3 - <<'PY'
import pathlib, re
root = pathlib.Path("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo-fork")
changed = []
for wt in (root / "worktrees").iterdir():
    for gitfile in wt.rglob(".git"):
        if not gitfile.is_file() or gitfile.is_symlink():
            continue
        rel_depth = len(gitfile.relative_to(wt).parts) + 1  # dirs from gitfile's own dir up to <root>
        text = gitfile.read_text()
        m = re.match(r"gitdir: (.*)\n?$", text)
        if not m:
            continue
        target = m.group(1)
        if target.startswith(".."):
            fixed = "../" * rel_depth + "repo/.git/worktrees/%s/modules/%s" % (
                wt.name, gitfile.parent.name)
            if fixed != target:
                gitfile.write_text("gitdir: %s\n" % fixed)
                changed.append((str(gitfile), target, fixed))
for c in changed:
    print("fixed %s\n  was %s\n  now %s" % c)
print("total fixed:", len(changed))
PY

echo "== B. worktree integrity =="
for id in 15 16 17; do
  wt="$NEW/worktrees/OpenSuperWhisper-fm-fm-20260923-$id"
  echo "--- wt-$id $(git -C "$wt" rev-parse HEAD 2>&1 | head -1)"
  git -C "$wt" status --porcelain=v1 2>&1 | head -12
  echo "entries: $(git -C "$wt" status --porcelain=v1 2>/dev/null | wc -l | tr -d ' ')"
  git -C "$wt" submodule status 2>&1 | head -4
done

echo "== C. main repo integrity =="
git -C "$NEW/repo" status --porcelain=v1 | head -5
echo "clean entries: $(git -C "$NEW/repo" status --porcelain=v1 | wc -l | tr -d ' ')"
git -C "$NEW/repo" log --oneline -1
git -C "$NEW/repo" worktree list

echo "== D. fleet record path rewrite =="
cd "$NEW/fleet"
grep -rl "/Volumes/home/zenon" . > /tmp/fm-pathfiles.txt
while IFS= read -r f; do
  LC_ALL=C sed -i '' \
    -e "s#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-#g" \
    -e "s#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo#g" \
    -e "s#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet#g" \
    -e "s#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-#$NEW/worktrees/OpenSuperWhisper-fm-fm-#g" \
    -e "s#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo#$NEW/repo#g" \
    -e "s#/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet#$NEW/fleet#g" "$f"
done < /tmp/fm-pathfiles.txt
echo "rewrote $(wc -l < /tmp/fm-pathfiles.txt | tr -d ' ') record files"
echo "leftovers outside the new root:"; grep -rn "/Volumes/home/zenon" . | grep -v "OpenSuperWhisper-fork" | head -10
echo "(none above = clean)"

echo "== E. archive copies =="
cp -a "$NEW/fleet/data/fm-20260924-03/opensuperwhisper-20260924.bundle" "$NEW/archive/"
cp -a "$NEW/fleet/data/fm-20260924-03/fleet-records-20260924.tgz" "$NEW/archive/"
ls -la "$NEW/archive"

echo "== F. layout =="
ls -la /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo-fork
du -sh "$NEW"/* 2>/dev/null
ls -la /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet
