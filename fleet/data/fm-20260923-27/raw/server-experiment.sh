#!/bin/bash
# fm-20260923-27 — attribution experiment for the app's HTTP transform path.
#
# Question: the app's in-process path pins `dist(seed = 0)` per request, but
# `TranslationService.buildRequestBody` sends no `seed` at all and
# `Scripts/transform-server.sh` starts `llama-server` with no `--seed`. Does
# that unpinned path drift run to run, and does pinning it stop the drift?
#
# The body below is the app's exact request shape for a translate-only
# Polish → English dictation (TranslationService.buildRequestBody:
# model, messages, temperature 0.2, stream false, chat_template_kwargs).
#
# Usage: server-experiment.sh <tag> <nopseed|bodyseed|cliseed>
set -uo pipefail
export LC_ALL=C

TAG="$1"
MODE="$2"
PORT="${PORT:-1924}"
MODEL="${MODEL:-$HOME/models/qwen2.5-1.5b-instruct-q4_k_m.gguf}"
ALIAS="qwen2.5-1.5b-instruct-q4_k_m"
DIR="/tmp/fm27/attrib"
RUNS="${RUNS:-6}"
INPUT="${INPUT:-Nie mogę dzisiaj przyjść na spotkanie, przepraszam.}"
mkdir -p "$DIR"

SERVER_ARGS=()
BODY_SEED=""
case "$MODE" in
    nopseed)  ;;                                          # what ships today
    cliseed)  SERVER_ARGS+=(--seed 0) ;;                  # server pinned
    bodyseed) BODY_SEED=0 ;;                              # app pins per request
    *) echo "unknown mode: $MODE" >&2; exit 2 ;;
esac

BODY="$(python3 - "$INPUT" "$ALIAS" "$BODY_SEED" <<'PY'
import json, sys
text, alias, seed = sys.argv[1], sys.argv[2], sys.argv[3]
prompt = ("You are a translation assistant. Translate the user's Polish text into natural English.\n"
          "Output ONLY the final English text, with no quotes, labels, or explanation.\n"
          "/no_think")
body = {
    "model": alias,
    "messages": [{"role": "system", "content": prompt}, {"role": "user", "content": text}],
    "temperature": 0.2,
    "stream": False,
    "chat_template_kwargs": {"enable_thinking": False},
}
if seed:
    body["seed"] = int(seed)
print(json.dumps(body))
PY
)"
printf '%s\n' "$BODY" > "$DIR/$TAG.body.json"

echo "== $TAG mode=$MODE server args: ${SERVER_ARGS[*]:-none}"
llama-server --model "$MODEL" --alias "$ALIAS" --host 127.0.0.1 --port "$PORT" \
    --ctx-size 4096 --n-gpu-layers 99 ${SERVER_ARGS[@]+"${SERVER_ARGS[@]}"} \
    > "$DIR/$TAG.server.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null; wait $PID 2>/dev/null' EXIT

ready=false
for _ in $(seq 1 240); do
    if curl -fsS "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ready=true; break; fi
    if ! kill -0 "$PID" 2>/dev/null; then echo "server exited early" >&2; tail -5 "$DIR/$TAG.server.log" >&2; exit 1; fi
    sleep 0.5
done
$ready || { echo "server never became ready" >&2; exit 1; }

for n in $(seq 1 "$RUNS"); do
    start=$(python3 -c 'import time; print(time.time())')
    curl -sS "http://127.0.0.1:$PORT/v1/chat/completions" \
        -H 'Content-Type: application/json' -d "$BODY" \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["choices"][0]["message"]["content"].strip())' \
      > "$DIR/$TAG.$n.txt"
    end=$(python3 -c 'import time; print(time.time())')
    printf '  run %s  %.2fs  %s\n' "$n" \
        "$(python3 -c "print($end - $start)")" \
        "$(shasum -a 256 < "$DIR/$TAG.$n.txt" | cut -c1-16)"
done

echo "  distinct outputs: $(shasum -a 256 "$DIR"/$TAG.*.txt | awk '{print $1}' | sort -u | wc -l | tr -d ' ') of $RUNS"
