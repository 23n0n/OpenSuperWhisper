**PLACEHOLDER: Readme section 8 edits (phase 2).**

Replace the paragraph that says the switch ships off:

> **The switch is named for what it does, not for what was asked.** One line in **Settings → Transcription →
> Language Settings**: **Long Pauses End the Sentence** — "a pause of 0.6 s or longer keeps its silence and closes the
> sentence, instead of dissolving into a breath that lets two thoughts merge". Off is byte-for-byte the behaviour
> every earlier build had, and it ships **off by default** — not out of caution, but because the measurement below
> says the switch-on state regresses the English control while this app sends no decoder prompt.

with the version that says it ships on, paired with the language-aware decoder prompt, and add a bullet about the
pairing measurement (the arm tables, the English-clean/Polish-win result, the pre-pass's measured cost), plus the
sentence that only the two measured languages carry a default and everything else sends no prompt.

Numbers and verbatim texts come from `/tmp/fm2414-pairing-evidence.log`.
