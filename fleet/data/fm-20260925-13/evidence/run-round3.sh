#!/bin/bash
# fm-20260925-13 round 3: the paths the winner also touches.
#   1. Polish tone+clean-up (both switches on) — control vs winner, 28 cases, 2 runs
#   2. English tone — control vs winner, 11 cases, 2 runs (the two prompts are byte-identical,
#      so this is the no-regression draw on the same bytes)
set -u
cd "$(dirname "$0")"
MODEL="/Volumes/home/zenon/Library/Application Support/ru.starmel.OpenSuperWhisper/transform-models/qwen3-8b-q4_k_m.gguf"
python3 tone-compiled.py "$MODEL" polish cases-pl.json measure-pl-combined.json 2 \
    control:compiled-before.json:cleanUpWithTone winner:compiled-after.json:cleanUpWithTone
python3 tone-compiled.py "$MODEL" english cases-en.json measure-en-after.json 2 \
    control:compiled-before.json:tone winner:compiled-after.json:tone
echo "ROUND3 DONE"
