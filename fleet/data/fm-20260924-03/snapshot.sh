#!/usr/bin/env bash
# fm-20260924-03 — preservation snapshot. Read-only against the repo and worktrees;
# writes only into the fleet task directory and a scratch verify dir.
set -euo pipefail

R=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo
H=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet
D="$H/data/fm-20260924-03"
STAMP=20260924
mkdir -p "$D"

echo "== 1. branch inventory =="
git -C "$R" for-each-ref --format='branch %(refname:short) %(objectname)' refs/heads | tee "$D/branches-all.txt"
echo "origin/develop $(git -C "$R" rev-parse origin/develop)" | tee -a "$D/branches-all.txt"

echo "== 2. bundle (delivery + all fm/* branches, upstream history excluded) =="
git -C "$R" bundle create "$D/opensuperwhisper-$STAMP.bundle" \
  ^origin/develop feat/local-translate-tone --branches='fm/*'
git -C "$R" bundle verify "$D/opensuperwhisper-$STAMP.bundle"
git -C "$R" bundle list-heads "$D/opensuperwhisper-$STAMP.bundle" | tee "$D/bundle-heads.txt"

echo "== 3. worktree uncommitted work =="
mkdir -p "$D/untracked"
for id in 15 16 17; do
  wt="$R-fm-fm-20260923-$id"
  [ -d "$wt" ] || { echo "MISSING worktree $wt"; continue; }
  git -C "$wt" status --porcelain=v1 > "$D/wt-$id-status.txt"
  git -C "$wt" diff HEAD > "$D/wt-$id-uncommitted.patch"
  git -C "$wt" log --oneline -3 > "$D/wt-$id-log.txt"
  git -C "$wt" ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' f; do
      mkdir -p "$D/untracked/$id/$(dirname "$f")"
      cp "$wt/$f" "$D/untracked/$id/$f"
    done
  echo "wt-$id tip $(git -C "$wt" rev-parse HEAD) status-entries $(wc -l < "$D/wt-$id-status.txt")"
done

echo "== 4. submodule pins =="
git -C "$R" submodule status --recursive | tee "$D/submodules.txt"

echo "== 5. fleet records =="
( cd "$H" && tar czf "/tmp/fleet-records-$STAMP.tgz" \
    --exclude='state/.lock' --exclude='data/fm-20260924-03' \
    state data/projects.md data/backlog.md data/RESUME.md data/FLEET-STATE.md data/fm-* )
mv "/tmp/fleet-records-$STAMP.tgz" "$D/fleet-records-$STAMP.tgz"
tar tzf "$D/fleet-records-$STAMP.tgz" | wc -l

echo "== 6. verify: restore the bundle into a scratch repo =="
S=/tmp/fm-verify-20260924-03
rm -rf "$S"; mkdir -p "$S"
git init -q "$S/repo"
git -C "$S/repo" remote add upstream "$R"
git -C "$S/repo" fetch -q upstream "origin/develop:refs/remotes/upstream/develop" 2>/dev/null ||
  git -C "$S/repo" fetch -q "$R" "origin/develop"
git -C "$S/repo" fetch -q "$D/opensuperwhisper-$STAMP.bundle" \
  "+refs/heads/*:refs/remotes/restored/*"
for br in feat/local-translate-tone fm/fm-20260923-15 fm/fm-20260923-16 fm/fm-20260923-09; do
  local_tip=$(git -C "$R" rev-parse "$br")
  restored=$(git -C "$S/repo" rev-parse "refs/remotes/restored/$br")
  [ "$local_tip" = "$restored" ] && echo "TIP OK  $br $restored" || echo "TIP MISMATCH $br local=$local_tip restored=$restored"
done
echo "delivered file count at delivery tip: $(git -C "$S/repo" ls-tree -r --name-only refs/remotes/restored/feat/local-translate-tone | wc -l) (expected 160)"

echo "== 7. verify: uncommitted patches apply cleanly =="
for id in 15 16 17; do
  br=fm/fm-20260923-$id
  ref="refs/remotes/restored/$br"
  git -C "$S/repo" rev-parse -q --verify "$ref" >/dev/null || { echo "patch-$id: no restored branch $br"; continue; }
  git -C "$S/repo" checkout -q -B "check-$id" "$ref"
  if git -C "$S/repo" apply --check "$D/wt-$id-uncommitted.patch"; then
    echo "PATCH OK $id"
  else
    echo "PATCH FAILED $id"
  fi
done

echo "== 8. snapshot size =="
du -sh "$D"
ls -la "$D"
