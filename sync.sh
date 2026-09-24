#!/usr/bin/env bash
# Refresh the fleet-state snapshot from the live records, redact, and push.
# The live records live outside git (../fleet, ../docs, ../archive); this branch is a copy.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../repo && pwd)"
MSG="${1:-fleet records: snapshot}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

rsync -a --delete ../fleet/ fleet/
rsync -a --delete ../docs/  docs/
mkdir -p archive
cp -p ../archive/*.bundle ../archive/*.tgz archive/ 2>/dev/null || true
python3 redact.py
git -C "$REPO" bundle create "$PWD/archive/all-local-branches-$STAMP.bundle" --branches --not origin/develop
git -C "$REPO" branch --format='%(refname:short) %(objectname:short)' > "archive/local-branches-$STAMP.txt"

git add -A
if git diff --cached --quiet; then
  echo "nothing to commit"
else
  git commit -q -m "$MSG"
fi
git push -u origin fleet-state
echo "snapshot $STAMP pushed"
