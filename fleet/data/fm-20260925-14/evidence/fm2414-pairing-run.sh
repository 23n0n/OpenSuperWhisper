#!/bin/sh
# fm-20260925-14 focused measurement run, detached.
# Log and evidence are named by LOG/EVID so each iteration is preserved.
set -u

LOG=${LOG:-/tmp/fm2414-pairing-focused.log}
EVID=${EVID:-/tmp/fm2414-pairing-evidence.log}
MODEL="/Volumes/home/zenon/Library/Application Support/ru.starmel.OpenSuperWhisper/whisper-models/ggml-large-v3-turbo.bin"
REC="$HOME/Library/Application Support/ru.starmel.OpenSuperWhisper/recordings"
WT=/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-pairing
TESTS=${TESTS:-OpenSuperWhisperTests/WhisperPauseBoundaryPairingTests}

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export OSW_TEST_MULTILINGUAL_MODEL="$MODEL"
export TEST_RUNNER_OSW_TEST_MULTILINGUAL_MODEL="$MODEL"
export TEST_RUNNER_OSW_TEST_CAPTAIN_RECORDINGS="$REC"
export TEST_RUNNER_OSW_TEST_EVIDENCE="$EVID"

: > "$LOG"
: > "$EVID"
printf 'chain start %s (pid %s)\n' "$(date -u +%FT%TZ)" "$$" >> "$LOG"

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
printf 'focused run start %s\n' "$(date -u +%FT%TZ)" >> "$LOG"
Scripts/dev-run.sh test \
    -only-testing:"$TESTS" >> "$LOG" 2>&1
status=$?
printf 'dev_run_exit=%s at %s\n' "$status" "$(date -u +%FT%TZ)" >> "$LOG"
printf 'evidence lines: %s\n' "$(grep -c '\[pair\]' "$EVID" 2>/dev/null || echo 0)" >> "$LOG"
exit "$status"
