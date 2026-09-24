#!/bin/bash
# fm-24: wired-memory sampler. llama.cpp puts Metal weights in wired buffers,
# so `Pages wired down` (not RSS) is the number that measures the model.
# Usage: wired.sh <label>
export LC_ALL=C
PAGE=16384
line="$(vm_stat | awk '/Pages wired down/ {gsub(/\./,"",$4); print $4}')"
bytes=$(( line * PAGE ))
printf '%s\twired_pages=%s\twired_bytes=%s\twired_GB=%.2f\n' "$1" "$line" "$bytes" "$(echo "$bytes/1073741824" | bc -l)"
echo "--- full vm_stat ---"
vm_stat | sed -n '1,12p'
echo "--- swap ---"
sysctl vm.swapusage
