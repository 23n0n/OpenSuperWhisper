#!/bin/bash
# fm-24: wired-memory trace. Samples `Pages wired down` every 0.5 s with a
# wall-clock stamp, so a load/unload shows up as a STEP in the trace even when
# unrelated activity (sibling agents building) drifts the baseline.
# Usage: wired_trace.sh <outfile> <seconds>
export LC_ALL=C
OUT="$1"; SECS="${2:-600}"
PAGE=16384
: > "$OUT"
end=$(( $(date +%s) + SECS ))
while [ "$(date +%s)" -lt "$end" ]; do
    line="$(vm_stat | awk '/Pages wired down/ {gsub(/\./,"",$4); print $4}')"
    printf '%s\t%s\t%s\n' "$(date +%s.%N)" "$line" "$(( line * PAGE ))" >> "$OUT"
    sleep 0.5
done
