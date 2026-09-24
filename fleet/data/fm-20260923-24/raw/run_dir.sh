#!/bin/bash
# fm-24 measurement driver: byte-for-byte the same request shape as fm-19,
# which is the app's TranslationService.systemPrompt + buildRequestBody +
# LlamaModel.makeSampler (top_k 40, top_p .95, min_p .05, temp .2, seed 0).
# Usage: run_dir.sh <model> <srcLang> <tgtLang> <file> <label> <outfile>
set -uo pipefail

MODEL="$1"; SRC="$2"; TGT="$3"; FILE="$4"; LABEL="$5"; OUT="$6"
PORT="${PORT:-1924}"
ENDPOINT="http://127.0.0.1:${PORT}/v1/chat/completions"
PROMPT="You are a translation assistant. Translate the user's ${SRC} text into natural ${TGT}. Output ONLY the final ${TGT} text, with no quotes, labels, or explanation.
/no_think"

: > "$OUT"
n=0
while IFS= read -r text; do
    [ -z "$text" ] && continue
    n=$((n + 1))
    body="$(jq -cn --arg model "$MODEL" --arg sys "$PROMPT" --arg user "$text" \
        '{model: $model,
          messages: [{role: "system", content: $sys}, {role: "user", content: $user}],
          temperature: 0.2, top_k: 40, top_p: 0.95, min_p: 0.05, seed: 0,
          n_predict: 1024, stream: false,
          chat_template_kwargs: {enable_thinking: false}}')"
    meta="$(curl -sS --max-time 300 -o /tmp/fm24/resp.json -w '%{http_code} %{time_total}' \
        -H 'Content-Type: application/json' --data-binary "$body" "$ENDPOINT" 2>/dev/null)"
    code="${meta%% *}"; t="${meta##* }"
    out="$(jq -r '.choices[0].message.content // "<EMPTY>"' /tmp/fm24/resp.json 2>/dev/null \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr '\n' ' ')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$t" "$code" "$text" "$out" >> "$OUT"
    echo "[$LABEL $n] ${t}s http=${code}"
    echo "  in : $text"
    echo "  out: $out"
done < "$FILE"
