#!/bin/bash
# fm-20260924-01 relaunch checks. Headless only: dev-run.sh test, no app, no AX.
#
# Part A - does the one failing suite case fail in isolation too, or only under
#          the load of several concurrent suites?
# Part B - the focused long-form re-measurement (independent second sample).
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
WT=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-fm-20260924-01
D=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260924-01/logs
cd "$WT" || exit 1

echo "### host load at start: $(uptime)"

for i in 1 2 3; do
    echo "### A$i snapshot class, isolated run $i at $(date -u +%FT%TZ)"
    Scripts/dev-run.sh test \
        -only-testing:OpenSuperWhisperTests/SettingsLayoutSnapshotTests \
        > "$D/snapshot-rerun-$i.log" 2>&1
    echo "### A$i exit=$?"
    grep -E "Test case 'SettingsLayoutSnapshotTests.*(passed|failed|skipped) on" \
        "$D/snapshot-rerun-$i.log" | sed "s/ on 'My Mac.*//"
done

echo "### B long-form classes at $(date -u +%FT%TZ)"
Scripts/dev-run.sh test \
    -only-testing:OpenSuperWhisperTests/WhisperLongFormSegmentAssemblyTests \
    -only-testing:OpenSuperWhisperTests/WhisperLongFormMediaFixtureTests \
    -only-testing:OpenSuperWhisperTests/WhisperLongFormLanguageIntegrationTests \
    > "$D/longform-remeasure.log" 2>&1
echo "### B exit=$?"
grep -E "Test case 'WhisperLongForm.*(passed|failed|skipped) on" \
    "$D/longform-remeasure.log" | sed "s/ on 'My Mac.*//"
echo "### done at $(date -u +%FT%TZ)"
