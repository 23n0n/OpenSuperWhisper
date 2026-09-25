#!/usr/bin/env python3
"""Wait for the measurement to start and finish, then report the outcome.

Nothing here polls the machine: it watches the two files the run writes. It
sleeps between checks, so it costs nothing while the gate is still closed.
"""
import os
import subprocess
import time

RUN_LOG = "/tmp/fm2415-run.log"
GATE_LOG = "/tmp/fm2415-gate.log"
EVIDENCE = "/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260925-15/evidence/decode-evidence.log"


def alive():
    out = subprocess.run(["ps", "-Ao", "args="], capture_output=True, text=True).stdout
    return any("run-measurement.sh" in line for line in out.splitlines())


def tail(path, count):
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
        return "".join(lines[-count:])
    except FileNotFoundError:
        return f"(no {path})\n"


def main():
    # 1. Wait for the launch (the driver writes this line when the gate opens).
    while not os.path.exists(GATE_LOG) or "launched the measurement" not in open(GATE_LOG).read():
        time.sleep(20)

    print("launched; waiting for the measurement to finish", flush=True)

    # 2. Wait for the run process to disappear, and for the summary to land.
    seen_summary = False
    while True:
        time.sleep(30)
        try:
            seen_summary = "SUMMARY processed" in open(EVIDENCE, encoding="utf-8", errors="replace").read()
        except FileNotFoundError:
            seen_summary = False
        if seen_summary and not alive():
            break

    print("=== gate log ===")
    print(tail(GATE_LOG, 6))
    print("=== run log tail ===")
    print(tail(RUN_LOG, 40))
    print("=== evidence summary ===")
    with open(EVIDENCE, encoding="utf-8", errors="replace") as handle:
        lines = handle.readlines()
    for line in lines:
        if "SUMMARY" in line or "SKIPPED" in line or "UNDECODABLE" in line:
            print(line.rstrip())
    print("=== evidence lines:", len(lines), "===")


if __name__ == "__main__":
    main()
