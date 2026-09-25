#!/usr/bin/env python3
"""Measure prompts that are taken from the COMPILED service's own output.

No reconstruction: every system prompt comes out of `bin/prompt-harness`, built
from the real TransformService.swift, so the bytes sent are the bytes the app
would send. Two prompt files are compared: the pre-change compiled service and the
post-change one.

Usage:
  tone-compiled.py <model.gguf> <language> <cases.json> <out.json> <runs> <arm>...
  <arm> = label:prompts.json:keyPrefix        keyPrefix is `tone` or `cleanUpWithTone`
"""
import json
import os
import subprocess
import sys
import time
import urllib.request

PORT = 1919


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
    MODEL, LANGUAGE, CASES_ARG, OUT, RUNS = sys.argv[1:6]
    runs = int(RUNS)
    arms = []
    for spec in sys.argv[6:]:
        label, path, prefix = spec.split(":")
        prompts = json.load(open(path, encoding="utf-8"))
        arms.append((label, prompts, prefix))
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
                for label, prompts, prefix in arms:
                    system = prompts["systems"][f"{prefix}/{LANGUAGE}/{tone}"]
                    user = prompts["users"][f"{LANGUAGE}/{tone}"].replace(
                        prompts["probe"] if LANGUAGE == "polish" else prompts["probeEnglish"], transcript)
                    out, seconds = ask(system, user)
                    rows.append({
                        "case": case.get("id", transcript[:40]),
                        "language": LANGUAGE,
                        "model": os.path.basename(MODEL),
                        "tone": tone,
                        "variant": label,
                        "prompt_source": f"{prefix}:{path}",
                        "run": run,
                        "input": transcript,
                        "output": out,
                        "seconds": seconds,
                    })
                    print(f"{len(rows):4d} r{run} {case.get('id','')} {tone} {label} "
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
    main()
