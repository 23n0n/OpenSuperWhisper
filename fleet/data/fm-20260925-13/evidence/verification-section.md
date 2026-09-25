## Verification

**The prompt the code sends is the prompt that was measured.**
`evidence/bin/prompt-harness` is rebuilt from the modified `TransformService.swift` by
`evidence/build-prompt-harness.py`, which extracts the real declarations verbatim and compiles them with the
real `Utils/LanguageDetector.swift`. Its output is compared byte for byte against
`evidence/expected-winner-prompts.json`: **8 system prompts and 6 user turns compared, 0 mismatches** — all
three registers in both languages, at the probe `wyślij raport do klienta dzisiaj` / `send the report to the
client today`.

**The change surface is exactly the Polish tone prompt.** `evidence/compiled-before.json` against
`evidence/compiled-after.json` (both printed by that harness, before and after the edit) differ on exactly
`tone/polish/{neutral,formal,casual}`, `cleanUpWithTone/polish/{neutral,formal,casual}` and `users/polish/*`.
Every English prompt and both clean-up-alone prompts are byte-identical — which is also why the English
measurement above is a draw on the same bytes the landed round measured.

**The instruments.** Guard verdicts come from the real `TransformGuard.swift` + `Utils/LanguageDetector.swift`
compiled at head (the guard itself was not modified), calibrated on the 19 known cases —
`evidence/guard-cases-local.txt`, **ALL 19 CASES PASS**. The word screen is the landed round's own
(`evidence/analyze13.py`); pointed at that round's raw answers it reproduces the published `old 13/7/8` and
`control 15/2/4` exactly, so the new tables are on the same scale.

**The suite, and where it stands.**

| run | head | command | result |
|---|---|---|---|
| 1 (full) | `9567b77` | `Scripts/dev-run.sh test`, detached, no other build or `llama-server` alive at launch | **434 total / 379 passed / 1 failed / 54 skipped**, `** TEST FAILED **` (`/tmp/fm2413-suite.log`; `evidence/suite1-summary.json`) |
| 2 (scoped) | `2de0698` | `Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/TransformServiceTests` | **29 passed / 0 failed**, `** TEST SUCCEEDED **` (`/tmp/fm2413-scoped.log`) |

The single run-1 failure was **mine and stale, not a product defect**:
`TransformServiceTests.testPolicyTable_returnsTheInputAndChargesACallOnlyWhenItActs` asserted, for every row,
`prompt.contains(language.displayName)` — *"tone on, Polish: every prompt names the language it pins"* — and
the Polish prompt now names Polish in Polish (`polski na wejściu, polski na wyjściu`, `po polsku`) instead of
"Polish". It was fixed at the **invariant** level in `2de0698`: the assertion is now policy-aware — a tone
prompt must pin its own language in its own words, and clean-up alone still says "it stays in Polish" — and
the whole class was re-run scoped and is green. `TransformGuardTests` was untouched and passed inside run 1.

**Bundle identity — the re-sign step ran in both runs**, and the designated requirement is unchanged:

```
identity:              OpenSuperWhisper Local Dev
designated requirement: identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"
```

`certificate leaf`, never a bare `cdhash`, and identical to the requirement the landed round recorded, so the
captain's Accessibility grant is not disturbed by this change.

## What is left unverified, and the limits this round did not remove

1. **The full suite has not been re-run at the final head `2de0698`.** Run 1 was at `9567b77` and failed on the
   one stale assertion above; that assertion is fixed and its whole class is green scoped, but the *full* suite
   green at `2de0698` is **not yet observed**. The gate closed first: a sibling crew had
   `xcodebuild test -only-testing:OpenSuperWhisperTests` running (pid 6695) and this round's own rule forbids
   starting a second suite beside it. The run to make is
   `Scripts/dev-run.sh test > /tmp/fm2413-suite-final.log 2>&1` on `2de0698` with no other `xcodebuild` or
   `llama-server` alive.
2. **Two draws per case at temperature 0.2.** The outputs are draws, not distributions. The winner is
   repeatable — 0 of 28 answers differ between its two runs, against the control's 2 of 28 — but the
   *magnitudes* (25 untouched against 15) are one session's numbers, not a confidence interval.
3. **Polish register quality is judged mechanically plus by reading, not by the captain's ear.** Four of his
   seven Polish dictations are a single clause long, where any register change is noise-level; the informative
   ones are the two run-ons and the adversarial set.
4. **The guard still cannot see content drift**, and it does not catch a delimiter echo either: nothing in the
   app strips an echoed `TRANSCRIPT`. The echo is forbidden by the prompt alone — measured 0 of 56 answers with
   the rule and 6 of 56 without it.
5. **The combined Polish prompt is half English by design.** The tone instruction is Polish; the clean-up
   sentence it rides with stays the English wording the app already had, because re-wording Polish clean-up was
   outside this round and would have changed a path nobody measured here. The combined prompt *was* measured
   and improved (21–22 untouched against 13–14), but that is the mixed prompt, not a Polish clean-up
   instruction.
6. **Latency figures are not clean.** A sibling crew ran `xcodebuild` builds and scoped test runs during parts
   of rounds 1 and 3 (`evidence/concurrency-note.txt`), which inflates the medians. Every variant inside a
   round was measured interleaved, so the comparisons are unaffected.
7. **No end-to-end run inside the app.** The measurement uses the app's exact compiled prompts and sampling
   through `llama-server`, not the app's own process; the in-app path is what the suite covers.

## Commit and diffstat

`9567b77` (the prompt change) + `2de0698` (the stale policy-table assertion) on `fm/tone-prompt` (base
`877d19e`), no merge, no push, no tag, no branch deleted, no model moved or copied, the primary checkout and
the pause crew's worktree untouched. The submodules the build needs were missing in this worktree and were
checked out at the recorded gitlinks (`git submodule update --init --recursive`), which cannot move another
worktree's checkout — verified after the fact.

```
 OpenSuperWhisper/TransformService.swift                 | 153 +++++++++++++++++++--
 OpenSuperWhisperTests/TransformServiceTests.swift      | 100 +++++++++++-------
 OpenSuperWhisperTests/TranscriptionLanguageGateTests.swift |   8 +-
 Readme.md                                              |   7 +-
```

Raw harness sources, every run's JSON, the classification output, the compiled-service prompt dumps before and
after, and the hashes of everything are in `evidence/`.
