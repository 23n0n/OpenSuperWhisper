#!/bin/sh
# fm-20260925-14 full unit suite, on the final tree, from a clean build state.
# File was written for the refusal's "nothing is broken" evidence: the tree is the
# base commit plus the measurement harness, and the measurement runs inside the
# green suite (the env vars are set), so the counts and the arm tables come from
# the same run.
set -u

LOG=/tmp/fm2414-suite.log
EVID=/tmp/fm2414-pairing-evidence-iter2.log
MODEL="/Volumes/home/zenon/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin"
REC="$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper/recordings"
WT=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pairing

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export OSW_TEST_MULTILINGUAL_MODEL="$MODEL"
export TEST_RUNNER_OSW_TEST_MULTILINGUAL_MODEL="$MODEL"
export TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS="$REC"
export TEST_RUNNER_OSW_TEST_EVIDENCE="$EVID"

[ -f "$LOG" ] && mv "$LOG" "$LOG.prev"
: > "$EVID"
printf 'full suite start %s (pid %s)\n' "$(date -u +%FT%TZ)" "$$" >> "$LOG"

minutes=0
while :; do
    busy=$(pgrep -f 'dev-run.sh|xcodebuild|swift-frontend|cargo|llama-server' | wc -l | tr -d ' ')
    if [ "$busy" = "0" ]; then
        printf 'machine idle at %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
        break
    fi
    minutes=$((minutes + 1))
    if [ "$minutes" -ge 90 ]; then
        printf 'machine still busy after %s min; giving up\n' "$minutes" >> "$LOG"
        pgrep -fl 'dev-run.sh|xcodebuild|llama-server' >> "$LOG" 2>&1
        exit 7
    fi
    sleep 60
done

cd "$WT" || exit 9
printf 'removing build/ for a from-scratch suite %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
rm -rf "$WT/build"
printf 'suite start %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
Scripts/dev-run.sh test >> "$LOG" 2>&1
status=$?
printf 'dev_run_exit=%s at %s\n' "$status" "$(date -u +%FT%TZ)" >> "$LOG"
printf 'evidence lines: %s\n' "$(grep -c '\[pair\]' "$EVID" 2>/dev/null || echo 0)" >> "$LOG"
bundle=$(ls -dt "$WT/build/Logs/Test/"*.xcresult 2>/dev/null | head -1)
printf 'result bundle: %s\n' "$bundle" >> "$LOG"
if [ -n "$bundle" ]; then
    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
        xcrun xcresulttool get test-results summary --path "$bundle" >> "$LOG" 2>&1
fi
exit "$status"
