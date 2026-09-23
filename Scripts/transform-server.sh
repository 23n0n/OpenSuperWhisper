#!/bin/bash

# Local, offline translation + tone backend for OpenSuperWhisper.
#
# The app POSTs the Polish transcript to an OpenAI-compatible
# /v1/chat/completions endpoint (Settings -> Translation & Tone). This script
# serves that endpoint with a small instruction-tuned LLM via llama-server, so
# nothing leaves the machine.
#
# Usage:
#   Scripts/transform-server.sh           - serve the endpoint (fails if weights are missing)
#   Scripts/transform-server.sh --fetch   - download the weights, verify them, then serve
#   Scripts/transform-server.sh --check   - verify weights are present, then exit
#
# Environment overrides:
#   TRANSFORM_MODEL_DIR  directory holding the GGUF   (default: $HOME/models)
#   TRANSFORM_PORT       listen port                  (default: 1919)
#   TRANSFORM_CTX_SIZE   server context size          (default: 4096)

set -euo pipefail

MODEL_REPO="bartowski/Qwen2.5-1.5B-Instruct-GGUF"
MODEL_FILE="Qwen2.5-1.5B-Instruct-Q4_K_M.gguf"
MODEL_SHA256="1adf0b11065d8ad2e8123ea110d1ec956dab4ab038eab665614adba04b6c3370"

# Local file name. The stem doubles as the API model alias, i.e. the id the
# server reports in /v1/models and the value the app's "Model" setting ships
# with (AppPreferences.transformModel).
MODEL_NAME="qwen2.5-1.5b-instruct-q4_k_m.gguf"
MODEL_ALIAS="${MODEL_NAME%.gguf}"

MODEL_DIR="${TRANSFORM_MODEL_DIR:-$HOME/models}"
MODEL_PATH="${MODEL_DIR}/${MODEL_NAME}"
PORT="${TRANSFORM_PORT:-1919}"
HOST="127.0.0.1"
CTX_SIZE="${TRANSFORM_CTX_SIZE:-4096}"

FETCH=false
CHECK_ONLY=false

usage() {
    sed -n '3,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

for arg in "$@"; do
    case "$arg" in
        --fetch) FETCH=true ;;
        --check) CHECK_ONLY=true ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "transform-server.sh: unknown argument: $arg" >&2
            echo "Try --help." >&2
            exit 2
            ;;
    esac
done

missing_weights_message() {
    cat >&2 <<EOF
ERROR: transform model weights are missing.

  expected: ${MODEL_PATH}

Fetch them (once, ~986 MB) with the explicit flag:

  Scripts/transform-server.sh --fetch

or place ${MODEL_FILE} there yourself, or point TRANSFORM_MODEL_DIR at an
existing directory that contains it.
EOF
}

fetch_weights() {
    mkdir -p "$MODEL_DIR"
    local url="https://huggingface.co/${MODEL_REPO}/resolve/main/${MODEL_FILE}"
    local tmp="${MODEL_PATH}.part"
    echo "Downloading ${MODEL_FILE} (~986 MB) from ${MODEL_REPO}..."
    rm -f "$tmp"
    curl -fL --retry 3 --retry-delay 2 --progress-bar -o "$tmp" "$url"
    if ! echo "${MODEL_SHA256}  ${tmp}" | shasum -a 256 -c - >/dev/null; then
        rm -f "$tmp"
        echo "ERROR: checksum mismatch for the downloaded weights; aborting." >&2
        exit 1
    fi
    mv "$tmp" "$MODEL_PATH"
    echo "Weights verified: ${MODEL_PATH}"
}

if [[ ! -f "$MODEL_PATH" ]]; then
    if $FETCH; then
        fetch_weights
    else
        missing_weights_message
        exit 1
    fi
elif $FETCH; then
    # Already present; re-verify rather than re-download.
    if echo "${MODEL_SHA256}  ${MODEL_PATH}" | shasum -a 256 -c - >/dev/null; then
        echo "Weights already present and verified: ${MODEL_PATH}"
    else
        rm -f "$MODEL_PATH"
        fetch_weights
    fi
fi

if $CHECK_ONLY; then
    echo "Weights present: ${MODEL_PATH}"
    exit 0
fi

if ! command -v llama-server >/dev/null 2>&1; then
    cat >&2 <<'EOF'
ERROR: llama-server not found on PATH.

Install llama.cpp, e.g.:

  brew install llama.cpp

EOF
    exit 1
fi

# Refuse to start when something already answers on the port: llama-server would
# fail to bind and a health probe against the incumbent would look like success.
if (exec 3<>"/dev/tcp/${HOST}/${PORT}") 2>/dev/null; then
    echo "ERROR: ${HOST}:${PORT} is already in use; stop what is serving it and retry." >&2
    exit 1
fi

echo "Starting llama-server with ${MODEL_ALIAS} on ${HOST}:${PORT}..."

llama-server \
    --model "$MODEL_PATH" \
    --alias "$MODEL_ALIAS" \
    --host "$HOST" \
    --port "$PORT" \
    --ctx-size "$CTX_SIZE" \
    --n-gpu-layers 99 &

SERVER_PID=$!

cleanup() {
    kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup INT TERM

READY=false
for _ in $(seq 1 240); do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "ERROR: llama-server exited before becoming ready." >&2
        exit 1
    fi
    if curl -fsS "http://${HOST}:${PORT}/health" >/dev/null 2>&1; then
        READY=true
        break
    fi
    sleep 0.5
done

if ! $READY; then
    echo "ERROR: llama-server did not become ready on ${HOST}:${PORT} within 120s." >&2
    cleanup
    exit 1
fi

echo ""
echo "Transform backend ready."
echo "  endpoint: http://${HOST}:${PORT}/v1/chat/completions"
echo "  model:    ${MODEL_ALIAS}"
echo ""
echo "Use that endpoint and model in Settings -> Translation & Tone."
echo "Verify the app contract with: Scripts/verify-transform.sh"
echo "Press Ctrl-C to stop."

wait "$SERVER_PID"
