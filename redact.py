#!/usr/bin/env python3
"""Remove the captain's own dictation and its model outputs from the published snapshot.

The live records under the workspace stay intact; this repository is published, so the verbatim
fragments of his recordings are replaced with length-preserving markers. Idempotent: the markers
contain no quotes, so a second run finds nothing to do and reports 0.
"""
import pathlib
import sys

LITERALS = [
    # (literal in the records, replacement published in its place)
    ("keyboard simulation output is working.", "<redacted: captain dictation, 38 chars>"),
    ("Klawiatura simulacja wyjście działa.", "<redacted: model output A, 36 chars>"),
    ("Klawiatura simulates jest działała.", "<redacted: model output B, 35 chars>"),
    ("Komputerki wizualizacyjne wydajne.", "<redacted: captain dictation, 34 chars>"),
]
SKIP = {pathlib.Path(__file__).resolve(), pathlib.Path("redact.py").resolve()}
TEXT_SUFFIXES = {".md", ".log", ".txt", ".json", ".tsv", ".out", ".sh", ".py"}

root = pathlib.Path(__file__).resolve().parent
total = 0
for path in sorted(root.rglob("*")):
    if not path.is_file() or path.resolve() in SKIP or path.suffix not in TEXT_SUFFIXES:
        continue
    try:
        text = path.read_text()
    except (UnicodeDecodeError, OSError):
        continue
    new = text
    for literal, replacement in LITERALS:
        new = new.replace(literal, replacement)
    if new != text:
        path.write_text(new)
        hits = sum(text.count(literal) for literal, _ in LITERALS)
        total += hits
        print(f"{path.relative_to(root)}: {hits} fragment(s) redacted")
print(f"total redacted: {total}")
sys.exit(0)
