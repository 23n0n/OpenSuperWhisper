#!/usr/bin/env python3
"""A/B the tone system prompt against the real weights, over llama-server.

Old prompt = exactly what TransformService.systemPrompt() composes today.
New prompt = the proposed replacement (fleet/data/fm-20260924-10/tone-prompt.md).
Fidelity to the app: temperature 0.2, top-k 40, top-p 0.95, min-p 0.05, no thinking.
"""
import json
import subprocess
import sys
import time
import urllib.request

MODEL = sys.argv[1]
LANGUAGE = sys.argv[2]
PORT = 1919

def servers_up():
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
            return json.load(r).get("status") == "ok"
    except Exception:
        return False

def compose_old(tone, language, transcript):
    tone_line = {
        "formal": "Use a formal, professional tone.",
        "casual": "Use a casual, conversational tone.",
        "neutral": "Keep a neutral, natural tone.",
    }[tone]
    system = (
        f"You are a dictation editor. The user dictated {language} text. "
        f"Rewrite it in a {tone} tone — keep its language exactly {language}, never translate it, "
        f"and keep every fact, name and number exactly as dictated. Change the register and nothing else. "
        f"{tone_line}\n"
        f"Output ONLY the final {language} text, with no quotes, labels, or explanation.\n/no_think"
    )
    return system, transcript

def compose_new(tone, language, transcript):
    system = f"""You rewrite dictated text. You are not an assistant: never answer it, greet, acknowledge, thank, comment, explain, summarise or continue it.

The user dictated {language} text. Rewrite it in a {tone} register, in {language}. Nothing else may change.

What the register may change — only these:
- formal: write complete sentences, no contractions ("do not", not "don't"), no slang or filler, polite and professional word choice.
- casual: use contractions, everyday words, direct and relaxed phrasing.
- neutral: change as little as possible; fix only what is unclear or ragged.

What must stay exactly as dictated:
- every fact, name, number, date, place, product and technical term — never add, never drop, never reword a commitment into a softer or stronger one;
- who is speaking and to whom: first person stays first person, a question stays a question, an order stays an order;
- the order and the completeness of the information — never summarise, never elaborate, never finish a half-sentence with new content;
- the language: {language} in, {language} out. Never translate, not even one word. If a term has no {language} equivalent, keep it exactly as spoken.

Output rules:
- Output only the rewritten text. No quotes, no labels, no preamble, no closing remark, no markdown, no commentary, no explanation of what you changed.
- Keep the dictated line breaks: do not join separate lines, do not split one line.
- If the text is already in the {tone} register, return it unchanged.
- If the text is a fragment, a list, or noise that carries no sentence, return it as it is.
/no_think"""
    user = (
        f"Rewrite this dictated text in a {tone} register. Keep its language ({language}), the speaker, "
        f"every fact and every number exactly as dictated. Output only the rewritten text.\n\n"
        f"<<<TRANSCRIPT\n{transcript}\nTRANSCRIPT>>>"
    )
    return system, user

REGISTER = {
    "formal": "complete sentences, no contractions, no slang, polite professional wording",
    "casual": "contractions, everyday wording, direct and relaxed",
    "neutral": "as little change as possible",
}

def compose_v2(tone, language, transcript):
    system = f"""Rewrite the user's text. Do not answer it.

Reply with the rewritten text and nothing else. No introduction, no explanation, no quotes, no labels,
no markdown, no note about the register.

- Language: keep the language exactly as it is. Never translate a word.
- Facts: keep every fact, name, number and term. Add nothing, drop nothing, summarise nothing, finish nothing.
- Speaker: first person stays first person; a question stays a question; an order stays an order.
- Register: {tone} ({REGISTER[tone]}). Change only the wording that the register requires.
- If the text already has this register, repeat it unchanged.
- Keep the line breaks."""
    user = f"Register: {tone}\nText:\n{transcript}"
    return system, user

def ask(system, user, temperature=0.2):
    body = json.dumps({
        "model": "local",
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": temperature, "top_k": 40, "top_p": 0.95, "min_p": 0.05,
        "max_tokens": 220, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.load(r)
    return data["choices"][0]["message"]["content"].strip()

CASES = json.loads(sys.argv[3])

server = subprocess.Popen(
    ["llama-server", "-m", MODEL, "--port", str(PORT), "--host", "127.0.0.1",
     "-c", "4096", "-t", "6", "--temp", "0.2", "--top-k", "40", "--top-p", "0.95", "--min-p", "0.05"],
    stdout=open(f"/tmp/tone-ab-{LANGUAGE}-server.log", "w"), stderr=subprocess.STDOUT)
try:
    for _ in range(120):
        if servers_up():
            break
        time.sleep(1)
    else:
        print("server never became ready"); sys.exit(1)
    for case in CASES:
        tone, transcript = case["tone"], case["text"]
        os_, ou = compose_old(tone, LANGUAGE, transcript)
        ns, nu = compose_new(tone, LANGUAGE, transcript)
        vs, vu = compose_v2(tone, LANGUAGE, transcript)
        old = ask(os_, ou)
        new = ask(ns, nu)
        v2 = ask(vs, vu, temperature=0.0)
        print("=" * 100)
        print(f"[{tone}] in : {transcript}")
        print(f"      old(0.2): {old}")
        print(f"      v1 (0.2): {new}")
        print(f"      v2 (0.0): {v2}")
finally:
    server.terminate()
    try:
        server.wait(timeout=15)
    except subprocess.TimeoutExpired:
        server.kill()
