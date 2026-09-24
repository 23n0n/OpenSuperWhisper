#!/usr/bin/env python3
"""Recompute the long-form recall numbers from a captured transcript.

This is a cross-check instrument, not the source of the reported numbers: the
authority is the XCTAttachment the test itself writes
(overallUniqueWordRecall / tailUniqueWordRecall), exported from the .xcresult.

The definition is transcribed verbatim from
OpenSuperWhisperTests/LongFormTranscriptionTests.swift @ 5e51124:

    normalizedWords: fold case+diacritics (en_US_POSIX), split on anything that
    is not alphanumeric, keep tokens of length >= 4
    wordRecall: |unique(reference) INTERSECT unique(transcription)| / |unique(reference)|
    tail: the last max(45, count/4) words of each side

Usage: recall-recompute.py <reference.txt> <transcript.txt>
"""
import re
import sys
import unicodedata


def fold(text: str) -> str:
    # Swift .folding(options: [.caseInsensitive, .diacriticInsensitive])
    text = unicodedata.normalize("NFD", text)
    text = "".join(c for c in text if not unicodedata.combining(c))
    return unicodedata.normalize("NFC", text).lower()


def normalized_words(text: str):
    return [w for w in re.split(r"[^0-9A-Za-z\u0400-\u04FF]+", fold(text)) if len(w) >= 4]


def recall(reference, transcription):
    expected = set(reference)
    if not expected:
        return 0.0
    return len(expected & set(transcription)) / len(expected)


def main():
    ref = normalized_words(open(sys.argv[1], encoding="utf-8").read())
    got = normalized_words(open(sys.argv[2], encoding="utf-8").read())
    tail_n = max(45, len(ref) // 4)
    tail_ref = ref[-tail_n:]
    tail_got = got[-max(45, len(got) // 4):]
    print(f"reference unique words: {len(set(ref))} (total {len(ref)})")
    print(f"transcript unique words: {len(set(got))} (total {len(got)})")
    print(f"overallUniqueWordRecall: {recall(ref, got):.4f}")
    print(f"tailUniqueWordRecall:    {recall(tail_ref, tail_got):.4f}")


if __name__ == "__main__":
    main()
