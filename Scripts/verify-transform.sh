#!/bin/bash

# Contract verification for the local translation + tone backend.
#
# Drives the running backend with the app's EXACT request shape and asserts the
# app's parsing expectations hold:
#
#   * request body     -> TranslationService.buildRequestBody(text:tone:model:)
#   * system prompt    -> TranslationService.systemPrompt(for:)  (extracted from source)
#   * model/endpoint   -> AppPreferences.transformModel / .transformEndpoint defaults
#   * timeout ceiling  -> AppPreferences.transformTimeout default
#   * response parsing -> TranslationService.parseContent(from:) / .stripReasoning(from:)
#
# The prompt, tone instructions and defaults are read out of the Swift sources,
# so this script fails if the app and the backend ever drift apart.
#
# Usage:
#   Scripts/verify-transform.sh
#
# Requires the backend to be running:  Scripts/transform-server.sh
# Exits non-zero if any assertion fails.
#
# Environment overrides:
#   TRANSFORM_ENDPOINT  endpoint to verify (default: the app's transformEndpoint default)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFS="$REPO_ROOT/OpenSuperWhisper/Utils/AppPreferences.swift"
SERVICE="$REPO_ROOT/OpenSuperWhisper/TranslationService.swift"

CHECKS=0
FAILURES=0

pass() {
    CHECKS=$((CHECKS + 1))
    echo "  ok   $1"
}

fail() {
    CHECKS=$((CHECKS + 1))
    FAILURES=$((FAILURES + 1))
    echo "  FAIL $1"
}

check() { # description, 0 = ok
    if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1"; fi
}

die() {
    echo "ERROR: $1" >&2
    exit 2
}

# MARK: - Sources of truth (extracted from the app sources)

for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not on PATH"
done
[[ -f "$PREFS" ]] || die "cannot find $PREFS"
[[ -f "$SERVICE" ]] || die "cannot find $SERVICE"

pref_string() { # key
    sed -n "s/.*@UserDefault(key: \"$1\", defaultValue: \"\([^\"]*\)\").*/\1/p" "$PREFS" | head -1
}

pref_number() { # key
    sed -n "s/.*@UserDefault(key: \"$1\", defaultValue: \([0-9.]*\)).*/\1/p" "$PREFS" | head -1
}

# The body of systemPrompt(for:)'s multi-line literal, still carrying the
# \(tone.instruction) interpolation.
system_prompt_skeleton() {
    awk '
      /static func systemPrompt\(for tone: ToneMode\) -> String/ { in_func = 1; next }
      in_func && /^[[:space:]]*"""$/ { quotes++; next }
      in_func && quotes == 1 { sub(/^[[:space:]]{8}/, ""); print }
      in_func && quotes == 2 { exit }
    ' "$SERVICE"
}

tone_instruction() { # neutral|formal|casual
    awk '/var instruction: String \{/ { f = 1; next }
         f && /^    \}/ { exit }
         f && /case \./ { print }' "$SERVICE" \
        | sed -n "s/.*case \.$1: return \"\(.*\)\".*/\1/p" | head -1
}

MODEL="$(pref_string transformModel)"
ENDPOINT="$(pref_string transformEndpoint)"
TIMEOUT="$(pref_number transformTimeout)"
SKELETON="$(system_prompt_skeleton)"
INSTR_NEUTRAL="$(tone_instruction neutral)"
INSTR_FORMAL="$(tone_instruction formal)"
INSTR_CASUAL="$(tone_instruction casual)"

[[ -n "$MODEL" ]] || die "could not read transformModel default from $PREFS"
[[ -n "$ENDPOINT" ]] || die "could not read transformEndpoint default from $PREFS"
[[ -n "$TIMEOUT" ]] || die "could not read transformTimeout default from $PREFS"
[[ -n "$SKELETON" ]] || die "could not read systemPrompt literal from $SERVICE"
for instr in "$INSTR_NEUTRAL" "$INSTR_FORMAL" "$INSTR_CASUAL"; do
    [[ -n "$instr" ]] || die "could not read a ToneMode.instruction from $SERVICE"
done

ENDPOINT="${TRANSFORM_ENDPOINT:-$ENDPOINT}"
BASE_URL="${ENDPOINT%/chat/completions}"
END_THINK_TOKEN="$(printf '<%bend%bof%bthinking%b>' '\357\275\234' '\342\226\201' '\342\226\201' '\357\275\234')"
ASCII_REASONING_MARKER='|end_of_thinking|'
FULLWIDTH_BAR="$(printf '%b' '\357\275\234')"
PROMPT_PLACEHOLDER='\(tone.instruction)'

echo "Transform backend contract verification"
echo "  endpoint: $ENDPOINT"
echo "  model:    $MODEL"
echo "  timeout:  ${TIMEOUT}s"
echo ""

# MARK: - Request shape parity with TranslationService

echo "== request/response shape (TranslationService) =="
grep -q 'temperature: 0.2' "$SERVICE"
check "buildRequestBody sends temperature 0.2" $?
grep -q 'stream: false' "$SERVICE"
check "buildRequestBody sends stream false" $?
grep -qE 'chatTemplateKwargs: \["enable_thinking": false\]' "$SERVICE"
check "buildRequestBody sends chat_template_kwargs.enable_thinking = false" $?
grep -q 'case chatTemplateKwargs = "chat_template_kwargs"' "$SERVICE"
check "wire key is chat_template_kwargs" $?
grep -q 'role: "system"' "$SERVICE"
check "system message is first" $?
grep -q 'case reasoningContent = "reasoning_content"' "$SERVICE"
check "response reasoning_content is decoded" $?
case "$SKELETON" in
    *"$PROMPT_PLACEHOLDER"*)
        pass "systemPrompt literal interpolates ToneMode.instruction" ;;
    *)
        fail "systemPrompt literal no longer interpolates ToneMode.instruction" ;;
esac

# MARK: - Backend reachability and served model id

echo ""
echo "== backend =="
MODELS_JSON="$(curl -sS --max-time 10 "${BASE_URL}/models" 2>/dev/null)"
if [[ -z "$MODELS_JSON" ]]; then
    fail "GET ${BASE_URL}/models returned nothing (is Scripts/transform-server.sh running?)"
    echo ""
    echo "FAILURES: $FAILURES (checks: $CHECKS)"
    exit 1
fi
pass "GET ${BASE_URL}/models responded"
SERVED="$(printf '%s' "$MODELS_JSON" | jq -r '.data[].id' 2>/dev/null | tr '\n' ' ')"
echo "  served ids: ${SERVED:-<none>}"
if printf '%s' "$MODELS_JSON" | jq -e --arg m "$MODEL" '.data | map(.id) | index($m) != null' >/dev/null 2>&1; then
    pass "the app's transformModel default ($MODEL) is served"
else
    fail "the app's transformModel default ($MODEL) is NOT served"
fi

# MARK: - Request/response helpers

# Builds the app's exact body and issues the request. Sets RESP_CODE,
# RESP_TIME and RESPONSE_BODY in the caller's shell.
send() { # tone, text
    local tone="$1" text="$2" instr prompt meta
    case "$tone" in
        neutral) instr="$INSTR_NEUTRAL" ;;
        formal) instr="$INSTR_FORMAL" ;;
        casual) instr="$INSTR_CASUAL" ;;
        *) die "unknown tone: $tone" ;;
    esac
    prompt="${SKELETON//"$PROMPT_PLACEHOLDER"/$instr}"
    [[ "$prompt" == *"$instr"* ]] || die "system prompt does not carry the $tone tone instruction"

    LAST_BODY="$(jq -cn --arg model "$MODEL" --arg sys "$prompt" --arg user "$text" \
        '{model: $model,
          messages: [{role: "system", content: $sys}, {role: "user", content: $user}],
          temperature: 0.2,
          stream: false,
          chat_template_kwargs: {enable_thinking: false}}')"

    meta="$(curl -sS --max-time 120 -o "$RESPONSE_FILE" -w '%{http_code} %{time_total}' \
        -H 'Content-Type: application/json' --data-binary "$LAST_BODY" "$ENDPOINT")"
    RESP_CODE="${meta%% *}"
    RESP_TIME="${meta##* }"
    RESPONSE_BODY="$(cat "$RESPONSE_FILE")"
}

# Mirrors TranslationService.stripReasoning(from:).
strip_reasoning() { # text
    jq -rn --arg c "$1" '($c
        | gsub("(?is)<think>.*?<\\|end_of_thinking\\|>"; "")
        | gsub("(?is)<think>.*?</think>"; "")
        | gsub("(?is)<think>.*"; "")
        | gsub("(?is)<thinking>.*?</thinking>"; "")
        | gsub("(?is)<reasoning>.*?</reasoning>"; "")
        | gsub("(?is)<thinking>.*"; "")
        | gsub("(?is)<reasoning>.*"; "")
        | gsub("<\\|end_of_thinking\\|>"; "")
        | gsub("(?is)</think>|</thinking>|</reasoning>"; "")
        | sub("^\\s+"; "") | sub("\\s+$"; ""))'
}

RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$RESPONSE_FILE"' EXIT

LATENCIES=()
SHORT_LATENCIES=()

# Asserts a raw assistant message carries no reasoning traces and that the
# app's stripReasoning is a no-op on it.
assert_no_reasoning() { # label, content, reasoning_content
    local label="$1" content="$2" reasoning="$3" stripped trimmed

    [[ -n "$reasoning" ]] && fail "$label: response carries reasoning_content" \
                         || pass "$label: no reasoning_content payload"

    printf '%s' "$content" | grep -qF "$END_THINK_TOKEN" \
        && fail "$label: content contains the Qwen3 end-of-thinking token" \
        || pass "$label: no Qwen3 end-of-thinking token"
    printf '%s' "$content" | grep -qF "$FULLWIDTH_BAR" \
        && fail "$label: content contains a U+FF5C reasoning delimiter" \
        || pass "$label: no U+FF5C reasoning delimiter"
    printf '%s' "$content" | grep -qiE '</?(think|thinking|reasoning)>' \
        && fail "$label: content contains a reasoning tag" \
        || pass "$label: no reasoning tags"
    printf '%s' "$content" | grep -qF "$ASCII_REASONING_MARKER" \
        && fail "$label: content contains an ASCII |end_of_thinking| marker" \
        || pass "$label: no ASCII end-of-thinking marker"

    stripped="$(strip_reasoning "$content")"
    trimmed="$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ "$stripped" == "$trimmed" ]] \
        && pass "$label: stripReasoning is a no-op (nothing to strip)" \
        || fail "$label: stripReasoning changed the content"
}

# Asserts one response satisfies the app's expectations.
verify_response() { # label, http_code, latency, pl_text
    local label="$1" code="$2" latency="$3" pl="$4"
    local content reasoning stripped too_slow

    [[ "$code" == "200" ]] && pass "$label: HTTP 200" || fail "$label: HTTP $code"

    if ! printf '%s' "$RESPONSE_BODY" | jq -e '(.choices | type == "array") and (.choices | length > 0)' >/dev/null 2>&1; then
        fail "$label: response has no choices (parseContent would throw)"
        return
    fi

    content="$(printf '%s' "$RESPONSE_BODY" | jq -r '.choices[0].message.content // empty')"
    reasoning="$(printf '%s' "$RESPONSE_BODY" | jq -r '.choices[0].message.reasoning_content // empty')"
    assert_no_reasoning "$label" "$content" "$reasoning"

    stripped="$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "$stripped" ]]; then
        fail "$label: parseContent would return emptyResponse"
    else
        pass "$label: parseContent yields non-empty text"
    fi

    [[ "$stripped" == "$pl" ]] && fail "$label: output is the untranslated input" \
                                || pass "$label: output differs from the Polish input"

    too_slow="$(jq -rn --argjson l "$latency" --argjson t "$TIMEOUT" 'if $l >= $t then 1 else 0 end')"
    [[ "$too_slow" == "0" ]] && pass "$label: ${latency}s is under the app's ${TIMEOUT}s timeout" \
                             || fail "$label: ${latency}s exceeds the app's ${TIMEOUT}s timeout"

    echo "       content: $stripped"
}

# MARK: - Translations (neutral tone, the shipped default)

echo ""
echo "== translations (neutral tone) =="
SENTENCES=(
    "Cześć, jak się masz?"
    "Musimy omówić budżet na przyszły kwartał."
    "Nie mogę dzisiaj przyjść na spotkanie, przepraszam."
    "Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę."
    "Zamknij okno, bo jest zimno na dworze."
    "Jutro rano jadę do Krakowa pociągiem o siódmej."
    "Dzień dobry. Dzwonię w sprawie zamówienia numer czterysta dwadzieścia trzy. Niestety nie otrzymałem jeszcze potwierdzenia wysyłki. Czy mógłby pan sprawdzić status i powiedzieć mi, kiedy paczka dotrze? Zależy mi na czasie, ponieważ to prezent na urodziny mojej siostry."
)

index=0
for pl in "${SENTENCES[@]}"; do
    index=$((index + 1))
    send neutral "$pl"
    echo "[$index] PL: $pl"
    verify_response "sentence $index" "$RESP_CODE" "$RESP_TIME" "$pl"
    echo "       latency: ${RESP_TIME}s"
    LATENCIES+=("$RESP_TIME")
    [[ $index -le 6 ]] && SHORT_LATENCIES+=("$RESP_TIME")
    echo ""
done

# MARK: - Tone separation (formal vs casual, same input)

echo "== tone separation (same Polish sentence) =="
TONE_PROBE="Nie mogę dzisiaj przyjść na spotkanie, przepraszam."
TONE_SAMPLES=3
echo "PL: $TONE_PROBE"

# Contractions and informal wording are casual register markers; the expanded
# (non-contracted) and deferential forms are formal register markers.
CASUAL_MARKERS="[A-Za-z]+'(s|t|re|ll|ve|d|m)\b|hey|yeah|gonna|wanna|kinda|sorta|chilly|hang on|no worries|catch up"
FORMAL_MARKERS="\bI am\b|\bwe are\b|\bwe must\b|\bcannot\b|unable to|as it is|\bdo not\b|\bplease\b|\bkindly\b|\bshall\b|\bI will\b|\bwe will\b|\bit is\b"

FORMAL_OUTPUTS=()
CASUAL_OUTPUTS=()
FORMAL_CASUAL_HITS=0
CASUAL_HITS=0
FORMAL_HITS=0

collect_tone() { # tone, count
    local tone="$1" count="$2" i content reasoning hits
    for i in $(seq 1 "$count"); do
        send "$tone" "$TONE_PROBE"
        content="$(printf '%s' "$RESPONSE_BODY" | jq -r '.choices[0].message.content // empty')"
        reasoning="$(printf '%s' "$RESPONSE_BODY" | jq -r '.choices[0].message.reasoning_content // empty')"

        [[ "$RESP_CODE" == "200" ]] && pass "$tone[$i]: HTTP 200" || fail "$tone[$i]: HTTP $RESP_CODE"
        assert_no_reasoning "$tone[$i]" "$content" "$reasoning"
        [[ -n "$(printf '%s' "$content" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" ]] \
            && pass "$tone[$i]: parseContent yields non-empty text" \
            || fail "$tone[$i]: parseContent would return emptyResponse"

        echo "       $tone[$i]: $content"
        if [[ "$tone" == "formal" ]]; then
            FORMAL_OUTPUTS+=("$content")
            hits="$(printf '%s' "$content" | grep -Eci "$CASUAL_MARKERS")"
            FORMAL_CASUAL_HITS=$((FORMAL_CASUAL_HITS + hits))
            hits="$(printf '%s' "$content" | grep -Eci "$FORMAL_MARKERS")"
            FORMAL_HITS=$((FORMAL_HITS + hits))
        else
            CASUAL_OUTPUTS+=("$content")
            hits="$(printf '%s' "$content" | grep -Eci "$CASUAL_MARKERS")"
            CASUAL_HITS=$((CASUAL_HITS + hits))
        fi

        LATENCIES+=("$RESP_TIME")
        SHORT_LATENCIES+=("$RESP_TIME")
    done
}

collect_tone formal "$TONE_SAMPLES"
echo ""
collect_tone casual "$TONE_SAMPLES"
echo ""

echo "  casual register markers: formal=${FORMAL_CASUAL_HITS}/${TONE_SAMPLES} casual=${CASUAL_HITS}/${TONE_SAMPLES}"
echo "  formal register markers: formal=${FORMAL_HITS}/${TONE_SAMPLES}"

[[ "$FORMAL_CASUAL_HITS" == "0" ]] \
    && pass "formal output never uses casual register markers" \
    || fail "formal output uses casual register markers"
[[ "$CASUAL_HITS" -ge "$TONE_SAMPLES" ]] \
    && pass "every casual output uses casual register markers" \
    || fail "only $CASUAL_HITS/$TONE_SAMPLES casual outputs use casual register markers"
[[ "$FORMAL_HITS" -ge "$TONE_SAMPLES" ]] \
    && pass "every formal output uses formal register markers" \
    || fail "only $FORMAL_HITS/$TONE_SAMPLES formal outputs use formal register markers"

OVERLAP=0
for f in "${FORMAL_OUTPUTS[@]}"; do
    for c in "${CASUAL_OUTPUTS[@]}"; do
        [[ "$f" == "$c" ]] && OVERLAP=$((OVERLAP + 1))
    done
done
[[ "$OVERLAP" == "0" ]] \
    && pass "formal and casual produce disjoint outputs for the same input" \
    || fail "formal and casual produced $OVERLAP identical output pair(s)"

# MARK: - Latency summary

echo ""
echo "== latency =="
stats="$(printf '%s\n' "${LATENCIES[@]}" | jq -Rn '[inputs | tonumber] | "n=\(length) min=\(min) mean=\((add / length) * 100 | round / 100) max=\(max)"')"
echo "  all requests: $stats"
short_stats="$(printf '%s\n' "${SHORT_LATENCIES[@]}" | jq -Rn '[inputs | tonumber] | "n=\(length) min=\(min) mean=\((add / length) * 100 | round / 100) max=\(max)"')"
echo "  short utterances: $short_stats"

over_target="$(printf '%s\n' "${SHORT_LATENCIES[@]}" | jq -Rn '[inputs | tonumber] | map(select(. > 3)) | length')"
[[ "$over_target" == "0" ]] \
    && pass "every short utterance met the plan's ~1-3s target" \
    || fail "$over_target short utterance(s) exceeded the plan's ~3s target"

echo ""
if [[ "$FAILURES" -eq 0 ]]; then
    echo "ALL CHECKS PASSED (checks: $CHECKS)"
    exit 0
fi
echo "FAILURES: $FAILURES (checks: $CHECKS)"
exit 1
