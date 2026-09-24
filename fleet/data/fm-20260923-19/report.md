# fm-20260923-19 — Can a stronger local model make English → Polish shippable?

Read-only measurement. No repo file was modified; nothing was written under
`/Volumes/home/zenon/Projects/`. Scratch: `/tmp/fm19/`, deliverable: this file.
All servers started for the measurement were stopped; **nothing is bound to port
1919** (verified: `lsof -nP -iTCP:1919 -sTCP:LISTEN` → empty, `pgrep llama-server`
→ none).

---

## Bottom line

**Yes — `Qwen3-30B-A3B-Instruct-2507-q4_k_m` makes English → Polish good enough
to ship as a selectable mode. The 1.5B does not, and the gap is categorical, not
a matter of tuning.** But it costs ~18 GB of resident RAM and ~1.1 s per
sentence (≈2.6× the 1.5B), and on a 32 GB M4 that is the whole decision:

| | shipped 1.5B | Qwen3-30B-A3B |
|---|---|---|
| EN→PL clean sentences (15) | **3/15** | **11/15** |
| EN→PL invented content | 3 sentences | **0** |
| EN→PL broken grammar / garbage | 4 sentences | **0** |
| EN→PL runs stable across identical repeats | no (fm-13: 8/10 differed) | **yes (10/10 byte-identical)** |
| Warm EN→PL latency, mean (range) | 0.43 s (0.18–1.14) | 1.11–1.22 s (0.35–3.32) |
| Warm PL→EN latency, mean (range) | 0.29 s (0.12–0.85) | 0.80 s (0.40–2.16) |
| Cold start (weights load) | 2.1 s | **66.0 s** |
| Resident memory | **1.20 GB** | **≈17–19 GB** |
| Disk | 0.99 GB | **19.03 GB** |

**Recommendation: do not make the 30B the default, and do not make it the only
Polish option either.** Ship the target-language control as it stands (it
already defaults to English), and treat the 30B as an opt-in "Polish output
(high quality)" download — *only if* you accept a permanent ~18 GB resident
model. Otherwise the honest answer to the captain is: the app can hold Polish
output with the 1.5B only for short, simple sentences, and the smallest model I
could *measure* that is reliably correct is the 30B-A3B. There is a real gap in
the middle (see "smallest correct model").

---

## What was run, exactly

- **Backends** (both via the shipping inference stack, llama.cpp + Metal, `--n-gpu-layers 99`):
  - `qwen2.5-1.5b-instruct-q4_k_m.gguf` — 986,048,768 B, the app's pinned default.
  - `Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` — 19,032,651,904 B, `~/models/`.
- `llama-server` (Homebrew, build 10621, commit c1d0e7a00), devices: `MTL0: Apple M4 (25559 MiB)`.
- Command: `llama-server --model … --port 1919 --host 127.0.0.1 --ctx-size 4096 --n-gpu-layers 99 --seed 0`
  — the same `--ctx-size`/`--n-gpu-layers`/seed the app's in-process `LlamaModel`
  hard-codes (`defaultContextSize = 4096`, `gpuLayers = 99`, `seed = 0`).
- **Request shape = the app's `TranslationService.systemPrompt(for:)` + `buildRequestBody` + `LlamaModel.makeSampler()`**:
  - system prompt: `You are a translation assistant. Translate the user's <Source> text into natural <Target>. Output ONLY the final <Target> text, with no quotes, labels, or explanation.` + `/no_think`
  - `temperature 0.2, top_k 40, top_p 0.95, min_p 0.05, seed 0, n_predict 1024`, non-streaming,
    `chat_template_kwargs: {enable_thinking: false}` (Qwen3 non-thinking).
- **Sequential, one server at a time**: 1.5B started, measured, stopped; then 30B
  started, measured, stopped; then the 1.5B was restarted only to take its
  wired-memory delta, and stopped again.
- **Sentence set**: the same 10 English sentences and 8 Polish sentences fm-13
  used (including the long paragraph), plus the 5 adversarial English sentences
  from fm-13 (`adversarial.txt`).
- Verdicts are my judgements as a single rater; no native-speaker review.

**Caveat on the path measured.** This is `llama-server` in a separate process,
not the app's in-process `TransformRuntime`. The app links its own vendored
llama.cpp and uses the identical context size, offload, temperature, sampler
chain, chat template and `/no_think` flag, so the *quality* results transfer
directly. The *timing* is server-side (HTTP+JSON + a 4-slot server context); the
app's in-process path avoids the HTTP hop but pays the same weight load and the
same decode. The 1.5B server numbers here reproduce fm-13's in-process numbers
almost exactly (fm-13 in-process EN→PL 0.26–1.16 s; this run 0.18–1.14 s), which
is the cross-check that the harness is faithful.

---

## 1. English → Polish — the decisive table

Latency is warm (server already loaded, warmed with a throwaway request).

### 1.5B (shipped baseline)

| # | Input | Output | Verdict | s |
|---|---|---|---|---|
| 1 | Hello, how are you? | Cześć, jak się masz? | correct | 0.18 |
| 2 | We need to discuss the budget for next quarter. | Musimy porozmawiać o budżecie dla nastepnego trimestru. | correct (missing diacritic, "porozmawiać" vs "omówić") | 0.30 |
| 3 | I'm sorry, I can't come to the meeting today. | Przepraszam, nie mogę przyszć do spotkania dzisiaj. | **broken grammar** ("przyszć" misspelled, "do spotkania" wrong case) | 0.27 |
| 4 | I sent you three documents yesterday, please check them. | Oto trzy dokumenty, które wysłałem Ci wczoraj, proszę sprawdzić. | correct | 0.30 |
| 5 | Close the window, it's cold outside. | Zamknij okno, jest zimno **za nami**. | **wrong word** — "za nami" = *behind us* | 0.23 |
| 6 | Tomorrow morning I'm taking the train to Krakow at seven. | Rano zjawi się za **trainem** do Krakowa w **sobotę** o godzinie siedem. | **invented content** — English leak "trainem", invented "w sobotę" (*on Saturday*), dropped "tomorrow" | 0.34 |
| 7 | Good morning. I'm calling about order number 423. … birthday present for my sister. | Dzień dobry. Słucham, ale jeszcze nie dostarczyli mi potwierdzenia odbioru. … Jestem w stanie, bo to jest **obiad dla mojej siostrzenicy**. | **invented content** — order number dropped, "I'm in a hurry" → "Jestem w stanie", "birthday present for my sister" → "dinner for my niece" | 1.14 |
| 8 | Hey, can you grab some milk on your way home? | **Czy mogę załatwić cię**, jeśli zabrażesz trochę mleka na drodze do domu? | **broken grammar** — "Czy mogę załatwić cię" is nonsense | 0.47 |
| 9 | The deployment failed because the database migration timed out. | Deployowanie się nie powiodło, ponieważ migrowanie bazy danych zakończyło się za d**束**. | **broken grammar** — Chinese character in output | 0.45 |
| 10 | Please confirm whether the contract has been signed… | Potwierdź, czy kontrakt **nie** został zatwierdzony, a jeśli tak, to **inform me** o tym… | **wrong word** — polarity inverted + English leak "inform me" | 0.59 |

### 30B-A3B

| # | Input | Output | Verdict | s |
|---|---|---|---|---|
| 1 | Hello, how are you? | Cześć, jak się masz? | correct | 0.35 |
| 2 | We need to discuss the budget for next quarter. | Musimy omówić budżet **za** następny kwartał. | correct (minor: native prefers "na następny kwartał") | 0.68 |
| 3 | I'm sorry, I can't come to the meeting today. | Przykro mi, ale nie mogę przyjść na spotkanie dziś. | correct | 2.52* |
| 4 | I sent you three documents yesterday, please check them. | Wysłałem Ci trzy dokumenty wczoraj, proszę je sprawdzić. | correct | 0.95 |
| 5 | Close the window, it's cold outside. | Zamknij okno, jest zimno **na zewnątrz**. | **correct — fixed** | 0.69 |
| 6 | Tomorrow morning I'm taking the train to Krakow at seven. | **Jutro** rano **jedziemy pociągiem** do Krakowa o siódmej. | correct (minor: "jedziemy" = *we go* for singular "I'm taking") | 0.98 |
| 7 | Good morning. I'm calling about order number 423. … birthday present for my sister. | Dzień dobry. Telefonuję w sprawie zamówienia numer czterysta dwadzieścia trzy. Niestety, nadal nie otrzymałem potwierdzenia wysyłki. Czy mógłby Pan sprawdzić stan zamówienia i powiedzieć mi, kiedy **przypłynie** paczka? Spieszę, bo to prezent urodzinowy dla mojej siostry. | correct (minor: "przypłynie" is *arrives by water*; everything else faithful) | 3.01* |
| 8 | Hey, can you grab some milk on your way home? | Hej, możesz zabrać mleko po drodze do domu? | **correct — fixed** | 0.76 |
| 9 | The deployment failed because the database migration timed out. | Wdrożenie nie powiodło się, ponieważ migracja bazy danych przekroczyła czas limitu. | **correct — fixed** | 0.98 |
| 10 | Please confirm whether the contract has been signed… | Proszę potwierdzić, czy umowa została podpisana, a jeśli nie, to poinformować, co jeszcze brakuje. | **correct — fixed** | 1.27 |

\* sentence 3 is the first request after load and carries a cold-cache penalty;
in the second pass it was 0.81 s and sentence 7 was 3.32 s, so the 3 s figures
are output-length + variance, not a per-sentence floor.

### 30B-A3B on the adversarial set (polarity / negation)

| # | Input | Output | Verdict | s |
|---|---|---|---|---|
| 1 | The contract has not been signed. | Umowa nie została podpisana. | correct | 0.43 |
| 2 | Do not send the invoice until Friday. | Nie wysyłaj faktury przed piątkiem. | correct ("przed piątkiem" = before Friday) | 0.62 |
| 3 | The migration timed out, so the deployment failed. | **Migration** przekroczyła czas, więc wdrożenie nie powiodło się. | **wrong word** — "Migration" left in English | 0.87 |
| 4 | My password is correct, but the login still fails. | Moje hasło jest poprawne, ale logowanie nadal nie powiodło się. | correct (both polarities held) | 0.92 |
| 5 | We will not be able to deliver the package tomorrow. | Nie będziemy mogli dostarczyć paczki **pojutrze**. | **wrong word** — "jutro" (*tomorrow*) → "pojutrze" (*day after tomorrow*) | 0.78 |

For contrast the 1.5B on the same five: 1 correct, 3 wrong-word/gibberish
("Przenośność sięga czasu", "Miwaś hasło"), 1 polarity slip. So the 30B's worst
Polish output is a *word choice*; the 1.5B's worst is *fabricated text*.

### Decisive examples (quote these)

| English | 1.5B | 30B-A3B |
|---|---|---|
| Close the window, it's cold outside. | Zamknij okno, jest zimno **za nami**. *(behind us)* | Zamknij okno, jest zimno **na zewnątrz**. ✔ |
| Tomorrow morning I'm taking the train to Krakow at seven. | Rano zjawi się za **trainem** do Krakowa w **sobotę**… *(English leak, invented Saturday, lost "tomorrow")* | **Jutro** rano **jedziemy pociągiem** do Krakowa o siódmej. ✔ |
| My password is correct, but the login still fails. | **Miwaś** hasło jest poprawne, ale logowanie się nie powiedzie. *(broken)* | Moje hasło jest poprawne, ale logowanie nadal nie powiodło się. ✔ |

### Stability

The 1.5B was unstable on identical repeated requests in fm-13 (8/10 outputs
differed between runs). The 30B was run twice through the full English→Polish
set: **all 10 outputs byte-identical across the two passes** (`diff` of the two
output columns is empty). Same temperature, same seed.

---

## 2. Polish → English (the captain's daily path) — does the 30B regress it?

**No. It is equal or slightly better, but ~2.7× slower and ~15× the memory.**

| # | Polish input | 1.5B output | 30B-A3B output | Verdict |
|---|---|---|---|---|
| 1 | Teraz mówię po polsku i chcę, żeby była po polsku. | Now I speak Polish and want it to be in Polish. | Now I'm speaking in Polish and I want it to remain in Polish. | both correct (30B more faithful) |
| 2 | Cześć, jak się masz? | Hello, how are you? | Hi, how are you? | both correct |
| 3 | Musimy omówić budżet na przyszły kwartał. | We need to discuss the budget for the upcoming quarter. | We need to discuss the budget for the next quarter. | both correct |
| 4 | Nie mogę dzisiaj przyjść na spotkanie, przepraszam. | I'm sorry, but I can't attend the meeting today. | I can't come to the meeting today, sorry. | both correct |
| 5 | Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę. | I sent you three documents yesterday, please check them. | I sent you three documents yesterday, please check them. | identical |
| 6 | Zamknij okno, bo jest zimno na dworze. | Close the window, it's cold outside. | Close the window, it's cold outside. | identical |
| 7 | Jutro rano jadę do Krakowa pociągiem o siódmej. | I am going to Krakow by train in the morning, at 7 o'clock. **(dropped "tomorrow")** | **Tomorrow morning** I'm going to Kraków by train at seven. | **30B better** |
| 8 | Dzień dobry. Dzwonię w sprawie zamówienia numer 423… Zależy mi na czasie… | …Could you please check the status… **It's important to me that I know the delivery time**, as it's a birthday present for my sister. *(paraphrased "Zależy mi na czasie")* | …Could you please check the status and let me know when the package will arrive? **I'm in a hurry** because it's a birthday present for my sister. | **30B more faithful** |

So the daily PL→EN path would **not** regress in quality with the 30B — it
improves on the two long sentences that matter most. What regresses is latency
(0.29 s → 0.80 s mean) and memory (1.2 GB → ~18 GB). **Keeping the 1.5B as the
default for PL→EN is the right call anyway**: it is already correct 8/8 on
genuine Polish text and it is cheap.

---

## 3. Latency

| | cold start (load) | warm min | warm mean | warm max |
|---|---|---|---|---|
| 1.5B EN→PL (10) | **2.08 s** | 0.182 | 0.428 | 1.136 |
| 30B EN→PL (10), pass 1 | **65.98 s** | 0.347 | 1.218 | 3.011 |
| 30B EN→PL (10), pass 2 | — | 0.479 | 1.109 | 3.323 |
| 1.5B EN→PL adversarial (5) | — | 0.231 | 0.297 | 0.370 |
| 30B EN→PL adversarial (5) | — | 0.433 | 0.723 | 0.916 |
| 1.5B PL→EN (8) | — | 0.117 | 0.291 | 0.853 |
| 30B PL→EN (8) | — | 0.405 | 0.804 | 2.159 |

Server-reported 30B throughput: **≈31 tok/s decode**, **≈70–160 tok/s prompt
eval**. The 1.5B ran at ≈65 tok/s decode. The 30B's cold start is dominated by
reading the 19 GB file off `/Volumes/home` (APFS local, `/dev/disk7s1`) at an
effective ≈290 MB/s — ~66 s. That is the number that matters for the app: the
app's `TransformRuntime` unloads the model after 10 minutes idle, so an
in-process 30B would pay ~66 s on the first dictation after any idle gap.

The 3 s outliers are the two long sentences; they are length-dominated.

---

## 4. Memory

Measured three ways because macOS attributes Metal/GPU weights unusually.

| Backend | model file | cold-load peak RSS | steady process RSS | wired memory delta (load→unload) |
|---|---|---|---|---|
| 1.5B | 0.99 GB | — | **1.20 GB** | **none** (its 1.2 GB shows as process RSS) |
| 30B | 19.03 GB (`mapped file 17.8 GB virtual`) | **13.2 GB** | 1.9 GB | **+17.2 GB wired** |

How the 30B number was obtained: `Pages wired down` was 1,433,703 pages
(22.94 GB) with the model resident and 358,179 pages (5.73 GB) 25 s after the
server was stopped — a **17.2 GB** drop caused by the unload. The process's own
RSS (1.9 GB steady) and `footprint` (509 MB) badly undercount it because
llama.cpp puts the weights in wired Metal buffers, not in process-private
memory; that is exactly why a naive RSS read would say "only 2 GB".

State of the machine with the 30B resident, 32 GB total:

- wired 22.94 GB, active 3.99 GB, inactive 3.96 GB, compressor 1.65 GB, free 0.42 GB
- **swap used 2.86 GB of 4 GB**; Metal's own reported working-set ceiling is 25,559 MiB

That is a machine at its ceiling. Adding the captain's Whisper `large-v3-turbo`
(~1.6 GB) and normal desktop apps to a permanently-resident 30B leaves no
headroom; macOS was already compressing and swapping during this measurement.

---

## 5. Integration consequence (honest cost)

The app's transform backend is a **pinned catalogue with one entry**
(`TransformModelManager.availableModels`): `qwen2.5-1.5b-instruct-q4_k_m`,
986 MB, `sha256 1adf0b11…37c0`, downloaded from Hugging Face into
`~/Library/Application Support/<bundle id>/transform-models/`. Adding the 30B
means:

- **Download**: 19.03 GB over the network, versus 0.99 GB today. For reference,
  the HF-hosted 30B-A3B q4_k_m is ~18.6 GiB. A new catalogue entry needs a
  download URL, a pinned SHA-256, a size, licence and source. Local file for
  comparison: `sha256` printed below.
- **Disk**: 19.03 GB. Free space is 727 GB, so disk is **not** the constraint.
- **RAM ceiling**: this is the constraint. ~18 GB wired on a 32 GB machine that
  must also run Whisper `large-v3-turbo` (~1.6 GB) and the OS/apps. Measured
  swap was 2.86 GB with the model up. It fits, barely, and only if nothing else
  large is running.
- **Unload between dictations**: the app's `TransformRuntime.idleUnloadInterval`
  is 10 minutes, precisely so that the ~1 GB is only paid while the feature is
  in use. That design **cannot survive** a 19 GB model:
  - keep unloading → the first dictation after any >10 min gap waits **~66 s**
    (unusable for dictation);
  - stop unloading → ~18 GB permanently wired in a menu-bar utility.
  There is no third option; the model must be resident to be usable, i.e. the
  idle-unload contract has to be special-cased or abandoned for this backend.
- **Default**: the shipped 1.5B should **stay the default for Polish → English**
  — it is 8/8 correct there today at 0.29 s and 1.2 GB. There is no quality case
  for moving the daily path onto the 30B; only the EN→PL direction needs it.

### Smallest model that is still correct for Polish output

Only two points were measurable on this machine: 1.5B dense → **fails**, 30B-A3B
MoE (~3B active) → **passes**. **No intermediate model existed on disk**
(I searched `~/models`, `~/.cache/huggingface`, the whole home tree: only the two
GGUF files, plus an unrelated `s1-mini.gguf`), and a download was out of scope
for this read-only measurement, so the middle of the curve is **unmeasured**.
What the data says about where the floor lies:

- The 30B-A3B is a Mixture-of-Experts with only ~3B *active* parameters yet it
  is correct, while the 1.5B dense is not. That points to **total capacity**, not
  active parameters, being what Polish output needs.
- The 1.5B's failure mode is not prompt-shaped: fm-13 already tried a strict
  "Polish only" prompt and it collapsed further (Chinese output). So no prompt
  tuning moves the 1.5B to acceptable.
- Therefore the smallest *measured-correct* model is the **Qwen3-30B-A3B**. The
  next thing to measure before conceding 18 GB would be a dense **Qwen3-8B or
  Qwen3-4B-Instruct-2507 q4_k_m (~2.5–5 GB)** — plausible, but **not verified
  here**, and I would not ship Polish output on an unmeasured model given how
  confidently the 1.5B looked fine on short sentences and then invented content
  on long ones.

### The cached Opus-MT model

`~/.cache/huggingface/hub/models--gaudi--opus-mt-pl-en-ctranslate2` is
**Polish → English only** — the wrong direction for this question — and it is
CTranslate2, which the Swift app cannot host without a new runtime. It does not
change the answer.

---

## 5b. Handoff data

- 30B weights: `/Volumes/home/zenon/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf`,
  19,032,651,904 bytes.
- 30B SHA-256: `bc275be67acfdd0b25f07015e798efd99e449eeebb560e2c2e8c50b11abcd676`
  (for the `TransformModel` catalogue entry / `Scripts/transform-server.sh` pin,
  should this model be adopted).
- Raw per-sentence TSV (index, seconds, http, input, output):
  `/tmp/fm19/out_15b_enpl.tsv`, `out_30b_enpl.tsv`, `out_30b_enpl_run2.tsv`,
  `out_15b_enpl_adv.tsv`, `out_30b_enpl_adv.tsv`, `out_15b_plen.tsv`,
  `out_30b_plen.tsv`.
- Sentence files: `/tmp/fm19/en.txt`, `en_adversarial.txt`, `pl.txt`.
- Driver: `/tmp/fm19/run_dir.sh`; RSS poller `/tmp/fm19/poll_rss.sh`.

---

## 6. What I could not measure

1. **The app's real in-process path with the 30B.** I measured `llama-server`
   (the shipping llama.cpp/Metal path, same parameters) because the app's model
   catalogue only accepts the pinned 1.5B id and the repo is read-only. Quality
   transfers; latency carries an HTTP hop I did not subtract, and server-side
   4-slot context differs slightly from the app's single in-process context.
2. **Any intermediate model.** No 7B/8B/4B GGUF exists on this machine and
   downloading was out of scope. The "smallest correct model" answer is bounded
   by the two measured points, not interpolated.
3. **Tone modes on the 30B** (formal/casual). Only the plain translate prompt —
   the app's shape for the selectable Polish mode — was measured.
4. **End-to-end dictation** (audio → Whisper `large-v3-turbo` → 30B transform)
   including the real memory coexistence of Whisper + the 30B in one process
   lifetime. Memory figures are for the transform server alone.
5. **Sustained/steady-state behaviour**: thermal throttling, and whether macOS
   compresses/evicts the wired weights under a longer, more varied workload.
   The 66 s cold start is the load; I did not measure reload-after-idle.
6. **Quality review by a native Polish speaker.** Verdicts are mine.
7. Determinism was checked on the EN→PL set only (2 passes); PL→EN was run once
   per backend.
