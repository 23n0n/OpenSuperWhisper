# fm-20260923-24 — The dense middle: is a 4B–8B model enough for English → Polish?

Read-only measurement. **No repo file was modified; nothing was written under
`/Volumes/home/zenon/Projects/`.** Deliverable: this file. Scratch:
`/tmp/fm24/` (raw TSVs also copied to `data/fm-20260923-24/raw/`).
Every server started for the measurement was stopped: `pgrep llama-server` →
none, `lsof -nP -iTCP:1924 -sTCP:LISTEN` → empty.

Builds on `fm-20260923-19` (the two-point baseline) and uses the **same 15
English sentences, the same 8 Polish sentences, the same prompt shape and the
same sampler** — the app's `TranslationService.systemPrompt(for:)` +
`buildRequestBody` + `LlamaModel.makeSampler()` (`top_k 40, top_p 0.95,
min_p 0.05, temperature 0.2, seed 0`, `n_predict 1024`,
`chat_template_kwargs {enable_thinking:false}`, `/no_think` at the end of the
system prompt), on `llama-server --ctx-size 4096 --n-gpu-layers 99 --seed 0`,
one server at a time.

---

## Bottom line

**The smallest model measured that is worth having is `Qwen3-8B-Q4_K_M`
(5.03 GB on disk, 5.33 GB wired). It removes the shipped 1.5B's categorical
defect — it never invents content and never drops a fact — but it is not a free
win: it still mangles a verb phrase in 2 of 15 English → Polish cases, and it is
*slower* than the 30B-A3B it would replace.**

The dense middle does **not** reach the 30B's quality anywhere in 4B–8B, and the
best dense model is the *slowest* of the lot, because decode speed on this M4
tracks active parameters, not file size:

| backend | file | **wired** | EN→PL clean | invented | broken grammar | EN→PL mean | decode |
|---|---|---|---|---|---|---|---|
| `qwen2.5-1.5b-instruct-q4_k_m` (shipped) | 0.99 GB | **1.08 GB** | 4/15 | **2** | **5** | 0.53 s | ~75 tok/s |
| `Qwen3-4B-Instruct-2507-q4_k_m` | 2.50 GB | **3.16 GB** | 9/15 | 0 | 5 | 1.08 s | ~30 tok/s |
| `Qwen2.5-7B-Instruct-Q4_K_M` | 4.68 GB | **4.42 GB** | 10/15 | 1 | 4 | 2.07 s | ~18 tok/s |
| `Qwen3-8B-Q4_K_M` | 5.03 GB | **5.33 GB** | **11/15** | **0** | 2 | 1.93 s | ~17 tok/s |
| `Qwen3-30B-A3B-Instruct-2507-q4_k_m` | 19.03 GB | **18.17 GB** | **12/15** | **0** | **0** | **1.04 s** | ~36 tok/s |

Recommendation, plainly:

1. **If "reliably correct" means "never fabricates and never breaks grammar",
   the answer does not change: it is still the 30B-A3B — 18.17 GB.** No dense
   model in 4B–8B clears the broken-grammar bar (best: 2 in 15), and the 30B is
   simultaneously the *fastest* backend measured (1.04 s mean EN→PL vs the 8B's
   1.93 s). **The captain's ~18 GB buys quality *and* latency, not only quality.**
2. **If "reliably correct" means "never invents, never drops a fact, and its
   remaining errors are clumsy forms rather than silent corruption" — which is
   the defect the captain actually named — then `Qwen3-8B` at 5.33 GB wired is
   the smallest model that qualifies** (11/15 clean, 0 invented, deterministic
   in both directions). That is a **3.4× RAM saving** against the 30B, and it is
   a *dense* model that makes the 10-minute idle unload viable again.
3. **Nothing between 1.5B and 8B is reliable.** The 4B (3.16 GB) already stops
   the fabrication but breaks Polish grammar in 5 of 15 sentences; the
   `Qwen2.5-7B` (4.42 GB) is *worse* than the smaller 4B — it emitted a Cyrillic
   homoglyph (`Dогrawka`), a corrupted word (`Za%X morgna`) and a wholly
   fabricated sentence. The Qwen3-**2507** line is what makes the middle work;
   the app's own Qwen2.5 family does not.
4. **Do not move the daily direction.** Polish → English is 8/8 correct today on
   the shipped 1.5B at 0.30 s and 1.08 GB. The 8B is *not* uniformly better
   there: it echoed one Polish input back untranslated, and costs 5.33 GB.
5. **The 8B can honour the 10-minute idle unload; the 30B cannot.** Cold load
   (page cache verified evicted): 8B **3.21 s**, 4B 2.22 s, against the 30B's
   **43.7 s** (66.0 s in fm-19). The app calls `warmUpIfEnabled()` when recording
   *starts* (`AudioRecorder.swift:202`), so a 3.2 s load hides behind the user's
   speech; a 43–66 s load does not.

---

## 1. English → Polish — the decisive table

15 sentences: the 10 baseline sentences and the 5 adversarial (polarity /
negation) sentences fm-13/fm-19 used, md5-identical to fm-19's files.

Verdicts are mine, under a bar fixed before scoring: **correct** = faithful and
grammatical (minor diacritic/stylistic slips stay correct); **wrong word** = a
content word, numeral or preposition changes the meaning; **broken grammar** =
ungrammatical form, nonsense or corrupted characters; **invented content** =
content absent from the English, or a clause dropped and replaced.

| backend | correct | wrong word | broken grammar | invented |
|---|---|---|---|---|
| 1.5B (shipped) | 4/15 | 4 | 5 | 2 |
| **Qwen3-4B-2507 (3.16 GB)** | 9/15 | 1 | 5 | 0 |
| Qwen2.5-7B (4.42 GB) | 10/15 | 0 | 4 | 1 |
| **Qwen3-8B (5.33 GB)** | 11/15 | 2 | 2 | 0 |
| 30B-A3B (18.17 GB) | 12/15 | 3 | 0 | 0 |

fm-19's own counts for its two backends were 3/15 clean (3 invented, 4 broken)
for the 1.5B and 11/15 clean (0/0) for the 30B. My re-scoring of the same raw
outputs under my bar moves each by about a sentence (4/15 and 12/15); the
*ordering and the failure modes are identical*, and the difference is only how
strictly a clumsy word choice counts as "not clean". The counts above are the
ones I stand behind; where they are used for the comparison they are applied to
all five backends identically.

An **independent second rater** (a separate model, `deepseek-flash`, given the
English source and the Polish output and the same four-way rubric, 75
judgements) put the five backends at 1 / 7 / 10 / 10 / 10 "correct" out of 15 —
a stricter absolute count, but **the same ranking**, the same invented-content
counts for four of five backends, and the same finding that only the 30B has no
broken-grammar output. Raw agreement was 59/75 (79%). Detail:
`raw/verdicts.json`.

### Decisive examples

| English | 1.5B (1.08 GB) | Qwen3-4B (3.16 GB) | Qwen3-8B (5.33 GB) | 30B-A3B (18.17 GB) |
|---|---|---|---|---|
| "Close the window, it's cold outside." | Zamknij okno, jest zimno **za nami**. *(behind us)* | …jest zimno **na zewnątrz**. ✔ | …jest zimno **na zewnątrz**. ✔ | …jest zimno **na zewnątrz**. ✔ |
| "Tomorrow morning I'm taking the train to Krakow at seven." | Rano zjawi się za **trainem**… w **sobotę** o godzinie siedem. *(English leak + invented "on Saturday")* | Jutro rano biorę pociąg do Krakowa **o siedem**. *(wrong case: should be "o siódmej")* | Jutro rano wsiadam na pociąg do Krakowa **o siódmej**. ✔ *(minor collocation)* | Jutro rano jedziemy pociągiem do Krakowa o siódmej. ✔ |
| "The deployment failed because the database migration timed out." | …migrowanie bazy danych zakończyło się za **d束**. *(corrupted token)* | …migracja bazy danych **przekroczyła czas oczekiwania**. ✔ | …migracja bazy danych **wygasła**. *(expired — wrong word)* | …migracja bazy danych przekroczyła czas limitu. ✔ |
| "The contract has not been signed." *(adversarial)* | Kontrakt nie został **zatwierdzony**. *(approved ≠ signed; tolerable)* | Umowa nie została podpisana. ✔ | Umowa nie została podpisana. ✔ | Umowa nie została podpisana. ✔ |
| "The migration timed out, so the deployment failed." *(adversarial)* | **Przenośność sięga czasu**, więc… *(nonsense)* | **Przesłanie migracji wyprzeło się**, dlatego… *(nonsense)* | **Migracja wygasła**, więc… *(wrong word)* | **Migration** przekroczyła czas, więc… *(English word left in)* |

The long paragraph (sentence 7) is where the middle separates from the 1.5B:

* 1.5B — `…Jestem w stanie, bo to jest obiad dla mojej siostrzenicy.`: the order
  number is dropped and the birthday present for **the sister** becomes **dinner
  for the niece**. Fabrication.
* **Qwen3-4B** — faithful throughout; one broken clause: `Jestem w śpiesznych`.
* **Qwen3-8B** — faithful throughout, including `Jestem w pośpiechu` (*I'm in a
  hurry*, the phrase the 1.5B turned into "I am able"); one broken clause:
  `Zadzwońłem o sprawdzenie zamówienia` (should be *zadzwoniłem, żeby sprawdzić*).
* 30B — faithful; only `przypłynie` (*arrives by water*) is off.

**Reading of the failure modes.** The 1.5B fabricates and leaks English. The 4B
and 8B never fabricate — their errors are morphology, i.e. visibly wrong rather
than silently wrong. The 8B's two errors are both a mangled verb phrase in a
longer sentence; the 4B's five are spread over ordinary sentences (`o siedem`,
`nie mogę się przyjąć`, `Jestem w śpiesznych`, `wyprzeło się`, `się nie
powiela`). The 30B's worst output is a wrong word choice.

**Qwen2.5-7B deserves its own line**, because it is the option that *looks*
safest on paper (the app already ships Qwen2.5) and is not: it corrupted
`Tomorrow` into `Za%X morgna`, wrote the Cyrillic homoglyph `Dогrawka` for
*Umowa*, and on the long paragraph invented an entire opening —
`Dobrze, porozmawiamy. Wybieram się do pracy. Zadzwoniłem o godzinie 9…` ("Fine,
we'll talk. I'm off to work. I called at 9…") — none of which is in the English.
It is the second-largest dense model measured and the second worst.

---

## 2. Polish → English (the captain's daily path)

| # | Polish input | 1.5B | 4B | 8B | 30B-A3B |
|---|---|---|---|---|---|
| 1 | Teraz mówię po polsku i chcę, żeby była po polsku. | Now I speak Polish and want it to be in Polish. | Now I am speaking Polish and I want it to be in Polish. | **Teraz mówię po polsku i chcę, żeby była po polsku.** *(NOT TRANSLATED — echoed input)* | Now I'm speaking in Polish and I want it to remain in Polish. |
| 7 | Jutro rano jadę do Krakowa pociągiem o siódmej. | I am going to Krakow by train in the morning, at 7 o'clock. *(dropped "tomorrow")* | Tomorrow morning I'm going to Kraków by train at seven. | I'm going to Krakow by train at seven tomorrow morning. | Tomorrow morning I'm going to Kraków by train at seven. |
| 8 | Dzień dobry. Dzwonię w sprawie zamówienia numer 423… Zależy mi na czasie… | …**It's important to me that I know the delivery time**… *(paraphrased)* | …**I need to know the delivery time**… *(paraphrased)* | …It's important to me because it's a birthday gift… | …**I'm in a hurry** because it's a birthday present… |

All 8 sentences are semantically correct on all five backends. The 8B is
**7/8**: sentence 1 comes back in Polish, unchanged. So on the daily path the
ranking is 1.5B = 4B = 30B > 8B, and the shipped 1.5B — 8/8, 0.30 s, 1.08 GB —
remains the right default. **The only reason to add a bigger model is the
Polish-output direction.**

### Determinism

Every backend's Polish → English set was run **three times** through the same
loaded server; the output column is byte-identical (`shasum -a 256` of the
output column; `raw/out_*_plen_run*.tsv`):

| backend | PL→EN run1 vs run2 vs run3 | EN→PL run1 vs run2 | across *separate server processes* |
|---|---|---|---|
| 1.5B | identical | identical | — |
| Qwen3-4B | identical | identical | identical (both directions) |
| Qwen2.5-7B | identical | identical | — |
| Qwen3-8B | identical | identical | identical (both directions) |
| 30B-A3B | identical | identical | identical — **and identical to fm-19's run in a different session**, both directions |

**The daily direction is byte-identical on all five backends.** The
non-determinism fm-13 reported for the 1.5B (8/10 outputs differing) does **not**
reproduce on the `llama-server` path with the app's exact request shape: same
temperature, same `seed: 0`, and now three repeats plus two fresh server
processes plus a different session all agree. That points at the app's
*in-process* `TransformRuntime` path (a different runtime object and state than
the server's), not at the sampling parameters — which this read-only measurement
cannot test, and which is the one thing I would fix before blaming the model.

---

## 3. Latency

Warm (server loaded, one throwaway request first), `time_total` as reported by
`curl` — the same instrument fm-19 used, so the numbers are comparable. One
server resident at a time.

| backend | EN→PL (10) mean (range) | EN→PL adversarial (5) | PL→EN (8) mean (range) | server-reported decode |
|---|---|---|---|---|
| 1.5B | 0.53 s (0.22–1.34) | 0.30 s | 0.30 s (0.15–0.89) | ~65–85 tok/s |
| **Qwen3-4B** | **1.08 s (0.53–3.51)** | 0.71 s (0.41–1.01) | **0.60 s (0.28–1.94)** | ~27–34 tok/s |
| Qwen2.5-7B | 2.07 s (1.25–5.73) | 0.88 s (0.66–1.16) | 1.11 s (0.57–3.49) | ~15–21 tok/s |
| **Qwen3-8B** | **1.93 s (0.75–6.79)** | 1.05 s (0.60–1.28) | **1.35 s (0.58–4.30)** | ~15–19 tok/s |
| 30B-A3B | **1.04 s (0.68–2.81)** | 0.72 s | 0.78 s (0.35–2.27) | ~34–38 tok/s |

The outliers are the long paragraph (sentence 7): the 8B takes **6.8 s** for it
(~15 tok/s × 99 tokens), the 7B 5.7 s, the 4B 3.5 s, the 30B 2.8 s, the 1.5B
1.3 s. Everything else lands under 2.4 s.

**The dense 8B is about twice as slow as the 30B-A3B for every sentence,** and
this is not a measurement artefact: the 8B must read ~4.7 GB of weights per
token while the MoE reads ~1.9 GB (3B of 30B parameters active). The 4B is
roughly level with the 30B (1.08 s vs 1.04 s mean). So on this M4 **a bigger
dense model is the wrong lever: quality and speed both live in the 2507 MoE.**

Caveat on conditions: the machine was simultaneously running other agents'
Xcode work, and my first 4B and 30B EN→PL passes overlapped a 5 GB model
download. I re-ran the 4B and 8B cleanly afterwards (that is what the table
shows: 1.08 s and 1.93 s, against 1.54 s and 2.16 s in the contended pass —
the contended 4B even hit 6.16 s once, which is download I/O, not the model).
The 30B's 1.04 s was measured in a window that still overlapped the tail of a
download, so it is, if anything, understated.

---

## 4. Memory — measured two ways, because the fm-19 method breaks at this size

fm-19 measured wired memory as a before/after `Pages wired down` delta. **That
method has a noise floor of roughly ±3 GB on this machine** and I could not use
it as the primary instrument: with nothing of mine loaded, the wired counter
swung between 3.60 and 5.60 GB inside 40 s while sibling agents were building,
and dropped/rose by ~3 GB inside a single 0.5 s sample. A before/after pair
therefore *invented* a 3.12 GB "wired delta" for the 1.5B, whose real cost is
1.08 GB — and that is also why fm-19's "the 1.5B shows no wired delta" should be
read as noise, not as a measurement.

So I measured memory two independent ways and they agree.

**(a) llama.cpp's own Metal allocation report** (`-lv 5`, ctx 4096, every layer
offloaded on every model, `--n-gpu-layers 99`). The weights, the KV cache and
the compute buffer are allocated on the Metal device, i.e. in wired pages — this
is the number that actually lands on the machine:

| backend | file on disk | Metal weights | KV (4096 ctx) | compute | **wired total** | mmap, not wired |
|---|---|---|---|---|---|---|
| qwen2.5-1.5B | 0.99 GB | 934.69 MiB | 112.00 MiB | 62.51 MiB | **1.08 GB** | 182.57 MiB |
| **Qwen3-4B-2507** | 2.50 GB | 2375.91 MiB | 576.00 MiB | 76.33 MiB | **3.16 GB** | 304.28 MiB |
| Qwen2.5-7B | 4.68 GB | 4168.09 MiB | 224.00 MiB | 129.01 MiB | **4.42 GB** | 292.36 MiB |
| **Qwen3-8B** | 5.03 GB | 4789.19 MiB | 576.00 MiB | 92.01 MiB | **5.33 GB** | 333.84 MiB |
| Qwen3-30B-A3B | 19.03 GB | 18145.26 MiB | 384.00 MiB | 81.53 MiB | **18.17 GB** | 315.30 MiB |

The app's in-process `TransformRuntime` uses the same 4096-token context
(`Llama.defaultContextSize`), so the KV column transfers to the app unchanged;
the server's 4 slots share one unified cache, so there is no 4× inflation.

**(b) A wired-memory trace** — `Pages wired down` sampled every 0.5 s
(`raw/wired_trace_*.txt`), reading the *step* at load/unload rather than a
distant before/after pair:

| backend | vm_stat step | MTL report | agreement |
|---|---|---|---|
| Qwen3-4B | **+3.15 GB** at launch (median of 11 samples before → median of ~100 after: 5.33 → 8.48 GB) | 3.16 GB | **+0.01 GB** |
| Qwen3-8B | **−5.34 GB** at stop (8.94 → 3.60 GB inside one 0.5 s sample, then flat) | 5.33 GB | **−0.01 GB** |
| 30B-A3B | **−18.19 GB** at stop (21.80 → 3.61 GB in one 0.5 s sample, this session) | 18.17 GB | **−0.02 GB** |

The 30B is worth a note: its *load* rises gradually (18 GB spread over a 43 s
load, ≈0.2 GB per 0.5 s sample, so it never shows up as one jump), but its
*unload* is instantaneous and reads **18.19 GB** — i.e. my own corrected method
independently reproduces fm-19's ~18 GB and pins it to within 20 MB of the
allocation report, on a machine whose baseline was moving by ±3 GB at the time.

**Why RSS lies here** (the point fm-19 made, now with the numbers): process RSS
at the end of the load phase reads ≈ the file size (4B: 3.01 GiB; 8B: 5.35 GiB)
because that is the mmap'd GGUF, and it then collapses — fm-19's steady RSS for
the 19 GB 30B was 1.9 GB, and `footprint` reported 642 MB for the 4B and 509 MB
for the 30B. The Metal buffers are simply not in the process's dirty footprint.
Neither RSS nor `footprint` can answer this question; the MTL report and the
trace step can, and they agree to 20 MB on all three models.

**Context for the decision:** with the 8B resident the trace reads **8.94–9.07 GB
wired** (a 3.6 GB pre-load baseline plus the 5.34 GB step), which leaves more
than 20 GB for the OS, Whisper `large-v3-turbo` and normal desktop load. Under
the 30B the same machine sat at 22.94 GB wired, 0.42 GB free and 2.86 GB of swap
(fm-19). That contrast — ~9 GB against ~23 GB — is the whole RAM argument. I did
not sample free memory / swap with the 8B loaded, only wired.

---

## 5. Can it honour the 10-minute idle unload?

`TransformRuntime.idleUnloadInterval` is 10 minutes, and the reload is triggered
from `AudioRecorder.swift:202` via `TransformRuntime.shared.warmUpIfEnabled()` —
**at the moment recording starts, not when the transform runs**. So the load is
paid while the user is still speaking and overlaps the utterance; the transform
only waits for the remainder.

| backend | cold load (cache evicted) | warm-cache load | verdict |
|---|---|---|---|
| 1.5B | — | 1.06 s | unload is free |
| **Qwen3-4B** | **2.22 s** | 1.51 s | honours the contract |
| Qwen2.5-7B | — | 1.57 s | honours the contract |
| **Qwen3-8B** | **3.21 s** | 1.77 s | **honours the contract** — hidden by any utterance longer than ~3 s |
| 30B-A3B | **43.7 s** (this session; fm-19: 66.0 s) | — | **cannot** — either a 43–66 s stall once per idle window, or ~18 GB permanently resident |

Cold load was obtained honestly: `purge` needs a password we do not have, so I
churned a 12 GB junk file through the page cache and **verified the eviction** —
the 8B's file read at **15.4 GB/s** before the churn and **2.2 GB/s** after it
(the internal disk's real speed). Load times are llama.cpp's own
`llama_server: model loaded` timestamp, measured from process start, so they do
not carry my tool-call latency.

**So the answer to the captain's question is yes for the dense middle.** A
5.33 GB model that reloads in 3.2 s keeps the app's design intact: unload after
10 minutes, pay ~3 s once when dictation resumes (mostly behind the user's own
speech), which is exactly what the 1.5B's lifecycle assumes today. The 30B
breaks that design; the 8B does not.

---

## 6. Attach to the catalogue — exactly what was run

All three were downloaded into `/tmp/fm24-models/`; every SHA-256 was checked
against Hugging Face's published LFS object id and matches.

| id / file | bytes | disk | SHA-256 | source |
|---|---|---|---|---|
| `Qwen3-4B-Instruct-2507-Q4_K_M.gguf` | 2,497,281,120 | 2.50 GB | `3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597` | `https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf` |
| `Qwen3-8B-Q4_K_M.gguf` | 5,027,783,488 | 5.03 GB | `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785` | `https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf` |
| `Qwen2.5-7B-Instruct-Q4_K_M.gguf` | 4,683,074,240 | 4.68 GB | `65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423` | `https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf` |

Notes for a catalogue entry: the two Qwen3 files are Apache-2.0; `Qwen3-8B` is
the hybrid-thinking sibling of the 30B-A3B already measured and needs the same
`/no_think` + `enable_thinking:false` treatment the app already sends
(`Qwen3-4B-Instruct-2507` is non-thinking and ignores the flag harmlessly).
There is **no `Qwen3-8B-Instruct-2507`** — the 2507 line is 4B / 30B-A3B /
235B-A22B, which is why the 8B rung had to be plain `Qwen/Qwen3-8B-GGUF`.

Baselines used from fm-19, unchanged on disk:
`~/models/qwen2.5-1.5b-instruct-q4_k_m.gguf` (986,048,768 B) and
`~/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` (19,032,651,904 B,
`bc275be67acfdd0b25f07015e798efd99e449eeebb560e2c2e8c50b11abcd676`).

**Kept / deleted:** I kept the recommended model,
`/tmp/fm24-models/Qwen3-8B-Q4_K_M.gguf` (5.03 GB), so it can be tried
immediately, and **deleted the 4B and the Qwen2.5-7B** — they are reproducible
from the URL + SHA-256 rows above, and every result they produced is retained as
raw TSVs. Nothing else of mine is left outside `/tmp/fm24/` and
`data/fm-20260923-24/raw/` (45 files, 284 KB of TSVs, traces, verdicts JSON and
scripts).

---

## 7. What I could not measure

1. **The app's real in-process path.** Everything was measured through
   `llama-server` (the shipping llama.cpp/Metal path, identical parameters), as
   fm-19 did, because the app's catalogue accepts one pinned id and the repo is
   read-only. Quality transfers; the HTTP hop is included in the latency. **This
   matters most for the determinism question**: fm-13's 1.5B instability was
   seen in-process, and three repeats on the server path now contradict it, so
   the in-process path is the remaining suspect and I could not test it.
2. **A native Polish speaker's verdict.** All verdicts are mine, cross-checked
   by one independent model rater that agreed on the ranking, not by a human.
3. **Tone modes** on any new backend — only the plain translate prompt, which is
   the shape the app uses for the selectable Polish mode.
4. **End-to-end dictation** (audio → Whisper `large-v3-turbo` → transform) and
   the real coexistence of Whisper + the chosen model in one process lifetime.
   Memory figures are for the transform server alone.
5. **Sustained behaviour**: thermal throttling, and whether macOS compresses or
   evicts the wired weights under a longer, more varied load. Latency was also
   measured on a machine that other agents were actively building on; the
   4B/8B numbers were re-taken cleanly, the 30B's were not.
6. **The 14B rung.** The brief bounded the search at 4B–8B; if the captain wants
   zero broken grammar without 18 GB, `Qwen3-14B` q4_k_m (~9 GB, ~8–10 s cold
   load, still inside the idle-unload budget) is the next thing to measure — it
   is the only remaining rung between the 8B's 2/15 broken and the 30B's 0/15.
7. **`Qwen3-4B-Instruct-2507` at a higher quant** (q6/q8, ~3.5–4.5 GB), which
   would test whether the 4B's five broken sentences are a quantisation artefact
   rather than a capacity limit.
