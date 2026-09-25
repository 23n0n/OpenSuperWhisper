#!/usr/bin/env python3
"""fm-20260925-13 — the tone-prompt round.

Runs the SHIPPED prompt (the control) and three candidates over llama-server with
the app's exact sampling, over the same 28 Polish cases the landed measurement
used (the captain's 7 real dictations x 3 registers, plus 7 adversarial), so the
rows compare directly with fm-20260924-11/report.md.

Variants:
  control        TransformService.systemPrompt/userPrompt as landed (byte-proof:
                 compare with bin/prompt-harness, which prints the real code's output)
  pl-instruction the whole instruction block in Polish, for Polish dictation only
                 (English stays English)
  example        one worked input->output pair in the same language and register,
                 appended to the system prompt
  selfcheck      one explicit self-check line appended to the system prompt

Usage:
  tone-round.py --verify                       # control == compiled service, byte for byte
  tone-round.py <model.gguf> <english|polish> <cases.json> <out.json> [runs]
"""
import importlib.util
import json
import os
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 1919
RUNS = 2

_spec = importlib.util.spec_from_file_location("tone_measure", os.path.join(HERE, "tone-measure.py"))
tone_measure = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(tone_measure)

REGISTER = tone_measure.REGISTER
DISPLAY = tone_measure.DISPLAY


# ---------------------------------------------------------------- control

def compose_control(language, tone, transcript):
    return tone_measure.compose_new(language, tone, transcript)


def _control_lines(language, tone):
    """The exact lines systemPrompt() joins, so an insertion can be placed where
    the Swift would append it."""
    name = DISPLAY[language]
    return [
        tone_measure.tone_instruction(language, tone),
        f"Output ONLY the final {name} text, with no quotes, labels, or explanation.",
        "/no_think",
    ]


def _with_block(language, tone, transcript, block):
    """systemPrompt() with one extra element appended after the instruction, the
    way `lines.append(...)` would place it."""
    lines = _control_lines(language, tone)
    lines.insert(len(lines) - 2, block)
    system = "\n".join(lines)
    return system, tone_measure.compose_new(language, tone, transcript)[1]


# ------------------------------------------------------- candidate: example

EXAMPLES = {
    "polish": {
        "formal": ("wyślij to do niego dzisiaj i daj mi znać jak odpowie",
                   "Proszę wysłać to do niego dzisiaj i dać mi znać, jak odpowie."),
        "casual": ("Proszę o przesłanie raportu do klienta jeszcze dziś.",
                   "Wyślij raport do klienta jeszcze dziś."),
        "neutral": ("Spotkanie jest jutro o dziesiątej rano.",
                    "Spotkanie jest jutro o dziesiątej rano."),
    },
    "english": {
        "formal": ("send it to him today and let me know what he says",
                   "Please send it to him today and let me know what he says."),
        "casual": ("Please transmit the report to the client today.",
                   "Send the report to the client today."),
        "neutral": ("The meeting is tomorrow at ten in the morning.",
                    "The meeting is tomorrow at ten in the morning."),
    },
}


def example_block(language, tone):
    source, target = EXAMPLES[language][tone]
    return ("One example of the rewrite asked for — the register changes, every content word "
            "stays:\n"
            f"input: {source}\n"
            f"output: {target}")


def compose_example(language, tone, transcript):
    return _with_block(language, tone, transcript, example_block(language, tone))


# -------------------------------------------------------- candidate: selfcheck

SELF_CHECK = ("Before you answer, check your rewrite against the dictation: every noun, number and "
              "proper noun of the dictation must appear in your answer, and your answer must contain "
              "nothing the dictation did not say. Fix the answer before you output it.")


def compose_selfcheck(language, tone, transcript):
    return _with_block(language, tone, transcript, SELF_CHECK)


# ---------------------------------------------------- candidate: pl-instruction

PL_REGISTER = {
    "formal": "formalny",
    "casual": "potoczny",
    "neutral": "neutralny",
}

# The same adjective where Polish needs the locative ("w rejestrze formalnym").
PL_REGISTER_LOCATIVE = {
    "formal": "formalnym",
    "casual": "potocznym",
    "neutral": "neutralnym",
}

PL_DEFINITION = {
    "formal": "pisz pełnymi zdaniami, bez skrótów, bez slangu i wypełniaczy, grzecznie i "
              "profesjonalnie.",
    "casual": "używaj form potocznych, codziennych słów, bezpośrednich i swobodnych sformułowań.",
    "neutral": "zmieniaj jak najmniej; popraw tylko to, co jest niejasne lub niezgrabne.",
}


def pl_instruction(tone):
    register = PL_REGISTER[tone]
    register_locative = PL_REGISTER_LOCATIVE[tone]
    return "\n".join([
        "Przepisujesz podyktowany tekst. Nie jesteś asystentem: nigdy nie odpowiadaj na niego, "
        "nie pozdrawiaj, nie potwierdzaj, nie dziękuj, nie komentuj, nie wyjaśniaj, nie streszczaj "
        "i nie kontynuuj go.",
        "",
        f"Użytkownik podyktował tekst po polsku. Przepisz go w rejestrze {register_locative}, "
        "po polsku. Nic innego nie może się zmienić.",
        "",
        "Co może zmienić rejestr — tylko to:",
        f"- {register}: {PL_DEFINITION[tone]}",
        "",
        "Co musi zostać dokładnie tak, jak podyktowano:",
        "- każdy fakt, nazwa, liczba, data, miejsce, produkt i termin techniczny — nigdy nie "
        "dodawaj, nigdy nie usuwaj, nigdy nie przeformułowuj zobowiązania na łagodniejsze ani "
        "ostrzejsze;",
        "- kto mówi i do kogo: pierwsza osoba zostaje pierwszą osobą, pytanie zostaje pytaniem, "
        "polecenie zostaje poleceniem;",
        "- kolejność i kompletność informacji — nigdy nie streszczaj, nigdy nie rozwijaj, nigdy "
        "nie kończ niedokończonego zdania nową treścią;",
        "- język: polski na wejściu, polski na wyjściu. Nigdy nie tłumacz, ani jednego słowa. "
        "Jeśli termin nie ma polskiego odpowiednika, zachowaj go dokładnie tak, jak został "
        "wypowiedziany.",
        "",
        "Zasady wyniku:",
        "- Podaj wyłącznie przepisany tekst. Bez cudzysłowów, bez etykiet, bez wstępu, bez uwagi "
        "na koniec, bez markdownu, bez komentarza, bez wyjaśniania, co zmieniłeś.",
        "- Zachowaj podziały wierszy: nie łącz osobnych wierszy, nie dziel jednego wiersza.",
        f"- Jeśli tekst jest już w rejestrze {register_locative}, zwróć go bez zmian.",
        "- Jeśli tekst to fragment, lista albo szum bez zdania, zwróć go takim, jaki jest.",
        "Podaj WYŁĄCZNIE końcowy tekst po polsku, bez cudzysłowów, etykiet i wyjaśnień.",
        "/no_think",
    ])


def compose_pl_instruction(language, tone, transcript):
    if language == "polish":
        system = pl_instruction(tone)
        user = (
            f"Przepisz ten podyktowany tekst w rejestrze {PL_REGISTER_LOCATIVE[tone]}. Zachowaj jego "
            "język (polski), osobę mówiącą, każdy fakt i każdą liczbę dokładnie tak, jak "
            "podyktowano. Podaj wyłącznie przepisany tekst.\n"
            "\n"
            f"<<<TRANSCRIPT\n{transcript}\nTRANSCRIPT>>>"
        )
        return system, user
    return tone_measure.compose_new(language, tone, transcript)


# ------------------------------------- candidate: pl-instruction, no echoed frame
#
# The Polish block makes the model echo the closing delimiter on some short
# dictations (`…po polsku.\nTRANSCRIPT`), which is a word the dictation never had.
# Two ways to forbid it, both prompt-only: (a) without naming the markers, so the
# instruction cannot prime them, (b) naming them, which is the most literal
# reading of the fix and is what the frequency claim has to survive.

PL_NO_MARKERS = ("W odpowiedzi ma być wyłącznie przepisany tekst — bez żadnych znaczników, "
                 "etykiet ani słów spoza podyktowanego tekstu.")


def pl_no_echo_markers(tone):
    return "\n".join([
        pl_instruction(tone).rsplit("\n", 2)[0],
        PL_NO_MARKERS,
        "Podaj WYŁĄCZNIE końcowy tekst po polsku, bez cudzysłowów, etykiet i wyjaśnień.",
        "/no_think",
    ])


def pl_no_echo_named(tone):
    return "\n".join([
        pl_instruction(tone).rsplit("\n", 2)[0],
        "Nie powtarzaj znaczników „<<<TRANSCRIPT” ani „TRANSCRIPT>>>” — podaj wyłącznie "
        "przepisany tekst, nic więcej.",
        "Podaj WYŁĄCZNIE końcowy tekst po polsku, bez cudzysłowów, etykiet i wyjaśnień.",
        "/no_think",
    ])


def compose_pl_no_echo(instruction):
    def compose(language, tone, transcript):
        if language == "polish":
            return instruction(tone), compose_pl_instruction(language, tone, transcript)[1]
        return tone_measure.compose_new(language, tone, transcript)
    return compose


VARIANTS = {
    "control": compose_control,
    "pl-instruction": compose_pl_instruction,
    "pl-no-echo": compose_pl_no_echo(pl_no_echo_markers),
    "pl-no-echo-named": compose_pl_no_echo(pl_no_echo_named),
    "example": compose_example,
    "selfcheck": compose_selfcheck,
}


def verify():
    """The control and the candidates' shared parts against the REAL compiled
    service's own output (bin/prompt-harness prints TransformService's prompts)."""
    path = os.environ.get("PROMPT_HARNESS_JSON", "/tmp/fm13-prompt.json")
    if not os.path.exists(path):
        subprocess.run([os.path.join(HERE, "bin", "prompt-harness")],
                       stdout=open(path, "w"), check=True)
    real = json.load(open(path, encoding="utf-8"))
    import difflib
    ok = True
    for language in ("english", "polish"):
        probe = real["probe"] if language == "polish" else real["probeEnglish"]
        for tone in ("neutral", "formal", "casual"):
            system, user = compose_control(language, tone, probe)
            same_system = system == real["systems"][f"tone/{language}/{tone}"]
            same_user = user == real["users"][f"{language}/{tone}"]
            ok = ok and same_system and same_user
            print(f"{'OK ' if same_system else 'BAD'} control system {language}/{tone}")
            print(f"{'OK ' if same_user else 'BAD'} control user   {language}/{tone}")
            for good, mine, theirs, label in ((same_system, system,
                                               real["systems"][f"tone/{language}/{tone}"], "system"),
                                              (same_user, user,
                                               real["users"][f"{language}/{tone}"], "user")):
                if not good:
                    print("\n".join(difflib.unified_diff(
                        theirs.split("\n"), mine.split("\n"), "compiled", "python", lineterm="")))
            # the control must be exactly the join of the lines systemPrompt() joins,
            # which is what places an inserted block where the Swift would.
            if system != "\n".join(_control_lines(language, tone)):
                ok = False
                print(f"BAD {language}/{tone}: control system is not the joined lines")
    print("CONTROL == COMPILED SERVICE:", ok)
    return ok


# ------------------------------------------------------------------ runner

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
    with urllib.request.urlopen(req, timeout=300) as r:
        data = json.load(r)
    return data["choices"][0]["message"]["content"].strip(), round(time.monotonic() - started, 2)


def main():
    MODEL, LANGUAGE, CASES_ARG, OUT = sys.argv[1:5]
    runs = int(sys.argv[5]) if len(sys.argv) > 5 else RUNS
    only = sys.argv[6].split(",") if len(sys.argv) > 6 else list(VARIANTS)
    cases = json.load(open(CASES_ARG, encoding="utf-8"))
    server = subprocess.Popen(
        ["llama-server", "-m", MODEL, "--port", str(PORT), "--host", "127.0.0.1",
         "-c", "4096", "-t", "6", "--temp", "0.2", "--top-k", "40", "--top-p", "0.95",
         "--min-p", "0.05"],
        stdout=open(f"/tmp/fm13-server-{LANGUAGE}-{os.path.basename(MODEL)}.log", "w"),
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
            for run in range(1, runs + 1):
                for variant in only:
                    system, user = VARIANTS[variant](LANGUAGE, tone, transcript)
                    out, seconds = ask(system, user)
                    rows.append({
                        "case": case.get("id", transcript[:40]),
                        "case_note": case.get("note", ""),
                        "language": LANGUAGE,
                        "model": os.path.basename(MODEL),
                        "tone": tone,
                        "variant": variant,
                        "run": run,
                        "input": transcript,
                        "output": out,
                        "seconds": seconds,
                        "system_chars": len(system),
                        "user_chars": len(user),
                    })
                    print(f"{len(rows):4d} r{run} {case.get('id','')} {tone} {variant} "
                          f"{seconds}s -> {out[:70]!r}", flush=True)
                with open(OUT, "w", encoding="utf-8") as fh:
                    json.dump(rows, fh, ensure_ascii=False, indent=1)
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
