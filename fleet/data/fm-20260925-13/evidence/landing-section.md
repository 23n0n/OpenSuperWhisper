## What was landed

`pl-no-echo-named` cleared all four conditions of the decision rule above, so it is the change that
landed, on branch `fm/tone-prompt` (base `877d19e`), no merge, no push, no tag, no model moved:

| file | change |
|---|---|
| `OpenSuperWhisper/TransformService.swift` | `ToneMode.registerName(for:)`, `registerNameLocative(for:)`, `registerDefinition(for:)`; `toneInstruction(for:tone:)` now branches to a new `polishToneInstruction(for:)` (the English body moved verbatim into a private `englishToneInstruction(for:)`); `polishMarkerInstruction()`; `systemPrompt` writes the closing line in the instruction's own language **only when the prompt carries tone text** (clean-up alone keeps its wording); `userPrompt` branches to a new Polish turn, with the English body moved verbatim into a private `englishUserPrompt(for:)`. |
| `OpenSuperWhisperTests/TransformServiceTests.swift` | the two language-blind prompt tests now assert each language's own invariants (English wording for `.english`, Polish wording for `.polish`), including the pin that the Polish prompt is not the English one, and the anti-echo rule. |
| `OpenSuperWhisperTests/TranscriptionLanguageGateTests.swift` | the per-language turn assertions read the Polish frame as Polish (`(polski)`, `po polsku`) instead of `(Polish)` — the invariant ("each turn pins its own language and not the other one") is unchanged. |
| `Readme.md` | the tone section now states that the instruction is written in the language of the dictation, with the measured numbers and the reason the Polish prompt names the two markers. |

**What was not touched:** `TransformGuard.swift` (no detection class added — the delimiter echo is not a
guard rule; the prompt forbids it), the routing `model(for:)`, the warm-up, `WhisperEngine`, the pause
crew's files, the clean-up wording, the reference block, and every prompt for English and for clean-up
alone. The English prompts and both clean-up-alone prompts are **byte-identical** before and after
(`evidence/compiled-before.json` against `evidence/compiled-after.json`: the only differing keys are
`tone/polish/*`, `cleanUpWithTone/polish/*` and `users/polish/*`).

**Fidelity of the landed code.** `evidence/bin/prompt-harness` is rebuilt from the modified
`TransformService.swift` by the same extractor, and its output is compared byte for byte against
`evidence/expected-winner-prompts.json` — the prompts the measured candidate composed, plus the clean-up
prompts of the pre-change compiled service: **8 systems and 6 user turns compared, 0 mismatches**. So the
code that landed sends exactly the bytes that were measured, in both languages.
