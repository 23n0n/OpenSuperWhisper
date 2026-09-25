#!/usr/bin/env python3
"""Fill the report's {{TOKEN}}s with fragments generated from the evidence.

Usage: assemble.py <prose.md> <report.md>

Every number in the report is produced by build-report.py from the evidence log,
so no figure in the prose can drift from the run that produced it. A leftover
token is printed, which is how a missing section is caught rather than shipped.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EVIDENCE = os.path.join(HERE, "decode-evidence.log")
ANCHORS = [
    "9039BAB0-CBA2-49B2-82E1-432FF7B94589.wav",
    "29EA0AEA-06B0-4FE1-B189-18A21822F35A.wav",
    "FD7B4C64-0AD7-4431-84D6-6F9EAFC77512.wav",
]


def fragment(section, *extra):
    result = subprocess.run(
        [sys.executable, "build-report.py", EVIDENCE, "--section", section, *extra],
        capture_output=True, text=True, cwd=HERE,
    )
    if result.returncode != 0:
        raise SystemExit(f"fragment {section} failed: {result.stderr}")
    return result.stdout.rstrip("\n")


def main():
    prose_path, out_path = sys.argv[1], sys.argv[2]
    prose = open(prose_path, encoding="utf-8").read()

    anchor_args = []
    for anchor in ANCHORS:
        anchor_args += ["--anchor", anchor]

    tokens = {
        "ANCHORS": fragment("anchors", *anchor_args),
        "TABLE": fragment("table"),
        "AGGREGATES": fragment("aggregates"),
        "MISMATCHES": fragment("mismatches"),
        "FLIPS": fragment("flips"),
        "GUARDS": fragment("guards"),
        "LEAKS": fragment("leaks"),
        "ODDBALLS": fragment("oddballs"),
        "EARS": fragment("ears"),
        "FOREIGN": fragment("foreign"),
        "CHANGED": fragment("changed"),
        "HISTORY": fragment("history"),
    }

    for key, value in tokens.items():
        prose = prose.replace("{{" + key + "}}", value)

    leftovers = sorted(set(re.findall(r"\{\{([A-Z_]+)\}\}", prose)))
    if leftovers:
        print("UNFILLED TOKENS:", leftovers, file=sys.stderr)

    with open(out_path, "w", encoding="utf-8") as handle:
        handle.write(prose)
    print(f"wrote {out_path} ({len(prose)} bytes)")


if __name__ == "__main__":
    main()
