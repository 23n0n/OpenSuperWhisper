# fm-20260925-13 — tone-prompt round: can a candidate beat the landed prompt?

**Mode: local-only.** Worktree `worktrees/OpenSuperWhisper-fm-toneprompt`, branch `fm/tone-prompt`
@ `877d19e` (the landed prompt, `OpenSuperWhisper/TransformService.swift` `systemPrompt()` /
`userPrompt()`; guard `TransformGuard.swift`). No merge, no push, no tag, no model moved or copied.

The landed prompt is the **control in every run**. The residual failure it left is invented and
dropped words in Polish (2 invented / 4 lost of 28), so that is the only thing a candidate may fix.

## Instrument (identical to the landed measurement, so the rows compare)

* `evidence/tone-round.py` — the driver. The control column is composed by
  `tone-measure.py`'s `compose_new`, the very function the landed round proved byte-equal to the
  compiled service.
* **Fidelity re-proved at this head, against the compiled service, not a reading:**
  `evidence/bin/prompt-harness` is built by `evidence/build-prompt-harness.py`, which extracts
  `ToneMode`, `TransformLanguage`, `TransformPolicy`, `systemPrompt`, `toneInstruction`,
  `userPrompt`, `cleanUpInstruction`, `referenceInstruction` **verbatim** (brace-matched spans) out
  of the real `TransformService.swift` and compiles them with the real `Utils/LanguageDetector.swift`.
  `tone-round.py --verify` compares the Python control with that program's output byte for byte for
  every (language × register), system and user turn: **CONTROL == COMPILED SERVICE: True**.
* `evidence/bin/guard-classify` and `bin/lang-verdict` — the **real** `TransformGuard.swift` and
  `LanguageDetector.swift` compiled from head `877d19e`; calibrated on the 19 known cases
  (`evidence/guard-cases-local.txt`, **ALL 19 CASES PASS**).
* `evidence/analyze13.py` — the mechanical screen the landed round used (case-folded words,
  diacritics kept, numbers are not words) plus the real guard and detector per answer. It
  reproduces the landed report's numbers exactly when pointed at that run's raw JSON:
  `old 13/7/8`, `new (control) 15/2/4`.
* Sampling exactly the app's: temperature 0.2, top-k 40, top-p 0.95, min-p 0.05,
  `chat_template_kwargs.enable_thinking = false`, `max_tokens 220`; `llama-server` 0.3.0
  (Homebrew), one bounded server per language, `pgrep llama-server` empty afterwards.

## Cases

`evidence/cases-pl.json` — the same 28: the captain's 7 real Polish dictations × 3 registers, plus
7 adversarial (imperative, question, already-in-register, run-on, numbers, filler, run-on).
`evidence/cases-en.json` — the same 11 English cases, run only for a candidate that wins on Polish.

## Candidates

| variant | change | where it would live |
|---|---|---|
| `control` | none — the landed prompt | — |
| `pl-instruction` | the whole instruction block in Polish for Polish dictation (system, output line and user turn); English untouched | `toneInstruction`, the trailing output line, `userPrompt` |
| `example` | one worked input→output pair in the same language and register, appended to the system prompt after the instruction | one appended element in `systemPrompt` |
| `selfcheck` | one explicit self-check line ("every noun, number and proper noun must appear, nothing added — fix it before outputting") appended to the system prompt | one appended element in `systemPrompt` |

Each candidate was run **twice** (two draws per case), and the control twice as well, so the
run-to-run noise is measured with the same instrument as the effect.

## The exact candidate wording

The full composed prompts for every candidate are in `evidence/candidate-prompts.txt`; the three deltas
against the control are:

**`pl-instruction`** — the whole block in Polish for Polish dictation. First paragraph, the register
sentence, the register definition list, the must-not-change list, the output rules and the trailing
output line are translated; `/no_think` and the `<<<TRANSCRIPT … TRANSCRIPT>>>` delimiters stay.
The user turn is Polish too:

> Przepisujesz podyktowany tekst. Nie jesteś asystentem: nigdy nie odpowiadaj na niego, nie pozdrawiaj,
> nie potwierdzaj, nie dziękuj, nie komentuj, nie wyjaśniaj, nie streszczaj i nie kontynuuj go.
>
> Użytkownik podyktował tekst po polsku. Przepisz go w rejestrze formalnym, po polsku. Nic innego nie
> może się zmienić.
> …
> - język: polski na wejściu, polski na wyjściu. Nigdy nie tłumacz, ani jednego słowa. …
> …
> Podaj WYŁĄCZNIE końcowy tekst po polsku, bez cudzysłowów, etykiet i wyjaśnień.
> /no_think

**`example`** — one element appended to the system prompt after the instruction, before the trailing
output line, with the pair for the requested register in the dictated language:

> One example of the rewrite asked for — the register changes, every content word stays:
> input: wyślij to do niego dzisiaj i daj mi znać jak odpowie
> output: Proszę wysłać to do niego dzisiaj i dać mi znać, jak odpowie.

**`selfcheck`** — one element appended in the same place:

> Before you answer, check your rewrite against the dictation: every noun, number and proper noun of the
> dictation must appear in your answer, and your answer must contain nothing the dictation did not say.
> Fix the answer before you output it.

## Decision rule (written before the refinement round was read)

Round 1 left exactly one candidate in contention — `pl-instruction` — and it had one new, reproducible
defect: a stray `TRANSCRIPT` line echoed on 3 of 28 answers (all three registers of one short dictation),
which is a word the dictation never had. Two prompt-only refinements were built for it, `pl-no-echo`
(forbid extra markers without naming them) and `pl-no-echo-named` (name the two markers), and measured in
a second round together with the control and the unrefined `pl-instruction`.

A candidate **lands** only if all of these hold, on the 28-case Polish round, run-to-run:

1. no delimiter echo at all (round 1's `pl-instruction` had 3);
2. invented-word answers ≤ the control's worst run in the same round (control was 2 in both rounds);
3. lost-word answers < the control's best run (control was 3 and 4 in round 1);
4. untouched answers > the control's best run (control was 16 in round 1).

Anything else — including "better on two of the three numbers" — is reported as **no win, nothing landed**,
which the brief names as a good outcome. The control's own failures are read honestly too: several of them
(`w języku polskim` → `po polsku`, `jest` → `to`) are legitimate casual rewrites that the mechanical screen
cannot tell from invention, so the screen is used as the round used it — as a screen — and the verbatim
diffs are printed beside it for the reader to judge.




## Polish round 1 — the three hypotheses against the control (224 answers)

Raw answers: `evidence/measure-pl-round1.json`; classification tool: `evidence/analyze13.py` over the real guard/detector; 28 cases per variant per run.

| variant | run | untouched | invented a word | lost a word | guard rejects | latency median (min–max) |
|---|---|---|---|---|---|---|
| `control` | 1 | 16 | 2 | 3 | 0 | 3.31 s (1.35–10.73) |
| `control` | 2 | 15 | 2 | 4 | 0 | 2.62 s (1.26–11.13) |
| `pl-instruction` | 1 | 22 | 4 | 1 | 0 | 2.81 s (1.02–15.35) |
| `pl-instruction` | 2 | 22 | 4 | 1 | 0 | 2.55 s (0.67–10.45) |
| `example` | 1 | 19 | 3 | 4 | 0 | 3.48 s (1.30–17.79) |
| `example` | 2 | 19 | 3 | 4 | 0 | 3.40 s (1.56–13.12) |
| `selfcheck` | 1 | 16 | 2 | 3 | 0 | 3.47 s (1.52–11.60) |
| `selfcheck` | 2 | 16 | 2 | 3 | 0 | 3.66 s (1.53–10.14) |

| variant | run-to-run determinism (identical prompt, two runs) |
|---|---|
| `control` | 1 of 28 answers differ |
| `pl-instruction` | 0 of 28 answers differ |
| `example` | 1 of 28 answers differ |
| `selfcheck` | 1 of 28 answers differ |

**Which cases failed, and with which words.**

`control`:

* run 1 — invented: pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (jest no plan taki więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w)
* run 2 — invented: pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (jest no plan taki więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w), pl-real-podgrywam-casual (języku)

`pl-instruction`:

* run 1 — invented: pl-plan-run-on (że), pl-real-jeszcze-raz-formal (transcript), pl-real-jeszcze-raz-casual (transcript), pl-real-jeszcze-raz-neutral (transcript); lost: pl-plan-run-on (no więc)
* run 2 — invented: pl-plan-run-on (że), pl-real-jeszcze-raz-formal (transcript), pl-real-jeszcze-raz-casual (transcript), pl-real-jeszcze-raz-neutral (transcript); lost: pl-plan-run-on (no więc)

`example`:

* run 1 — invented: pl-imperative (proszę wysłać), pl-plan-run-on (że), pl-real-odzyskalem-casual (to); lost: pl-imperative (wyślij), pl-plan-run-on (no więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku)
* run 2 — invented: pl-imperative (proszę wysłać), pl-plan-run-on (że), pl-real-odzyskalem-casual (to); lost: pl-imperative (wyślij), pl-plan-run-on (no więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku)

`selfcheck`:

* run 1 — invented: pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (jest no plan taki więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w)
* run 2 — invented: pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (jest no plan taki więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w)

**Every case where a candidate's answer differs from the control's, verbatim.**

* `pl-filler` / neutral / run 1:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-instruction`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-filler` / neutral / run 2:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-instruction`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-plan-run-on` / formal / run 1:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-instruction`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-plan-run-on` / formal / run 2:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-instruction`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-real-jeszcze-raz-casual` / casual / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-casual` / casual / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-formal` / formal / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-formal` / formal / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-neutral` / neutral / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-neutral` / neutral / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-nagrywam-casual` / casual / run 1:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-casual` / casual / run 2:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-odzyskalem-casual` / casual / run 1:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-instruction`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-casual` / casual / run 2:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-instruction`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-podgrywam-casual` / casual / run 2:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-instruction`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-ziameczku-casual` / casual / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-casual` / casual / run 2:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 1:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 2:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 1:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 2:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-run-on` / casual / run 1:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-instruction`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`
* `pl-run-on` / casual / run 2:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-instruction`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`

* `pl-filler` / neutral / run 1:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `example`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-filler` / neutral / run 2:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `example`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-imperative` / formal / run 1:
  * control: `'Wyślij raport do klienta dzisiaj.'`
  * `example`: `'Proszę wysłać raport do klienta dzisiaj.'`
* `pl-imperative` / formal / run 2:
  * control: `'Wyślij raport do klienta dzisiaj.'`
  * `example`: `'Proszę wysłać raport do klienta dzisiaj.'`
* `pl-numbers` / casual / run 1:
  * control: `'numer faktury to 423 a kwota to trzy tysiące złotych'`
  * `example`: `'Numer faktury to 423 a kwota to trzy tysiące złotych'`
* `pl-numbers` / casual / run 2:
  * control: `'numer faktury to 423 a kwota to trzy tysiące złotych'`
  * `example`: `'Numer faktury to 423 a kwota to trzy tysiące złotych'`
* `pl-plan-run-on` / formal / run 1:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `example`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-plan-run-on` / formal / run 2:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `example`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-question` / formal / run 1:
  * control: `'Czy możemy przenieść spotkanie na przyszły tydzień'`
  * `example`: `'Czy możemy przenieść spotkanie na przyszły tydzień?'`
* `pl-question` / formal / run 2:
  * control: `'Czy możemy przenieść spotkanie na przyszły tydzień'`
  * `example`: `'Czy możemy przenieść spotkanie na przyszły tydzień?'`
* `pl-real-nagrywam-casual` / casual / run 1:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `example`: `'Teraz nagrywam w polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-casual` / casual / run 2:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `example`: `'Teraz nagrywam w polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `example`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `example`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-podgrywam-casual` / casual / run 2:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `example`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-ziameczku-casual` / casual / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `example`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-casual` / casual / run 2:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `example`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 1:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `example`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 2:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `example`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-run-on` / casual / run 2:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `example`: `'No więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje.'`

* `pl-imperative` / formal / run 1:
  * control: `'Wyślij raport do klienta dzisiaj.'`
  * `selfcheck`: `'Wyślij raport do klienta dzisiaj'`
* `pl-real-podgrywam-casual` / casual / run 2:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `selfcheck`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`


## Polish round 2 — the refinement round (224 answers)

Raw answers: `evidence/measure-pl-round2.json`; classification tool: `evidence/analyze13.py` over the real guard/detector; 28 cases per variant per run.

| variant | run | untouched | invented a word | lost a word | guard rejects | latency median (min–max) |
|---|---|---|---|---|---|---|
| `control` | 1 | 15 | 2 | 4 | 0 | 1.75 s (0.65–3.59) |
| `control` | 2 | 15 | 2 | 4 | 0 | 1.36 s (0.52–2.61) |
| `pl-instruction` | 1 | 22 | 4 | 1 | 0 | 2.33 s (1.10–4.73) |
| `pl-instruction` | 2 | 22 | 4 | 1 | 0 | 2.21 s (1.10–3.45) |
| `pl-no-echo` | 1 | 22 | 4 | 1 | 0 | 2.38 s (1.40–3.60) |
| `pl-no-echo` | 2 | 22 | 4 | 1 | 0 | 2.37 s (1.39–3.71) |
| `pl-no-echo-named` | 1 | 25 | 1 | 1 | 0 | 2.37 s (1.40–3.66) |
| `pl-no-echo-named` | 2 | 25 | 1 | 1 | 0 | 2.37 s (1.40–3.60) |

| variant | run-to-run determinism (identical prompt, two runs) |
|---|---|
| `control` | 2 of 28 answers differ |
| `pl-instruction` | 0 of 28 answers differ |
| `pl-no-echo` | 1 of 28 answers differ |
| `pl-no-echo-named` | 0 of 28 answers differ |

**Which cases failed, and with which words.**

`control`:

* run 1 — invented: pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (jest no plan taki więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w), pl-real-podgrywam-casual (języku)
* run 2 — invented: pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (jest no plan taki więc), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w), pl-real-podgrywam-casual (języku)

`pl-instruction`:

* run 1 — invented: pl-plan-run-on (że), pl-real-jeszcze-raz-formal (transcript), pl-real-jeszcze-raz-casual (transcript), pl-real-jeszcze-raz-neutral (transcript); lost: pl-plan-run-on (no więc)
* run 2 — invented: pl-plan-run-on (że), pl-real-jeszcze-raz-formal (transcript), pl-real-jeszcze-raz-casual (transcript), pl-real-jeszcze-raz-neutral (transcript); lost: pl-plan-run-on (no więc)

`pl-no-echo`:

* run 1 — invented: pl-plan-run-on (że), pl-real-jeszcze-raz-formal (transcript), pl-real-jeszcze-raz-casual (transcript), pl-real-jeszcze-raz-neutral (transcript); lost: pl-plan-run-on (no więc)
* run 2 — invented: pl-plan-run-on (że), pl-real-jeszcze-raz-formal (transcript), pl-real-jeszcze-raz-casual (transcript), pl-real-jeszcze-raz-neutral (transcript); lost: pl-plan-run-on (no więc)

`pl-no-echo-named`:

* run 1 — invented: pl-plan-run-on (że); lost: pl-plan-run-on (no więc)
* run 2 — invented: pl-plan-run-on (że); lost: pl-plan-run-on (no więc)

**Every case where a candidate's answer differs from the control's, verbatim.**

* `pl-filler` / neutral / run 1:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-instruction`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-filler` / neutral / run 2:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-instruction`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-imperative` / formal / run 1:
  * control: `'Wyślij raport do klienta dzisiaj'`
  * `pl-instruction`: `'Wyślij raport do klienta dzisiaj.'`
* `pl-plan-run-on` / formal / run 1:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-instruction`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-plan-run-on` / formal / run 2:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-instruction`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-real-jeszcze-raz-casual` / casual / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-casual` / casual / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-formal` / formal / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-formal` / formal / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-neutral` / neutral / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-neutral` / neutral / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-instruction`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-nagrywam-casual` / casual / run 1:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-casual` / casual / run 2:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-instruction`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-odzyskalem-casual` / casual / run 1:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-instruction`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-casual` / casual / run 2:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-instruction`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-podgrywam-casual` / casual / run 1:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-instruction`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-podgrywam-casual` / casual / run 2:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-instruction`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-ziameczku-casual` / casual / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-casual` / casual / run 2:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 1:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 2:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 2:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-instruction`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-run-on` / casual / run 1:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-instruction`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`
* `pl-run-on` / casual / run 2:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-instruction`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`

* `pl-filler` / neutral / run 1:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-no-echo`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-filler` / neutral / run 2:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-no-echo`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-plan-run-on` / formal / run 1:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-no-echo`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-plan-run-on` / formal / run 2:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-no-echo`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-real-jeszcze-raz-casual` / casual / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-no-echo`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-casual` / casual / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-no-echo`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-formal` / formal / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-no-echo`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-formal` / formal / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-no-echo`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-neutral` / neutral / run 1:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-no-echo`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-jeszcze-raz-neutral` / neutral / run 2:
  * control: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.'`
  * `pl-no-echo`: `'Jeszcze raz transkrypcja w języku polskim, jeszcze raz transkrypcja w języku polskim.\nTRANSCRIPT'`
* `pl-real-nagrywam-casual` / casual / run 1:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-no-echo`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-casual` / casual / run 2:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-no-echo`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-odzyskalem-casual` / casual / run 1:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-no-echo`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-casual` / casual / run 2:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-no-echo`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-podgrywam-casual` / casual / run 1:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-no-echo`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-podgrywam-casual` / casual / run 2:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-no-echo`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-ziameczku-casual` / casual / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-casual` / casual / run 2:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 1:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 2:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 2:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-run-on` / casual / run 1:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-no-echo`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`
* `pl-run-on` / casual / run 2:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-no-echo`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`

* `pl-filler` / neutral / run 1:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-no-echo-named`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-filler` / neutral / run 2:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że że wdrożenie jest zrobione'`
  * `pl-no-echo-named`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-imperative` / formal / run 1:
  * control: `'Wyślij raport do klienta dzisiaj'`
  * `pl-no-echo-named`: `'Wyślij raport do klienta dzisiaj.'`
* `pl-plan-run-on` / formal / run 1:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-no-echo-named`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-plan-run-on` / formal / run 2:
  * control: `'Najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
  * `pl-no-echo-named`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-real-nagrywam-casual` / casual / run 1:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-no-echo-named`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-casual` / casual / run 2:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `pl-no-echo-named`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo-named`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo-named`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo-named`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `pl-no-echo-named`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-odzyskalem-casual` / casual / run 1:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-no-echo-named`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-casual` / casual / run 2:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `pl-no-echo-named`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-podgrywam-casual` / casual / run 1:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-no-echo-named`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-podgrywam-casual` / casual / run 2:
  * control: `'Teraz podgrywam w polskim, teraz nagrywam w polskim.'`
  * `pl-no-echo-named`: `'Teraz podgrywam w języku polskim, teraz nagrywam w języku polskim.'`
* `pl-real-ziameczku-casual` / casual / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo-named`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-casual` / casual / run 2:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo-named`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 1:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo-named`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-formal` / formal / run 2:
  * control: `'Dobra, ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo-named`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 1:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo-named`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-real-ziameczku-neutral` / neutral / run 2:
  * control: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `pl-no-echo-named`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-run-on` / casual / run 1:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-no-echo-named`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`
* `pl-run-on` / casual / run 2:
  * control: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`
  * `pl-no-echo-named`: `'no więc myślę że po prostu powinniśmy to wypuścić w piątek jeśli nic się nie zepsuje'`


## Polish round 3 — the tone+clean-up path, control vs the landed change (112 answers)

Raw answers: `evidence/measure-pl-combined.json`; classification tool: `evidence/analyze13.py` over the real guard/detector; 28 cases per variant per run.

| variant | run | untouched | invented a word | lost a word | guard rejects | latency median (min–max) |
|---|---|---|---|---|---|---|
| `control` | 1 | 13 | 6 | 6 | 0 | 1.83 s (0.66–3.99) |
| `control` | 2 | 14 | 4 | 4 | 0 | 1.48 s (0.53–2.73) |
| `winner` | 1 | 21 | 1 | 1 | 0 | 1.79 s (0.68–5.31) |
| `winner` | 2 | 22 | 1 | 1 | 0 | 1.54 s (0.54–2.65) |

| variant | run-to-run determinism (identical prompt, two runs) |
|---|---|
| `control` | 4 of 28 answers differ |
| `winner` | 1 of 28 answers differ |

**Which cases failed, and with which words.**

`control`:

* run 1 — invented: pl-filler (nie), pl-plan-run-on (analizujemy następnie następujący przeprowadzamy testy zmiany), pl-real-odzyskalem-formal (fakt to), pl-real-odzyskalem-casual (to), pl-real-odzyskalem-neutral (to), pl-real-nagrywam-casual (po polsku); lost: pl-filler (no), pl-plan-run-on (no patrzymy taki testujemy w więc), pl-real-odzyskalem-formal (jest taka), pl-real-odzyskalem-casual (jest), pl-real-odzyskalem-neutral (jest), pl-real-nagrywam-casual (języku polskim w)
* run 2 — invented: pl-plan-run-on (analizujemy następnie następujący przeprowadzamy testy), pl-real-odzyskalem-formal (fakt to), pl-real-odzyskalem-casual (to), pl-real-nagrywam-casual (po polsku); lost: pl-plan-run-on (no patrzymy taki testujemy w więc), pl-real-odzyskalem-formal (jest taka), pl-real-odzyskalem-casual (jest), pl-real-nagrywam-casual (języku polskim w)

`winner`:

* run 1 — invented: pl-plan-run-on (że); lost: pl-plan-run-on (no więc)
* run 2 — invented: pl-plan-run-on (że); lost: pl-plan-run-on (no więc)

**Every case where a candidate's answer differs from the control's, verbatim.**

* `pl-filler` / neutral / run 1:
  * control: `'yyy nie więc w sumie chciałem powiedzieć, że wdrożenie jest zrobione.'`
  * `winner`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-filler` / neutral / run 2:
  * control: `'yyy no więc w sumie chciałem powiedzieć, że wdrożenie jest zrobione.'`
  * `winner`: `'yyy no więc w sumie chciałem powiedzieć że że wdrożenie jest zrobione'`
* `pl-numbers` / casual / run 1:
  * control: `'numer faktury to 423, a kwota to trzy tysiące złotych'`
  * `winner`: `'numer faktury to 423 a kwota to trzy tysiące złotych'`
* `pl-numbers` / casual / run 2:
  * control: `'numer faktury to 423, a kwota to trzy tysiące złotych'`
  * `winner`: `'numer faktury to 423 a kwota to trzy tysiące złotych'`
* `pl-plan-run-on` / formal / run 1:
  * control: `'Plan jest następujący: najpierw przeprowadzamy testy, a następnie wdrażamy zmiany, a potem analizujemy logi.'`
  * `winner`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-plan-run-on` / formal / run 2:
  * control: `'Plan jest następujący: najpierw przeprowadzamy testy, następnie wdrażamy, a potem analizujemy logi.'`
  * `winner`: `'Plan jest taki, że najpierw testujemy, potem wdrażamy, a potem patrzymy w logi.'`
* `pl-real-nagrywam-casual` / casual / run 1:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `winner`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-casual` / casual / run 2:
  * control: `'Teraz nagrywam po polsku, sprawdzam jak to działa.'`
  * `winner`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `winner`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-formal` / formal / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `winner`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 1:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `winner`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-nagrywam-neutral` / neutral / run 2:
  * control: `'Teraz nagrywam w języku polskim, sprawdzam, jak to działa.'`
  * `winner`: `'Teraz nagrywam w języku polskim, sprawdzam jak to działa.'`
* `pl-real-odzyskalem-casual` / casual / run 1:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `winner`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-casual` / casual / run 2:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `winner`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-formal` / formal / run 1:
  * control: `'Dobra wiadomość to fakt, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `winner`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-formal` / formal / run 2:
  * control: `'Dobra wiadomość to fakt, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `winner`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-odzyskalem-neutral` / neutral / run 1:
  * control: `'Dobra wiadomość to taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
  * `winner`: `'Dobra wiadomość jest taka, że odzyskałem swój polski. Udało mi się zrobić fork. Ben super whisper. Dałem drugi model. Jestem. Znowu po polsku.'`
* `pl-real-ziameczku-casual` / casual / run 2:
  * control: `'Dobra ziameczku, tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to, że żeś pieprzył po całości.'`
  * `winner`: `'Dobra ziameczku tak nie możesz tego zrobić. Musisz pójść zupełnie inną drogą. Bo tu chodzi o to że żeś pieprzył po całości.'`
* `pl-run-on` / casual / run 2:
  * control: `'No więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje.'`
  * `winner`: `'no więc myślę, że po prostu powinniśmy to wypuścić w piątek, jeśli nic się nie zepsuje'`


## English — no regression (44 answers)

Raw answers: `evidence/measure-en-after.json`; classification tool: `evidence/analyze13.py` over the real guard/detector; 11 cases per variant per run. Both arms send **byte-identical** English prompts — the comparison is the no-regression draw on the same bytes.

| variant | run | untouched | invented a word | lost a word | guard rejects | latency median (min–max) |
|---|---|---|---|---|---|---|
| `control` | 1 | 4 | 1 | 2 | 0 | 1.06 s (0.46–2.41) |
| `control` | 2 | 4 | 1 | 2 | 0 | 0.78 s (0.31–1.64) |
| `winner` | 1 | 4 | 1 | 2 | 0 | 0.77 s (0.31–1.65) |
| `winner` | 2 | 4 | 1 | 2 | 0 | 0.83 s (0.31–1.66) |

| variant | run-to-run determinism (identical prompt, two runs) |
|---|---|
| `control` | 0 of 11 answers differ |
| `winner` | 0 of 11 answers differ |

**Which cases failed, and with which words.**

`control`:

* run 1 — invented: en-plan-run-on (to); lost: en-plan-run-on (ok so we), en-real-keyboard (s)
* run 2 — invented: en-plan-run-on (to); lost: en-plan-run-on (ok so we), en-real-keyboard (s)

`winner`:

* run 1 — invented: en-plan-run-on (to); lost: en-plan-run-on (ok so we), en-real-keyboard (s)
* run 2 — invented: en-plan-run-on (to); lost: en-plan-run-on (ok so we), en-real-keyboard (s)

**Every case where a candidate's answer differs from the control's, verbatim.**

* `winner`: identical to the control on every case in every run.

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
 OpenSuperWhisper/TransformService.swift                    | 153 ++++++++++--
 OpenSuperWhisperTests/TransformServiceTests.swift           | 155 ++++++++------
 OpenSuperWhisperTests/TranscriptionLanguageGateTests.swift  |   8 +-
 Readme.md                                                   |   7 +-
 4 files changed, 262 insertions(+), 61 deletions(-)
```

Raw harness sources, every run's JSON, the classification output, the compiled-service prompt dumps before and
after, and the hashes of everything are in `evidence/`.
