#!/usr/bin/env bash
# Consolidate the OpenSuperWhisper fork work into /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo-fork.
# Captain-approved 2026-09-24: structured root + removal of the five merged worktrees.
# Same-volume moves only (rename), so no 20 GB copy. Snapshotted first (fm-20260924-03).
set -euo pipefail

P=/Volumes/home/zenon/Projects
OLD="$P/OpenSuperWhisper"
NEW="$P/OpenSuperWhisper-fork"
FH=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet
DOCS=/Volumes/home/zenon/Documents/deepseek_general

[ -d "$OLD" ] || { echo "FATAL: no repo at $OLD"; exit 2; }
[ -e "$NEW" ] && { echo "FATAL: $NEW already exists"; exit 2; }
cd /tmp

echo "== 1. remove merged worktrees (branches stay) =="
for id in 12 13 22 23 27; do
  wt="$P/OpenSuperWhisper-fm-fm-20260923-$id"
  [ -d "$wt" ] || { echo "skip $id (absent)"; continue; }
  if git -C "$OLD" worktree remove --force "$wt" 2>/dev/null; then
    echo "removed $wt"
  else
    rm -rf "$wt"
    echo "rm -rf (git refused; submodule worktree) $wt"
  fi
done
git -C "$OLD" worktree prune
git -C "$OLD" worktree list
echo "space after prune:"; df -h /Volumes/home | tail -1

echo "== 2. build the new layout =="
mkdir -p "$NEW/worktrees" "$NEW/docs" "$NEW/archive"
mv "$OLD" "$NEW/repo"
for id in 15 16 17; do
  mv "$P/OpenSuperWhisper-fm-fm-20260923-$id" "$NEW/worktrees/"
done
mv "$FH" "$NEW/fleet"
mv "$DOCS/voice-keyboard-fork-plan.md" "$DOCS/voice-keyboard-study.md" "$NEW/docs/"
# compatible symlink so a stale path still resolves to the fleet records
ln -s "$NEW/fleet" /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet

echo "== 3. repair git worktree links for the moved paths =="
git -C "$NEW/repo" worktree repair
git -C "$NEW/repo" worktree repair "$NEW/worktrees"/OpenSuperWhisper-fm-fm-20260923-{15,16,17} 2>&1 || true
git -C "$NEW/repo" worktree list
for id in 15 16 17; do
  echo "--- wt-$id"
  git -C "$NEW/worktrees/OpenSuperWhisper-fm-fm-20260923-$id" status --porcelain=v1 | wc -l
  git -C "$NEW/worktrees/OpenSuperWhisper-fm-fm-20260923-$id" rev-parse HEAD
done

echo "== 4. rewrite absolute paths in the fleet records =="
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
echo "rewrote $(wc -l < /tmp/fm-pathfiles.txt) record files"
grep -rn "/Volumes/home/zenon" . | grep -v "OpenSuperWhisper-fork" | head -10 || true

echo "== 5. archive copy of the verified snapshot =="
cp -a "$NEW/fleet/data/fm-20260924-03/opensuperwhisper-20260924.bundle" "$NEW/archive/"
cp -a "$NEW/fleet/data/fm-20260924-03/fleet-records-20260924.tgz" "$NEW/archive/"
cp -a "$NEW/fleet/data/fm-20260924-03/opensuperwhisper-20260924.bundle" /tmp/ 2>/dev/null || true

echo "== 6. result =="
ls -la "$NEW"
du -sh "$NEW"/* 2>/dev/null
df -h /Volumes/home | tail -1
