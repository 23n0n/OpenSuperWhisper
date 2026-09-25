#!/usr/bin/env python3
"""Independent re-derivation of the pairing verdict from the evidence log.

The harness prints its own table; this recomputes it from the transcripts so the
report's verdict is not a single implementation's word for it. Word comparison is
case-folded alphanumeric tokens with multiplicity, which is the harness's rule:

    words(t) = re.findall(r"[0-9A-Za-z]+", t.lower())  as a multiset

Usage: fm2414-verdict.py <evidence log>
"""
import re
import sys
from collections import Counter

path = sys.argv[1] if len(sys.argv) > 1 else "/tmp/fm2414-pairing-evidence.log"

header = re.compile(r"^\[pair\] (?P<rec>.+?) \| (?P<arm>.+?) \| (?P<ms>\d+) ms$")
recordings = {}
current = None

for line in open(path, encoding="utf-8"):
    line = line.rstrip("\n")
    m = header.match(line)
    if m:
        current = {"rec": m.group("rec"), "arm": m.group("arm"), "text": None}
        recordings.setdefault(m.group("rec"), {})[m.group("arm")] = current
        continue
    if current is not None and line.startswith("[pair]   text: "):
        current["text"] = line[len("[pair]   text: "):]


def words(text):
    return Counter(re.findall(r"[0-9A-Za-z]+", text.lower()))


def sentences(text):
    return [s.strip() for s in re.split(r"(?<=[.!?…。！？])\s*", text.strip()) if s.strip()]


def delta(baseline, text):
    return words(baseline) - words(text), words(text) - words(baseline)


def find(arm_name):
    for rec, arms in recordings.items():
        for arm, data in arms.items():
            if arm == arm_name:
                yield rec, data["text"] or ""


CONTROL = "off / none (control)"
ON = "on / {}"

pl1 = [r for r in recordings if r.startswith("pl-1")]
pl2 = [r for r in recordings if r.startswith("pl-2")]
en = [r for r in recordings if r.startswith("en")]
if not (pl1 and pl2 and en):
    print("recordings found:", list(recordings))
    sys.exit("the evidence log does not hold all three recordings")
pl1, pl2, en = pl1[0], pl2[0], en[0]

controls = {rec: recordings[rec][CONTROL]["text"] for rec in (pl1, pl2, en)}
control_sentences = {rec: len(sentences(controls[rec])) for rec in controls}

labels = []
for rec in (pl1, pl2, en):
    for arm in recordings[rec]:
        if arm.startswith("on / ") and arm != "on / none (repeated)":
            label = arm[len("on / "):]
            if label not in labels:
                labels.append(label)

print("## Independent re-derivation")
print()
print("control sentences:", {rec.split(" ")[0]: control_sentences[rec] for rec in (pl1, pl2, en)})
print()
print("| pl prompt | en prompt | en control words vs control | pl-1 boundary | pl-2 words | verdict |")
print("|---|---|---|---|---|---|")
for pl_label in labels:
    for en_label in labels:
        en_text = recordings[en][ON.format(en_label)]["text"]
        removed, added = delta(controls[en], en_text)
        clean = not removed and not added

        pl1_text = recordings[pl1][ON.format(pl_label)]["text"]
        pl1_boundary = pl1_text.count("drogą.") > controls[pl1].count("drogą.") or (
            len(sentences(pl1_text)) > control_sentences[pl1] and "drogą." in pl1_text
        )
        pl2_text = recordings[pl2][ON.format(pl_label)]["text"]
        pl2_win = "Open Super Whisper" in pl2_text and "Dodałem" in pl2_text

        verdict = "PASS" if clean and pl1_boundary and pl2_win else "FAIL"
        detail = "clean" if clean else "NO -{} +{}".format(
            " ".join(sorted(removed)), " ".join(sorted(added)))
        print("| {} | {} | {} | {} | {} | {} |".format(
            pl_label, en_label, detail,
            "yes" if pl1_boundary else "NO", "yes" if pl2_win else "NO", verdict))

print()
print("## Per recording: every on-arm against the control, verbatim")
print()
for rec in (pl1, pl2, en):
    print("### {}".format(rec))
    print()
    print("| arm | sentences | words removed | words added | text |")
    print("|---|---|---|---|---|")
    for arm, data in sorted(recordings[rec].items()):
        text = data["text"]
        if text is None or not arm.startswith("on / "):
            continue
        removed, added = delta(controls[rec], text)
        print("| {} | {} | {} | {} | {} |".format(
            arm, len(sentences(text)),
            " ".join(sorted(removed)) or "—", " ".join(sorted(added)) or "—",
            text.replace("|", r"\|")))
    print()
