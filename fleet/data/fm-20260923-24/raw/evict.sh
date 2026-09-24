#!/bin/bash
# fm-24: cold-load experiment.
#
# `purge` needs a password we do not have, so evict the model from the unified
# buffer cache by churning a file much larger than it: write JUNK GB, read it
# back, then read a 1 GB slice of the model and compare the throughput with the
# same slice while the model was still cached. A big drop = the model left the
# cache and the following load is a genuine cold load.
set -uo pipefail
export LC_ALL=C

MODEL="$1"
JUNK_GB="${2:-12}"
JUNK=/tmp/fm24/junk.bin
SLICE_MB=1000

slice() {  # warm/cold read of a model slice, MB/s
    dd if="$MODEL" of=/dev/null bs=1m count=$SLICE_MB 2>&1 | tail -1
}

echo "### model: $MODEL"
echo "### 1. slice read with the model warm in cache:"
slice

echo "### 2. filling $JUNK_GB GB of buffer cache with junk"
dd if=/dev/urandom of="$JUNK" bs=1m count=$(( JUNK_GB * 1024 )) 2>&1 | tail -1
echo "--- reading the junk back (evicts older file pages) ---"
dd if="$JUNK" of=/dev/null bs=1m 2>&1 | tail -1

echo "### 3. same model slice after the churn:"
slice

echo "### 4. free/used now:"
vm_stat | sed -n '1,6p'
