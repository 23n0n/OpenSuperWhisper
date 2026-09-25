#!/usr/bin/env python3
"""Wait for the machine to be free, then launch the measurement, detached.

The gate the brief asks for: no `xcodebuild` and no `llama-server` alive, seen
twice a minute apart with nothing busy in between. A single failing observation
resets the clock. When it opens, the measurement is launched in its own session
(`start_new_session=True`) so it is not torn down with this script's session.
"""
import datetime
import os
import subprocess
import sys
import time

DATA = "/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260925-15"
RUN = f"{DATA}/evidence/run-measurement.sh"
GATE_LOG = "/tmp/fm2415-gate.log"
RUN_LOG = "/tmp/fm2415-run.log"
MARKERS = ("xcodebuild", "llama-server")


def log(message):
    stamp = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(GATE_LOG, "a") as handle:
        handle.write(f"[{stamp}] {message}\n")


def busy():
    out = subprocess.run(
        ["ps", "-Ao", "comm=,args="], capture_output=True, text=True
    ).stdout
    hits = []
    for line in out.splitlines():
        if "wait-and-run" in line or "analyse.py" in line:
            continue
        if any(marker in line for marker in MARKERS):
            hits.append(line.strip())
    return hits


def main():
    log("gate opened: waiting for a free machine (xcodebuild / llama-server)")
    free_since = None
    while True:
        hits = busy()
        now = time.time()
        if hits:
            log("BUSY: " + " ; ".join(h[:100] for h in hits[:2]))
            free_since = None
        elif free_since is None:
            free_since = now
            log("free (first observation) - waiting for the second, 60 s apart")
        elif now - free_since >= 60:
            log(f"FREE twice a minute apart ({int(now - free_since)} s) - launching")
            break
        time.sleep(20)

    os.makedirs(os.path.dirname(RUN_LOG), exist_ok=True)
    handle = open(RUN_LOG, "w")
    process = subprocess.Popen(
        ["/bin/bash", RUN],
        start_new_session=True,
        stdout=handle,
        stderr=subprocess.STDOUT,
        cwd=os.path.dirname(RUN),
    )
    log(f"launched the measurement: pid {process.pid}, log {RUN_LOG}")
    print(process.pid)


if __name__ == "__main__":
    main()
