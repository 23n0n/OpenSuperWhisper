#!/bin/bash
# fm-20260925-13: the last acceptance item — the full suite at the final head.
# Waits for the machine contention gate, runs it detached, waits for it, prints the counts.
set -u
cd /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-toneprompt

# 1. gate: no other xcodebuild / llama-server alive (60 s loop, bounded)
for i in $(seq 1 45); do
  if ! pgrep -f "xcodebuild|llama-server" >/dev/null 2>&1; then
    echo "GATE OPEN at $(date -u +%Y-%m-%dT%H:%M:%SZ) after $((i*60-60))s"
    break
  fi
  sleep 60
done
if pgrep -f "xcodebuild|llama-server" >/dev/null 2>&1; then
  echo "GATE STILL CLOSED at $(date -u +%Y-%m-%dT%H:%M:%SZ) — suite not run"
  exit 3
fi

# 2. the suite, detached in its own session
rm -f /tmp/fm2413-suite-final.log
python3 -c "
import subprocess
log = open('/tmp/fm2413-suite-final.log', 'w')
p = subprocess.Popen(['Scripts/dev-run.sh', 'test'], stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
print('suite launched pid', p.pid)
"
wait_for=""
for i in $(seq 1 90); do
  if grep -q '\*\* TEST SUCCEEDED \*\*\|\*\* TEST FAILED \*\*\|dev_run_exit=' /tmp/fm2413-suite-final.log 2>/dev/null; then
    sleep 30   # let the re-sign step finish after the marker
    break
  fi
  sleep 30
done

echo "=== markers ==="
grep -n '\*\* TEST SUCCEEDED \*\*\|\*\* TEST FAILED \*\*' /tmp/fm2413-suite-final.log
echo "=== decision requirement ==="
grep -n "certificate leaf" /tmp/fm2413-suite-final.log | tail -2
XC=$(ls -dt build/Logs/Test/*.xcresult 2>/dev/null | head -1)
echo "xcresult: $XC"
/Applications/Xcode.app/Contents/Developer/usr/bin/xcresulttool get test-results summary --path "$XC" > /tmp/fm2413-final-summary.json 2>/tmp/fm2413-final-summary.err
python3 -c "
import json
d=json.load(open('/tmp/fm2413-final-summary.json'))
print('FINAL COUNTS:', d['totalTestCount'],'total,',d['passedTests'],'passed,',d['failedTests'],'failed,',d['skippedTests'],'skipped, result',d['result'])
for f in d.get('testFailures',[]):
    print('FAILURE:', f['testName'], '->', (f.get('failureText') or '').split(chr(10))[0][:200])
"
tail -5 /tmp/fm2413-suite-final.log
echo "FINAL SUITE JOB DONE"
