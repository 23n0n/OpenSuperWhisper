#!/bin/bash
# fm-24: run a sentence file N times through the server, then compare outputs.
# Usage: runs.sh <model-alias> <label> <srcLang> <tgtLang> <file> <tag> <n> [warm]
set -uo pipefail
export LC_ALL=C

MODEL="$1"; LABEL="$2"; SRC="$3"; TGT="$4"; FILE="$5"; TAG="$6"; N="$7"; WARM="${8:-0}"
PORT="${PORT:-1924}"
cd /tmp/fm24

# The server binds its port before the weights are in place (hub's port
# readiness fires early), so wait for a real HTTP 200 before sending work.
for _ in $(seq 1 600); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://127.0.0.1:${PORT}/health")
    [ "$code" = "200" ] && break
    sleep 0.5
done
[ "$code" = "200" ] || { echo "SERVER NOT READY (health=$code)"; exit 1; }

if [ "$WARM" = "1" ]; then
    body=$(jq -cn --arg m "$MODEL" --arg s "You are a translation assistant. Translate the user's Polish text into natural English. Output ONLY the final English text, with no quotes, labels, or explanation.
/no_think" \
      '{model:$m,messages:[{role:"system",content:$s},{role:"user",content:"Dzień dobry"}],temperature:0.2,top_k:40,top_p:0.95,min_p:0.05,seed:0,n_predict:1024,stream:false,chat_template_kwargs:{enable_thinking:false}}')
    curl -sS -o /dev/null -w "warmup http=%{http_code} t=%{time_total}\n" \
        -H 'Content-Type: application/json' --data-binary "$body" \
        "http://127.0.0.1:${PORT}/v1/chat/completions"
fi

for i in $(seq 1 "$N"); do
    ./run_dir.sh "$MODEL" "$SRC" "$TGT" "$FILE" "${LABEL}-${TAG}-${i}" "out_${LABEL}_${TAG}_run${i}.tsv" \
        > "log_${LABEL}_${TAG}_run${i}.txt"
    echo "--- ${LABEL} ${TAG} run${i} done ---"
done

if [ "$N" -gt 1 ]; then
    for i in $(seq 2 "$N"); do
        if diff <(cut -f5 "out_${LABEL}_${TAG}_run1.tsv") <(cut -f5 "out_${LABEL}_${TAG}_run${i}.tsv") > /dev/null; then
            echo "DETERMINISM ${LABEL} ${TAG}: run1 vs run${i} BYTE-IDENTICAL"
        else
            echo "DETERMINISM ${LABEL} ${TAG}: run1 vs run${i} DIFFERS"
            diff <(cut -f5 "out_${LABEL}_${TAG}_run1.tsv") <(cut -f5 "out_${LABEL}_${TAG}_run${i}.tsv") | sed 's/^/    /'
        fi
    done
fi
