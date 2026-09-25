#!/usr/bin/env python3
"""Measure the SHIPPED tone route: the system prompt is composed byte-for-byte as
`TransformService.systemPrompt(for: .tone(...), cleanUp: false)` composes it on
branch fm/tone-output @ 9c36eae, and the user turn as
`TransformService.userPrompt(for:language:tone:)` composes it.

The pinned harness `tone-ab.py` reproduces the *proposal* from
`fm-20260924-10/tone-prompt.md`; it differs from the landed code in two places
(it lists all three register definitions, and it does not carry the code's
trailing "Output ONLY the final <language> text ..." line). This driver exists so
the measurement is about what the branch actually sends. Run with --verify to
diff the reconstructed prompt against the landed prompt printed by the real
compiled service (evidence/service-checks.txt).

Sampling is the app's: temperature 0.2, top-k 40, top-p 0.95, min-p 0.05,
chat_template_kwargs.enable_thinking = false.

Usage: tone-measure.py <model.gguf> <english|polish> <cases.json> <out.json>
       tone-measure.py --verify
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

PORT = 1919

REGISTER = {
    "neutral": ("Neutral", "change as little as possible; fix only what is unclear or ragged."),
    "formal": ("Formal", 'write complete sentences, no contractions ("do not", not "don\'t"), '
                         'no slang or filler, polite and professional word choice.'),
    "casual": ("Casual", "use contractions, everyday words, direct and relaxed phrasing."),
}

DISPLAY = {"english": "English", "polish": "Polish"}


def tone_instruction(language, tone):
    """TransformService.toneInstruction(for:tone:) — Swift multiline literal."""
    name = DISPLAY[language]
    register = REGISTER[tone][0].lower()
    return "\n".join([
        "You rewrite dictated text. You are not an assistant: never answer it, greet, acknowledge, "
        "thank, comment, explain, summarise or continue it.",
        "",
        f"The user dictated {name} text. Rewrite it in a {register} register, in {name}. "
        "Nothing else may change.",
        "",
        "What the register may change — only these:",
        f"- {register}: {REGISTER[tone][1]}",
        "",
        "What must stay exactly as dictated:",
        "- every fact, name, number, date, place, product and technical term — never add, never "
        "drop, never reword a commitment into a softer or stronger one;",
        "- who is speaking and to whom: first person stays first person, a question stays a "
        "question, an order stays an order;",
        "- the order and the completeness of the information — never summarise, never elaborate, "
        "never finish a half-sentence with new content;",
        f"- the language: {name} in, {name} out. Never translate, not even one word. If a term "
        f"has no {name} equivalent, keep it exactly as spoken.",
        "",
        "Output rules:",
        "- Output only the rewritten text. No quotes, no labels, no preamble, no closing remark, "
        "no markdown, no commentary, no explanation of what you changed.",
        "- Keep the dictated line breaks: do not join separate lines, do not split one line.",
        f"- If the text is already in the {register} register, return it unchanged.",
        "- If the text is a fragment, a list, or noise that carries no sentence, return it as it is.",
    ])


def compose_new(language, tone, transcript):
    """TransformService.systemPrompt + userPrompt as landed."""
    name = DISPLAY[language]
    system = "\n".join([
        tone_instruction(language, tone),
        f"Output ONLY the final {name} text, with no quotes, labels, or explanation.",
        "/no_think",
    ])
    register = REGISTER[tone][0].lower()
    user = (
        f"Rewrite this dictated text in a {register} register. Keep its language ({name}), the "
        f"speaker, every fact and every number exactly as dictated. Output only the rewritten text.\n"
        f"\n"
        f"<<<TRANSCRIPT\n{transcript}\nTRANSCRIPT>>>"
    )
    return system, user


def compose_old(language, tone, transcript):
    """The wording this branch replaced — verbatim from the pinned tone-ab.py."""
    name = DISPLAY[language]
    tone_line = {
        "formal": "Use a formal, professional tone.",
        "casual": "Use a casual, conversational tone.",
        "neutral": "Keep a neutral, natural tone.",
    }[tone]
    system = (
        f"You are a dictation editor. The user dictated {name} text. "
        f"Rewrite it in a {tone} tone — keep its language exactly {name}, never translate it, "
        f"and keep every fact, name and number exactly as dictated. Change the register and nothing else. "
        f"{tone_line}\n"
        f"Output ONLY the final {name} text, with no quotes, labels, or explanation.\n/no_think"
    )
    return system, transcript


def verify():
    """Diff the reconstruction against the landed prompt printed by the real service."""
    path = ("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260924-11/"
            "evidence/service-checks.txt")
    text = open(path, encoding="utf-8").read()
    start = text.index("=== the system prompt a Polish formal tone turn sends ===\n")
    start = text.index("\n", start) + 1
    end = text.index("\n=== the framed user turn ===")
    landed = text[start:end]
    landed_user_start = text.index("=== the framed user turn ===\n")
    landed_user_start = text.index("\n", landed_user_start) + 1
    landed_user_end = text.index("\n=== the system prompt clean-up alone sends", landed_user_start)
    landed_user = text[landed_user_start:landed_user_end]

    probe = "wyślij raport do klienta dzisiaj"
    mine, my_user = compose_new("polish", "formal", probe)
    print("system prompt reconstruction == landed code:", mine == landed)
    print("user turn reconstruction == landed code:", my_user == landed_user)
    if mine != landed:
        import difflib
        print("\n".join(difflib.unified_diff(landed.split("\n"), mine.split("\n"),
                                             "landed", "reconstructed", lineterm="")))
    if my_user != landed_user:
        import difflib
        print("\n".join(difflib.unified_diff(landed_user.split("\n"), my_user.split("\n"),
                                             "landed", "reconstructed", lineterm="")))
    # and the pinned harness's own proposal, so the delta is on the record
    src = open("/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260924-11/"
               "evidence/tone-ab.py", encoding="utf-8").read()
    ns = {}
    exec(compile(src.split("CASES = json.loads")[0].replace(
        "MODEL = sys.argv[1]", "MODEL = 'x'").replace("LANGUAGE = sys.argv[2]", "LANGUAGE = 'Polish'"),
        "tone-ab.py", "exec"), ns)
    pinned_system, pinned_user = ns["compose_new"]("formal", "Polish", probe)
    print("pinned harness proposal == landed code:", pinned_system == landed)
    print("pinned harness user turn == landed user turn:", pinned_user == landed_user)
    return mine == landed and my_user == landed_user


def servers_up():
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2) as r:
            return json.load(r).get("status") == "ok"
    except Exception:
        return False


def ask(system, user):
    body = json.dumps({
        "model": "local",
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": 0.2, "top_k": 40, "top_p": 0.95, "min_p": 0.05,
        "max_tokens": 220, "stream": False,
        "chat_template_kwargs": {"enable_thinking": False},
    }).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{PORT}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"})
    started = time.monotonic()
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.load(r)
    elapsed = time.monotonic() - started
    return data["choices"][0]["message"]["content"].strip(), round(elapsed, 2)


def main():
    MODEL, LANGUAGE, CASES_ARG, OUT = sys.argv[1:5]
    if os.path.exists(CASES_ARG):
        cases = json.load(open(CASES_ARG, encoding="utf-8"))
    else:
        cases = json.loads(CASES_ARG)
    server = subprocess.Popen(
        ["llama-server", "-m", MODEL, "--port", str(PORT), "--host", "127.0.0.1",
         "-c", "4096", "-t", "6", "--temp", "0.2", "--top-k", "40", "--top-p", "0.95",
         "--min-p", "0.05"],
        stdout=open(f"/tmp/fm11r/server-{LANGUAGE}-{MODEL.split('/')[-1]}.log", "w"),
        stderr=subprocess.STDOUT)
    rows = []
    try:
        for _ in range(240):
            if servers_up():
                break
            time.sleep(1)
        else:
            print("server never became ready")
            sys.exit(1)
        for case in cases:
            tone, transcript = case["tone"], case["text"]
            for variant, (system, user) in (("old", compose_old(LANGUAGE, tone, transcript)),
                                            ("new", compose_new(LANGUAGE, tone, transcript))):
                out, seconds = ask(system, user)
                rows.append({
                    "case": case.get("id", transcript[:40]),
                    "case_note": case.get("note", ""),
                    "language": LANGUAGE,
                    "model": MODEL.split("/")[-1],
                    "tone": tone,
                    "variant": variant,
                    "input": transcript,
                    "output": out,
                    "seconds": seconds,
                })
                print(f"{len(rows):3d} {case.get('id','')} {tone} {variant} {seconds}s "
                      f"-> {out[:80]!r}", flush=True)
    finally:
        server.terminate()
        try:
            server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.kill()
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(rows, fh, ensure_ascii=False, indent=1)
    print(f"wrote {OUT} ({len(rows)} rows)")


if __name__ == "__main__":
    if sys.argv[1:2] == ["--verify"]:
        sys.exit(0 if verify() else 1)
    main()
