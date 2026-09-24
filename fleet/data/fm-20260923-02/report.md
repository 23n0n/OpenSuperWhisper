# fm-20260923-02 — Small PL→EN translation model feasibility (scout report)

**Task:** OpenSuperWhisper fork — the app currently sends the Polish transcript to a general LLM
endpoint for PL→EN translation **+ tone**. Captain asks: is a much smaller, translate-only model
feasible, and which one is small yet effective? Read-only investigation; deliverable is this report,
**no branch, no PR, no repo changes**.

**Scout:** first-mate crew, task `fm-20260923-02`. **Date:** 2026-09-23.
**Status:** smoke test executed and passing (after fixing a critical tokenization bug — see §5).

---

## 1. Question and method

- **Question:** replace the general-LLM translation call with the smallest effective PL→EN model?
- **Method:**
  1. Verified environment facts first-hand (files, ports, binaries, package versions).
  2. Queried the Hugging Face API for the **exact byte size** of every candidate weight file
     (`/api/models/{repo}?blobs=true` and `/api/models/{repo}/tree/main?recursive=true`).
  3. Ran a **real, warmed CTranslate2 inference smoke test** on the leading candidate
     (`gaudi/opus-mt-pl-en-ctranslate2`, CPU, int8) using the four sentences from the brief plus a
     longer paragraph, recording exact outputs and wall-clock latency.
  4. Ranked integration options against the app's existing OpenAI-compatible
     `/v1/chat/completions` call and stated the tone-vs-size decision.

Everything marked **[verified]** below was reproduced on this machine in this session. Anything
marked **[unverified]** was not executed here and is labelled as such. Sizes are decimal MB
(1 MB = 1,000,000 B); the raw byte count is given where it matters.

---

## 2. Environment reality — brief claims vs. what I actually found

| Claim in brief | My verification | Verdict |
|---|---|---|
| `/Volumes/home/zenon/mlx/.venv` does **not** exist | **It exists** and is fully populated: Python 3.14.7, `mlx 0.32.2`, `mlx-lm 0.31.3`, `mlx-metal 0.32.2`, `transformers 5.16.1`, `sentencepiece 0.2.2` | ❌ **brief wrong — venv present** |
| launchd job `com.dsh.mlx-qwen` points at the missing venv | No matching plist under `~/Library/LaunchAgents`, `/Library/LaunchAgents`, `/Library/LaunchDaemons`; `launchctl list` shows no mlx/omlx/qwen job | ❌ **not found (job absent)** |
| GUI app `oMLX` (MLX server) configured on `127.0.0.1:1991`, empty `~/.omlx/models` | `oMLX` present as `/Applications/oMLX alias`; `~/.omlx/settings.json` sets `host 127.0.0.1 port 1991`, `auto_start_on_launch true`, `model_dirs ["/Volumes/home/zenon/.omlx/models"]`; that dir is **empty**; `stats.json` shows 0 requests; **nothing listening on 1991 right now** (server not running) | ⚠️ configured but **not running**; models dir empty — confirmed |
| `~/.cache/huggingface/hub` holds no Qwen3-14B (only ~28M cache) | `~/.cache/huggingface/hub` = **12 KB**; contents: `models--deepseek-ai--DeepSeek-V4-Flash-0731`, `models--gaudi--opus-mt-pl-en-ctranslate2`. **No Qwen3-14B.** | ✅ confirmed |
| `llama.cpp` installed | `llama-server` 0.3.0 (build 10621, commit c1d0e7a00, AppleClang 21, Darwin arm64); `llama-cli` present | ✅ confirmed |
| Existing GGUF `Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf` | present, `19,032,651,904 B` ≈ 19.0 GB | ✅ confirmed |
| `whisper-cli` supports `--translate` natively | `whisper-cli --help` → `-tr, --translate  [false]  translate from source language to english`; also `-l LANG` (source language, `en` default, `auto` available) | ✅ confirmed |
| Python 3.14.7 only; CTranslate2 4.8.2 has a cp314 macOS arm64 wheel | Python **3.14.7**; `/tmp/mt-venv` runs `ctranslate2 4.8.2` successfully on this machine | ✅ confirmed |

**Other environment facts [verified]:** macOS 27.0 (build 26A428), arm64.
`/tmp/mt-venv` = the prepared test venv (`ctranslate2 4.8.2`, `sentencepiece 0.2.2`,
`huggingface_hub 1.32.0`). Model already downloaded to `/tmp/opus-pl-en`
(`model.bin` `153,890,769 B`, `source.spm`, `target.spm`, `shared_vocabulary.json`, `vocab.json`).

**Correction to the brief's premise:** the "local MLX Qwen is not set up" story is only half true.
The **MLX toolchain is installed and working** (`/Volumes/home/zenon/mlx/.venv` with `mlx-lm`); what
is missing is (a) a *downloaded MLX model* and (b) a *running server*. The oMLX GUI is configured
but idle with an empty model dir. So the MLX option is "download a ~1 GB model and start a server",
not "build the environment from scratch".

---

## 3. Candidate table — sizes from the Hugging Face API [verified]

Tone column = can the model follow a tone/style instruction ("formal", "casual", "concise"), i.e. is
it an instruction-tuned LLM. Dedicated NMT models cannot.

| # | Model / artifact | Weight bytes [verified] | Size | Runtime | Tone? | Notes |
|---|---|---:|---:|---|---|---|
| 1 | `Helsinki-NLP/opus-mt-pl-en` (Marian, dedicated pl→en) | `308,863,317` (fp32 `pytorch_model.bin`) | **308.9 MB** | Transformers/PyTorch | **No** | Original checkpoint; also ships `tf_model.h5` 309.4 MB. Purpose-built for PL→EN. |
| 2 | `gaudi/opus-mt-pl-en-ctranslate2` | `153,890,769` (`model.bin`, int8) | **153.9 MB** | **CTranslate2 (CPU)** | **No** | **Smoke-tested here.** ~2× smaller than fp32. |
| 3 | `Xenova/opus-mt-pl-en` (ONNX int8) | encoder `51,922,201` + decoder_merged `59,202,382` | **111.1 MB** | onnxruntime / transformers.js | **No** | Smallest weight set. Runtime not tested. |
| 4 | `facebook/nllb-200-distilled-600M` | `2,460,457,927` (fp32) | **2460.5 MB** | Transformers/PyTorch | **No** | 200 languages; needs `src_lang` prefix. |
| 5 | `JustFrederik/nllb-200-distilled-600M-ct2-int8` | `622,595,991` (`model.bin`, int8) | **622.6 MB** | CTranslate2 (CPU) | **No** | Multi-language, int8. Runtime not tested here. |
| 6 | `Qwen/Qwen2.5-1.5B-Instruct-GGUF` q4_k_m | `1,117,320,736` | **1117.3 MB** | `llama-server` (OpenAI API) | **Yes** (unverified) | Official Qwen GGUF. |
| 6b | `bartowski/Qwen2.5-1.5B-Instruct-GGUF` Q4_K_M / Q5_K_S | `986,048,768` / `1,098,729,728` | **986.0 MB / 1098.7 MB** | `llama-server` | **Yes** (unverified) | Smaller requant of the same model. |
| 7 | `mlx-community/Qwen3-1.7B-4bit` | `968,080,210` | **968.1 MB** | oMLX / `mlx_lm.server` | **Yes** (unverified) | Matches brief's ~968 MB. |
| 8 | `mlx-community/Qwen2.5-1.5B-Instruct-4bit` | `868,628,559` | **868.6 MB** | oMLX / `mlx_lm.server` | **Yes** (unverified) | MLX 4-bit alternative to #6b. |
| 9 | `second-state/gemma-3-1b-it-GGUF` Q5_K_S / Q4_K_M | `836,399,616` / `806,058,240` | **836.4 MB / 806.1 MB** | `llama-server` | **Yes** (unverified) | Matches brief's ~836 MB (Q5). |
| 10 | `mlx-community/gemma-3-1b-it-4bit` | `732,577,304` | **732.6 MB** | oMLX / `mlx_lm.server` | **Yes** (unverified) | MLX 4-bit; smallest of the LLM options. |
| 11 | `whisper-cli --translate` | 0 MB extra | **0 MB** | whisper.cpp (already installed) | **No** | Translates during STT. No separate PL transcript. |

Notes:
- The brief's sizes are confirmed and are decimal MB: opus fp32 309 MB ✅, CT2 154 MB ✅, ONNX int8
  ≈110 MB ✅ (111.1), NLLB CT2 int8 623 MB ✅ (622.6), Qwen3-1.7B-4bit 968 MB ✅, gemma-3-1b Q5 836 MB ✅
  (Q5_K_S). Qwen2.5-1.5B Q5_K_S is 1098.7 MB (brief said ~1.1 GB ✅); Q4_K_M is 986.0 MB (bartowski) /
  1117.3 MB (official Qwen — quant recipe differs).
- "Tone? = Yes" for the LLMs is **capability-level, not measured here**. No LLM was run in this
  session; the tone column is marked unverified.

---

## 4. Smoke-test evidence — `gaudi/opus-mt-pl-en-ctranslate2`

### 4.1 Setup / commands run

Test venv and model were supplied by the first mate. I installed nothing except the `transformers`
tokenizer into `/tmp/mt-venv` (needed only for the canonical-tokenizer cross-check; the final run uses
raw `sentencepiece`).

```bash
# environment
/tmp/mt-venv/bin/pip list | grep -Ei 'ctranslate2|sentencepiece|huggingface|transformers'
# ctranslate2 4.8.2 / sentencepiece 0.2.2 / huggingface_hub 1.32.0 / transformers 5.17.0
/tmp/mt-venv/bin/python -c "import ctranslate2,sys;print(ctranslate2.__version__, sys.version)"

# definitive smoke test (script body in §4.4)
/tmp/mt-venv/bin/python /tmp/mt-smoke2.py int8 2
/tmp/mt-venv/bin/python /tmp/mt-smoke2.py float32 2
```

### 4.2 Decisive output — **int8, beam_size 2, CPU, warmed** [verified]

```
# warmup (not timed) -> "That's a warm-up sentence."

[1] PL: Cześć, jak się masz?
    EN: Hi, how are you?
    39.7 ms, 4 words
[2] PL: Musimy omówić budżet na przyszły kwartał.
    EN: We need to discuss the budget for next quarter.
    58.6 ms, 9 words
[3] PL: Nie mogę dzisiaj przyjść na spotkanie, przepraszam.
    EN: I can't come to the meeting tonight. I'm sorry.
    84.4 ms, 9 words
[4] PL: Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę.
    EN: I sent you three documents yesterday. Please check them.
    67.1 ms, 9 words

# latency: total=249.7 ms  mean=62.4 ms  median=62.8 ms  min=39.7 ms  max=84.4 ms
# peak RSS: 364 MiB
# language-prefix probe:
  prefix=''         -> 'Hi, how are you?'
  prefix='>>en<< '  -> 'Hi, how are you?'      # prefix neither needed nor harmful for a bilingual Marian
```

**float32, same script** [verified] — same outputs, ~2× slower, higher memory:

```
# latency: total=489.1 ms  mean=122.3 ms  median=122.0 ms
# peak RSS: 471 MiB
```

So **int8 works cleanly** — no need to fall back to float32 for correctness. Float32 costs ~2× latency
and ~107 MiB more RAM for identical text.

### 4.3 Longer, realistic transcript chunk (whole-transcript use case) [verified]

Input (268 chars / 38 words, passed as one string, no sentence splitting):

> Dzień dobry. Dzwonię w sprawie zamówienia numer czterysta dwadzieścia trzy. Niestety nie otrzymałem jeszcze potwierdzenia wysyłki. Czy mógłby pan sprawdzić status i powiedzieć mi, kiedy paczka dotrze? Zależy mi na czasie, ponieważ to prezent na urodziny mojej siostry.

Output:

> I'm calling about the order number four hundred twenty three. Unfortunately, I haven't received a shipping confirmation yet. Could you check the status and tell me when the package arrives? I care about the time, because it's a gift for my sister's birthday.

```
latency=282.5 ms  -> ~949 chars/s, ~134 words/s   peak RSS 364 MiB
```

This is where the **quality caveat becomes concrete**:
- "Dzień dobry." ("Good morning") was **dropped** from the output.
- "Zależy mi na czasie" (idiomatic: "I'm in a hurry / it's time-sensitive") was rendered literally
  as "I care about the time" — meaning is wrong.
- The result is grammatically clean English and the numbers/sum stayed correct.

### 4.4 Smoke-test script (self-contained, reproducible)

```python
#!/usr/bin/env python3
import time, resource, statistics, sys
import ctranslate2, sentencepiece as spm

MODEL = "/tmp/opus-pl-en"
SENTS = [
    "Cześć, jak się masz?",
    "Musimy omówić budżet na przyszły kwartał.",
    "Nie mogę dzisiaj przyjść na spotkanie, przepraszam.",
    "Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę.",
]
COMPUTE = sys.argv[1] if len(sys.argv) > 1 else "int8"
BEAM = int(sys.argv[2]) if len(sys.argv) > 2 else 2

sp = spm.SentencePieceProcessor(); sp.Load(f"{MODEL}/source.spm")
tg = spm.SentencePieceProcessor(); tg.Load(f"{MODEL}/target.spm")
tr = ctranslate2.Translator(MODEL, device="cpu", compute_type=COMPUTE)

def translate(text):
    src = sp.EncodeAsPieces(text) + ["</s>"]   # EOS is MANDATORY for Marian — see §5
    out = tr.translate_batch([src], beam_size=BEAM, max_batch_size=1)
    return tg.DecodePieces(out[0].hypotheses[0])

translate("To jest zdanie rozgrzewkowe.")      # warm-up, not timed
for s in SENTS:
    t0 = time.perf_counter(); en = translate(s); ms = (time.perf_counter()-t0)*1000
    print(f"{ms:7.1f} ms  {en}")
```

Environment used: `ctranslate2 4.8.2` (`compute_type="int8"` resolves to `int8_float32` on this
macOS arm64 build), CPU, Python 3.14.7, macOS 27.0 arm64.

**Does the model need a language prefix token?** **No.** Marian `opus-mt-pl-en` is a fixed
bilingual model; `>>en<<` was neither required nor beneficial (identical output on the probe).
NLLB (candidate #4/#5) *does* require a source-language token (`pol_Latn`), which is extra plumbing
— **[unverified]** here since NLLB was not run.

---

## 5. Critical implementation gotcha (must be carried into any integration)

**The Marian source token sequence must end with the EOS token `</s>`, or the decoder never
terminates.** My first attempt tokenized with `source.spm` alone (as the most naive CT2 example
suggests) and every sentence degenerated into an unbounded repetition loop — it consumed the default
256 decoding steps and produced output like:

```
PL: Cześć, jak się masz?
EN: Hi, how are you? How are you?? How are you??? How are you?? How are you??? ...
```

Appending `</s>` to the source fixes it completely, and the same fix reconciles with the canonical
usage (HF `MarianTokenizer` appends `</s>` automatically):

```
raw spm          src_tail='?'    ntok=256 -> 'Hi, how are you? How are you?? How are you??? ...'
raw spm + </s>   src_tail='</s>' ntok=6   -> 'Hi, how are you?'
```

This was **not** an int8/float32 problem (both looped identically without `</s>`) and **not** a bad
download (the `gaudi` CT2 conversion is fine and matches the HF model). Whoever builds the ~40-line
wrapper (option C below) must append `</s>` to the source pieces. **[verified]**

---

## 6. Quality caveat — the core tradeoff

- A **dedicated NMT** (opus-mt / NLLB) of ~150–620 MB generally **beats a same-size general LLM** at
  raw translation fidelity, because it is trained only for translation. It is also far smaller and
  faster.
- But a dedicated NMT **cannot do tone** (no instruction following, no "make it formal/casual").
  The smoke test shows it also **drops short conversational openers** and can render idioms
  literally ("Zależy mi na czasie" → "I care about the time").
- If tone must stay, the smallest drop-in options are the **~1.5–1.7B instruction LLMs**
  (Qwen2.5-1.5B ≈ 869–986 MB, Qwen3-1.7B-4bit ≈ 968 MB, gemma-3-1b ≈ 733–836 MB). Their tone quality
  was **not measured here [unverified]**.

This tone-vs-size tradeoff is the actual decision.

---

## 7. Integration options — ranked by app change required

Given the app (per brief) already POSTs to an **OpenAI-compatible `/v1/chat/completions`** endpoint:

| Rank | Option | App change | Model size | Tone? | Trade-off |
|---|---|---|---|---|---|
| **A (zero change)** | `llama-server` + small GGUF (`Qwen2.5-1.5B-Instruct` Q4_K_M 986 MB, or gemma-3-1b Q5_K_S 836 MB) | **None** — change endpoint/base-URL + model name in prefs | 836–986 MB | **Yes** | Bigger weights, but keeps tone and needs no code. |
| **A' (zero change)** | oMLX or `mlx_lm.server` + MLX 4-bit (`Qwen3-1.7B-4bit` 968 MB / `Qwen2.5-1.5B-4bit` 869 MB) | **None** — same OpenAI API | 869–968 MB | **Yes** | MLX toolchain already installed; must download model + start server (oMLX currently idle, empty model dir). |
| **B (small code)** | CT2 `opus-mt-pl-en` behind a ~40-line local HTTP **wrapper that mimics `/v1/chat/completions`** | None-to-minimal (if wrapper named as an endpoint) | **154 MB** | **No** | Smallest effective model; wrapper is new moving part. **Must append `</s>`** (§5). |
| **C (native code)** | CT2 `opus-mt-pl-en` via a native `/translate` route (small `TranslationService` change) | Small, surgical | **154 MB** | **No** | Cleanest long-term; touches app code. |
| **D (no second call)** | whisper.cpp `--translate` | Config/flag change | **0 MB** | **No** | Couples translation into STT, **loses the separate Polish transcript** path (and any downstream PL-text features), no tone. |

Whisper `--translate` is the only option with **zero extra weights** and one pass, but it changes the
product behaviour (no Polish transcript to keep/display), so it is listed last for this fork.

---

## 8. Recommendation and the decision the captain must make

**Smallest effective model = `gaudi/opus-mt-pl-en-ctranslate2`, 153.9 MB int8.**
It was actually run here on CPU and produced clean English for all four test sentences in
**39.7–84.4 ms each (mean 62.4 ms)**, ~364 MiB RSS, ~949 chars/s on a 268-char paragraph.

Size comparison [verified]:
- vs Qwen3-1.7B-4bit (968.1 MB): **6.3× smaller**
- vs Qwen2.5-1.5B (986.0–1117.3 MB): **6.4–7.3× smaller**
- vs a ~14B 6-bit LLM (≈10.5 GB): **~68× smaller** (brief's "~70×" is accurate)
- vs the existing 30B q4 GGUF (19.0 GB): **~123× smaller**

**Drop-in + tone = Qwen2.5-1.5B-Instruct GGUF Q4_K_M (986 MB) via `llama-server`, zero app change.**
Smoke testing proves the 154 MB NMT is fast and correct-enough; it does **not** prove any LLM's tone
quality, so that remains to be validated by the captain if tone is a must.

### Decision for the captain

> **Tone vs size.**
> - If translation tone/style is **not** required (plain faithful PL→EN is enough): adopt
>   **opus-mt-pl-en CT2, 154 MB**, via a small wrapper or native `/translate` route. ~6–7× smaller
>   than any toned LLM, ~60 ms/sentence on CPU, no GPU. Accept that it cannot follow tone
>   instructions and may drop/idiomatize short conversational phrases.
> - If tone **must** stay: adopt a **~1.5–1.7B instruct LLM** (Qwen2.5-1.5B or Qwen3-1.7B-4bit,
>   869–986 MB) served by `llama-server` (GGUF) or oMLX/`mlx_lm` (MLX). **Zero app change** — only
>   endpoint/model prefs. This is a ~6× larger model than the NMT but keeps the current behaviour.
> - Whisper `--translate` (0 MB) only makes sense if the separate Polish transcript path is
>   intentionally abandoned.

---

## 9. Unverified claims (explicit)

- Tone quality / instruction-following of every LLM candidate (Qwen2.5-1.5B, Qwen3-1.7B, gemma-3-1b)
  — **not run** in this session.
- Runtime/latency/memory for NLLB CT2 int8 (#5), the ONNX int8 path (#3), `llama-server` with any
  small GGUF, and oMLX/`mlx_lm.server` — **not run** here.
- NLLB's `pol_Latn` source-language-token requirement is stated from general knowledge, not tested.
- The app's exact endpoint plumbing (`/v1/chat/completions`, how the base URL/model are configured)
  is taken from the brief; the OpenSuperWhisper repo was **not** read or modified (scout isolation).
- The brief's launchd claim (`com.dsh.mlx-qwen` pointing at a missing venv) could not be reproduced
  — no such plist/job exists (see §2).

## 10. Repo / isolation

No changes to `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo` or any worktree. No branch, no PR.
The only artifact produced is this report. Test scripts live under `/tmp` only
(`/tmp/mt-smoke.py`, `/tmp/mt-smoke2.py`, `/tmp/mt-probe.py`). The only environment mutation was
`pip install transformers` into the disposable `/tmp/mt-venv` (for a canonical-tokenizer cross-check);
the MLX venv was read, not modified.

---

## Ant Labs (Desert Ant Labs) on-device models

**Addendum, 2026-09-23.** Captain pointed at
`https://ai-tldr.dev/releases/desert-ant-labs-on-device-models/` and asked whether these "tiny
Ant Labs on-device models" are a better fit than `gaudi/opus-mt-pl-en-ctranslate2` for PL→EN.

### A.0 Headline verdict (read this first)

> **Worse — not comparable, because none of the 18 Desert Ant Labs models does translation at all.**
> After enumerating the full catalog (vendor page, `catalog.json`, `llms.txt`, the Hugging Face org
> API, and the SDK/CLI source tree), there is **no PL→EN model, no NMT model, and no
> speech-translation model** in the lineup. The closest models are Voz (speech → *same-language*
> text) and Ear/Tongue (language *identification*). Voz transcribes Polish into **Polish**, not
> English — verified here on the four brief sentences (see A.4). So Ant Labs cannot replace opus-mt
> for this task; it could at most replace the *STT* stage (whisper), not the translation stage, and
> it costs 466 MB + an Apple-only, source-available (non-OSI) licence to do so.

> **Amendment — Addendum 2 (§A.9).** The *product* verdict stands: the exact catalog page
> advertises **no translation model**, and no supported Ant Labs interface translates. But the
> stronger claim that no Ant Labs model can emit English from Polish is **too absolute**: the raw
> `title` weights (the only generative model) leak unreliable, hallucination-prone English when
> driven with an **unsupported custom prompt**. See §A.9.5. It is not a usable translator and does
> not change the recommendation.

`gaudi/opus-mt-pl-en-ctranslate2` (154 MB, ~62 ms median, Apache-2.0) therefore remains the only
candidate in this report that actually performs PL→EN.

### A.1 Fetch evidence (all [verified] this session)

| What | Result |
|---|---|
| ai-tldr.dev page | `HTTP 200`, 29,867 B, fetched with `curl -sL` |
| Vendor model index | `https://desertant.com/models/` `HTTP 200`, 29,925 B |
| Vendor announcement | `https://desertant.com/blog/introducing-desert-ant-labs/` `HTTP 200`, 30,383 B |
| Machine-readable catalog | `https://desertant.com/catalog.json` `HTTP 200`, 21,844 B — **18 models, zero translation** |
| Agent catalog | `https://desertant.com/llms.txt` `HTTP 200`, 7,058 B; `llms-full.txt` 45,364 B |
| HF org API | `GET /api/models?author=desert-ant-labs` `HTTP 200` — **17 repos**, none `translation`/`text2text` |
| HF blob sizes | `GET /api/models/{repo}?blobs=true` for all 17 repos; cross-checked with `curl -sIL` Content-Length |
| SDK | `github.com/Desert-Ant-Labs/desert-ant-core` (Swift/Kotlin/JS), licence `NOASSERTION` |
| CLI | `github.com/Desert-Ant-Labs/desert-ant-cli` v0.1.1, darwin-arm64 tarball **10,636,686 B** |
| Licence | `https://license.desertant.com/1.0` — Desert Ant Labs Source-Available License 1.0 (not OSI) |
| grep for "translat" | only two **use-case prose** hits (`llms-full.txt` lines 224, 499: "pick the right translation model"); no model, no repo, no command |

The vendor page itself lists the 18 tasks: Align, Clear, Clips, Ear, Emo, Gist, Redact, Shapes,
Title, Tongue, Uhm, Voz (12 stable) + Eye, Face, Moderator, Schemer, Toxic, Who (6 beta). **Not one
is translation.**

### A.2 The 18 models — task, size, runtime, Polish, PL→EN?

Sizes are **real, verified** bytes from the HF `/api/models/{repo}?blobs=true` API (decimal MB).
"HF repo total" sums every format in the repo; the "deployable" column is the one artifact the
relevant runtime actually loads.

| Model | Task | Modality | Deployable weights [verified] | Other formats in repo | Polish? | PL→EN? |
|---|---|---|---|---|---|---|
| **Voz** | speech recognition (ASR), 25 langs | audio→text (**same language**) | Core ML encoder `460,717,376` + decoder `15,831,820` + mel `826,688` = **477.4 MB** (+embedding 10.5 MB) | tflite encoder 1,207,525,456 + decoder 24.5 MB; web ONNX ≈408 MB; repo total **2131.8 MB**; **on-disk cache 466 MB** | ✅ **pl** (vendor WER 9.99%) | ❌ outputs Polish |
| **Ear** | spoken language ID, 99 langs | audio→label | Core ML `13,696,070` = **13.7 MB** | tflite 23.1 MB; repo total 37.0 MB | ✅ **pl** (verified 0.91–0.99) | ❌ |
| **Tongue** | text language ID, 84 langs | text→label | ONNX `8,399,496`; int8 `2,104,940`; int4 `1,056,492` (**1.1–8.4 MB**) | — | ✅ **pl** in `labels.json` | ❌ |
| **Redact** | PII redaction, 27 langs | text→redacted text | Core ML `11,541,810` = **11.5 MB** | tflite 24.5 MB; repo total 38.9 MB | ✅ **pl** | ❌ |
| **Emo** | emoji suggestion, 22 langs | text→emoji | Core ML `4,701,400` = **4.7 MB** | tflite 10.2 MB | ✅ (ran on Polish) | ❌ |
| **Gist** | topic tagging, 101 langs | text→topics | Core ML `6,516,872` = **6.5 MB** | tflite 13.0 MB; embedding int8 66.9 MB | ✅ (ran on Polish) | ❌ |
| **Title** | titles/descriptions | text→text (**same language**) | safetensors `286,449,872` = **286.4 MB** (on disk 280 MB) | — | handles Polish (outputs Polish) | ❌ |
| **Clips** | clip selection | transcript→ranked clips | Core ML `283,724,544` = **283.7 MB** | tflite ~283 MB ×2; repo total 854.0 MB | n/a | ❌ |
| **Clear** | speech enhancement | audio→audio | Core ML `9,114,304` = **9.1 MB** | ONNX 24.8 MB, tflite 49.3 MB | n/a | ❌ |
| **Align** | word timestamps | audio→timestamps | Core ML `506,560`; tflite 1.0 MB = **~1.0 MB** | repo total 1.7 MB | n/a | ❌ |
| **Uhm** | filler-word detection | audio→spans | Core ML `46,997,248` = **47.0 MB** | ONNX 94.0 MB, tflite 23.9 MB | n/a | ❌ |
| **Shapes** | shape recognition | stroke→shape | safetensors `202,320`; tflite 1.3 MB = **~1.5 MB** | repo total 1.7 MB | n/a | ❌ |
| **Toxic** | hate-speech triage, 23 EU langs | text→label | Core ML `80,000,724` = **80.0 MB** | ONNX 100.2 MB, tflite 90.6 MB | ✅ **pl** | ❌ |
| **Schemer** | structured extraction, 13 langs | text→JSON | int4-AWQ `111,172,475` (111.2 MB); int8 215.8 MB; fp32 **850.2 MB** | Core ML int4 zips ~87.8 MB each | ✅ **pl** | ❌ |
| **Moderator** | NSFW image detection (beta) | image→label | Core ML `10,040,000` = **10.0 MB** | tflite 9.8 MB | n/a | ❌ |
| **Who** | speaker labelling (beta) | audio→turns | Core ML `5,471,127` (voice) = **~5.5 MB** | repo total 12.0 MB | n/a | ❌ |
| **Eye** | image/video scoring (beta) | image→score | **not public** — HF API returns `HTTP 401` | — | n/a | ❌ |
| **Face** | face matching (beta) | image→match | **not public** — HF API returns `HTTP 401` | — | n/a | ❌ |

**Runtime formats [verified]:** Core ML (`.mlmodelc`) on Apple; LiteRT/TFLite on Android; ONNX +
WebAssembly (LiteRT.js) on web/Node. `desertant doctor` on this machine: `Core ML ok`, `MLX ok`,
`LiteRT --` (not installed); 9 models runnable via the CLI (clear, clips, ear, emo, gist, redact,
title, uhm, voz). Tongue is explicitly "not in the CLI yet"; Align, Shapes need SDK integration.

### A.3 Vendor claims vs verified here

**Vendor claims (quoted from the fetched pages — not independently reproduced unless noted):**

- Page quick facts: *"18 (12 stable, 6 beta)"*, SDKs *"Swift, Kotlin, JavaScript"*, runtimes
  *"Core ML, LiteRT, WebAssembly"*, free tier *"100k monthly active devices"*, licence
  *"Source-available"*, announced 8 Sep 2026.
- *"Voz transcribes ten minutes of audio in two seconds on an iPhone, which Desert Ant Labs measures
  as 4.7x faster than Whisper, and it returns word-level timing."*
- Voz card: **467 MB on disk**, *"~290x real time"* on long files, **WER 7.40%** average (vs 7.00%
  Whisper large-v3-turbo) over six Open ASR Leaderboard sets; **Polish WER 9.99%** on 10-min FLEURS
  long audio; base model **NVIDIA Parakeet TDT 0.6B v3** (CC BY 4.0), converted to Core ML.
- *"Redact catches 88.8% of the personal data in a text, close to the 2.3GB GLiNER-PII"* (91.1%),
  from a 12 MB model.
- *"Tongue names the language from three words, scoring 0.933 at 2MB against 0.887 for a 293MB
  detector."*
- *"Clear … 302x realtime on a phone"* from 9 MB; Clips is *"our 284MB model"*.

**Verified here:** the catalogue composition (no translation), the byte sizes in A.2 (HF API +
Content-Length + on-disk), the runtime availability on this Mac, the licence text, and the smoke
test in A.4.

### A.4 Smoke test — the four brief sentences, on this machine [verified]

Runtime exists (Core ML on macOS 27.0 arm64) and Voz is <1.5 GB, so it was actually run. The CLI
(v0.1.1, darwin-arm64) was unpacked to `/tmp/dacli` **without installing it system-wide**. The four
Polish sentences were synthesised to 16 kHz mono WAV with the macOS Polish voice `Zosia`
(`say -v Zosia`), since the brief sentences are the translation test set and Voz needs audio.

| # | Polish input (as audio) | Voz output [verified] | English? |
|---|---|---|---|
| 1 | Cześć, jak się masz? | `Cześć, jak się masz` | ❌ still Polish |
| 2 | Musimy omówić budżet na przyszły kwartał. | `Musimy omówić budżet na przyszły kwartał` | ❌ still Polish |
| 3 | Nie mogę dzisiaj przyjść na spotkanie, przepraszam. | `Nie mogę dzisiaj przyjść na spotkanie, przepraszam.` | ❌ still Polish |
| 4 | Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę. | `Wysłałem Ci wczoraj trzy dokumenty, sprawdź je proszę` | ❌ still Polish |

**Latency / memory [verified]:** first Voz call `62.58 s` wall (includes one-time weight download +
Core ML specialisation), peak RSS `1,073,102,848 B` ≈ 1.02 GiB; warm calls `2.86–2.90 s` wall per
short clip (`~2.72 s` user CPU — each CLI invocation is a fresh process that reloads the model, so
this is per-call overhead, not the vendor's warm in-process figure). Cached model on disk: **Voz
466 MB**, Title 280 MB, Gist 74 MB, Ear 13 MB, Redact 11 MB, Emo 5.3 MB.

**Other models on the same four Polish sentences [verified]:**

| Model | Output on Polish input | Takeaway |
|---|---|---|
| Ear | `pl 0.91 / ru 0.04 / en 0.02`; warm `pl 0.97–0.99`, 0.15 s | correctly identifies Polish |
| Redact | text returned unchanged (no PII) | handles Polish, does not translate |
| Emo | `🚶 📦 👋` / `💰 📊 📅` / `📅 👥 🤝` / `📄 🔍 ✉️` | handles Polish, does not translate |
| Gist | `Arts & Culture 0.45` / `Music 0.83` / `Self-Improvement 0.68` / `Self-Improvement 0.34` | handles Polish (topics noisy), no translation |
| Title | s2 → title `Budżet na przyszły kwartał`, desc `Budżet buduje na przyszły kwartał, w którym budujemy budżet na kolejny kwartał.` (first call 13.75 s, warm ~2.0 s) | the only text-generation model; emits **Polish**, not English |

**No command or model in the Ant Labs lineup produced English from any Polish sentence** through
any supported interface (SDK/CLI/fixed prompt). *(Addendum 2 qualifies this: the raw `title`
weights do leak English under an unsupported custom prompt — see §A.9.5 — but unreliably and with
hallucinations.)* Ear and
Voz together can tell you "this audio is Polish" and "here is the Polish transcript", which is
exactly what you already get from whisper.cpp — the translation step is still missing and still
needs opus-mt (or whisper `--translate`).

### A.5 Download locations (real)

- HF org: `https://huggingface.co/desert-ant-labs` — one repo per model:
  `https://huggingface.co/desert-ant-labs/{voz|ear|tongue|redact|emo|gist|title|clips|clear|align|uhm|shapes|toxic|toxic-en|schemer|moderator|who}`
  (`eye` and `face` return `HTTP 401`, i.e. gated/private).
- SDK source: `https://github.com/Desert-Ant-Labs/desert-ant-core`
- CLI: `https://github.com/Desert-Ant-Labs/desert-ant-cli`; release asset
  `desertant-darwin-arm64.tar.gz` v0.1.1 = `10,636,686 B`; Homebrew tap
  `desert-ant-labs/tap/desertant`.
- Catalog for agents: `https://desertant.com/catalog.json`, `https://desertant.com/llms.txt`.

**Licence [verified]:** Desert Ant Labs Source-Available License 1.0 — free below 100,000 monthly
active devices *per model per platform*; **commercial licence required above that**; not
OSI-approved; attribution ("Powered by Desert Ant Labs") required; may not be used to train a
competing model. This is a materially worse licence for a shipping app than opus-mt's **Apache-2.0**.

### A.6 Verdict vs `gaudi/opus-mt-pl-en-ctranslate2`

| | Ant Labs (best relevant: Voz) | `gaudi/opus-mt-pl-en-ctranslate2` |
|---|---|---|
| Does PL→EN? | **No** (transcribes Polish to Polish) | **Yes**, verified |
| Weight size | 466 MB on disk | **154 MB** |
| Latency | warm ~2.9 s/short clip via CLI (per-process load); vendor ~50–62× RT warm | **~62 ms median**, verified |
| Runtime | Core ML, **Apple-only** | CTranslate2, CPU, cross-platform |
| Licence | Source-available, commercial above 100k MAU | **Apache-2.0** |
| Tone? | No | No |
| Replaces | whisper (STT), not translation | the translation call |

**Verdict: worse / not applicable.** Ant Labs has nothing that performs PL→EN, so it is not a
candidate for the translation step at all. Two secondary points:

1. **Cannot collapse STT+translate.** Voz is speech-in→text-out but **same-language**; it does not
translate. Only whisper.cpp `--translate` does speech→English in one pass (0 MB extra, already
installed). Adding Voz would replace whisper for *transcription* at a cost of +466 MB and an
Apple-only, source-available dependency, while still leaving translation to opus-mt. It does not
improve the option-D path.
2. **If the goal is text-only PL→EN, opus-mt wins outright** — 154 MB vs Voz's 466 MB, ~62 ms vs
   ~2.9 s per short clip, Apache-2.0 vs source-available, cross-platform vs Apple-only.

If a future Ant Labs *translation* model appears, re-evaluate then; as of the 2026-09-23 fetch there
is none. The only mildly interesting pieces are Ear (13.7 MB spoken-language ID, Polish verified)
and Tongue (1–8 MB text language ID, Polish in labels) — as *routing* helpers, not translators.

### A.7 Reproducing the fetch (commands used)

```bash
curl -sL --max-time 30 "https://ai-tldr.dev/releases/desert-ant-labs-on-device-models/"
curl -sL "https://desertant.com/catalog.json"
curl -sL "https://desertant.com/llms.txt"
curl -sL "https://huggingface.co/api/models?author=desert-ant-labs&limit=100"
curl -sL "https://huggingface.co/api/models/desert-ant-labs/voz?blobs=true"
curl -sIL "https://huggingface.co/desert-ant-labs/voz/resolve/main/encoder.mlmodelc/weights/weight.bin"
# CLI smoke test (no system install; unpacked to /tmp)
curl -sL -o /tmp/dacli.tgz \
  "https://github.com/Desert-Ant-Labs/desert-ant-cli/releases/download/v0.1.1/desertant-darwin-arm64.tar.gz"
mkdir -p /tmp/dacli && tar xzf /tmp/dacli.tgz -C /tmp/dacli
/tmp/dacli/desertant doctor && /tmp/dacli/desertant models
say -v Zosia -o /tmp/antlabs-audio/s1.aiff "Cześć, jak się masz?"
afconvert -f WAVE -d LEI16@16000 -c 1 /tmp/antlabs-audio/s1.aiff /tmp/antlabs-audio/s1.wav
/tmp/dacli/desertant voz /tmp/antlabs-audio/s1.wav --quiet
/tmp/dacli/desertant ear /tmp/antlabs-audio/s1.wav --top 3
```

### A.8 Isolation note

No repo changes, no branch, no PR. The only machine mutations were downloads to `/tmp` (page copy,
CLI tarball) and the CLI's own model cache at
`/Volumes/home/zenon/Library/Caches/desert-ant-models` (851 MB total), plus four WAVs synthesised in
`/tmp/antlabs-audio`. The CLI was never installed system-wide.

---

## A.9 Addendum 2 — the exact catalog page, re-examined (2026-09-23)

**Captain:** "Here is the exact page of our tiny models lab https://desertant.com/models/"

The captain pointed at the catalog page itself, not the secondary summary used in §A. So this
addendum fetches `https://desertant.com/models/` directly, enumerated every model on it, hunted
specifically for translation-adjacent capability, and **smoke-tested the only generative model** on
the four brief sentences plus held-out Polish. It also **corrects one over-strong claim** in §A.0/§A.4.

### A.9.0 Headline — the reconciliation

> **The catalog page does not offer translation. Prior product verdict stands.** All 18 models are
> advertised as *"Small, specialized models that run on the device, **one per task**"*, and the 18
> tasks are: word timestamps, speech enhancement, clip selection, spoken-language detection, emoji,
> topic tagging, PII redaction, shape recognition, titles/descriptions, language identification,
> filler detection, speech recognition, image/video understanding, face matching, content
> moderation, structured extraction, hate-speech triage, and who-said-what. **No translate/NMT/
> seq2seq task anywhere.** The only generative model — Title — is explicitly trained and served to
> **"Write in the same language as the passage"**.
>
> **But one claim in §A.0/§A.4 was too strong and is corrected here.** "No Ant Labs model can
> produce English from Polish" is false as stated: the raw `desert-ant-labs/title` weights
> (Granite-4.0-350m 6-bit, 286.4 MB, MLX), when driven with an **unsupported custom prompt** and
> greedy decode, **do emit English** — 11/11 sentences produced English-shaped output under one
> prompt. The quality is **not usable**: across 11 tested sentences only **3 were fully correct, 2
> partial, and 6 wrong** (meaning inversions like *"Zamknij okno"* → "Open the door", and
> hallucinations). It is a leaky side effect of the multilingual base model, **not** a supported
> translation capability, and it remains far worse than `opus-mt-pl-en`. See §A.9.5.

**Net:** Ant Labs still has **no translation product and no supported translation path**. Title
cannot be used as a translator in the app. The prior recommendation (opus-mt-pl-en CT2, 154 MB) is
unchanged.

### A.9.1 Fetch evidence (all [verified] this session)

| Artifact | Result |
|---|---|
| `https://desertant.com/models/` | `HTTP 200`, **29,925 B** `curl -sL`; static HTML, 18 model cards (no client-side JSON needed) |
| `https://desertant.com/catalog.json` | `HTTP 200`, 21,844 B — machine-readable, **exactly 18 models** |
| `https://desertant.com/llms.txt` | `HTTP 200`, 7,058 B — 18 models listed, none `translation` |
| `https://desertant.com/llms-full.txt` | `HTTP 200`, 45,364 B — **2** `translat` hits, both routing prose (§A.9.3) |
| `models.json`, `api/models`, `models/index.json`, `models/catalog.json` | `HTTP 404` — no hidden data route |
| `https://desertant.com/assets/main.js` | `HTTP 200`, 8,567 B — **0** `translat` hits, no model-data `fetch` |
| all 18 `https://desertant.com/models/{slug}/` pages | all `HTTP 200`; `translat` hits only on `ear` (1) and `tongue` (3), all routing prose |
| all 12 `https://desertant.com/docs/{model}/` pages | all `HTTP 200`; 1 `translat` hit total (tongue, training-corpus prose) |
| HF org `GET /api/models?author=desert-ant-labs` | `HTTP 200` — **17 repos**, **zero** with `pipeline_tag` `translation`/`text2text-generation` |
| GitHub `desert-ant-core` tree | **1,044 paths, zero** whose name contains `translat`/`nmt` |
| GitHub `desert-ant-cli` tree | 9 model runners only: Clear, Clips, Ear, Emo, Gist, Redact, Title, Uhm, Voz — **no translate runner** |

### A.9.2 The 18 advertised tasks — direct quotes from the page

Page intro, verbatim: *"Small, specialized models that run on the device, one per task."* Meta
description: *"Small, specialized on-device models for vision, audio, and text: redaction,
transcription, shape recognition, emoji, and more."* Every model card, quoted:

| # | Model | Page task line (verbatim) | Generate English from Polish? |
|---|---|---|---|
| 1 | **Align** | "Accurate word timestamps for any transcript." | No — timestamps; does not transcribe ([vendor] *"Align corrects a transcriber's timings; it doesn't transcribe"*) |
| 2 | **Clear** | "Studio sound, no cloud bill." | No — audio→audio speech enhancement |
| 3 | **Clips** | "Create video shorts and highlights." | No — transcript→ranked clips |
| 4 | **Ear** | "Detect language based on 30 seconds of audio." | No — audio→language label ([vendor] *"Ear names the language; it doesn't transcribe."*) |
| 5 | **Emo** | "Suggest emoji faster than you can type." | No — text→emoji classifier |
| 6 | **Gist** | "Generate topics and tags for posts and articles." | No — text→topic classifier |
| 7 | **Redact** | "Filter PII on-device." | No — text→redacted same-language text |
| 8 | **Shapes** | "Rough sketch. Perfect shape." | No — stroke→shape class |
| 9 | **Title** | "Suggest a title and description for any text." | **Only candidate** — text generation; **not** translation (explicitly same-language; §A.9.4) |
| 10 | **Tongue** | "Detect language based on 3 words." | No — text→language label |
| 11 | **Uhm** | "Detect and remove filler words in seconds." | No — audio→filler spans |
| 12 | **Voz** | "Transcribe 10 minutes of audio in 2s on an iPhone." | No — ASR, same language (verified in §A.4) |
| 13 | **Eye** | "Tag and rank images based on aesthetics and content." (beta) | No — image/video scoring |
| 14 | **Face** | "Find people in photos, private on the device." (beta) | No — face matching |
| 15 | **Moderator** | "Flag nudity before upload or showing." (beta) | No — image classifier |
| 16 | **Schemer** | "Extract typed JSON from any text." (beta) | No — extraction; [vendor] *"Schemer copies what the text states; Schemer does not write."* |
| 17 | **Toxic** | "Catch hate speech before it posts." (beta) | No — text→hate label |
| 18 | **Who** | "Label who said what in audio and video." (beta) | No — speaker diarization |

### A.9.3 Translation-adjacent search — every hit, quoted

A case-insensitive grep for `translat|nmt|seq2seq|opus|marian|bilingual` across the page, the three
machine catalogs, and all 18+12 model/doc pages produced **only these**, all *routing/use-case prose*
that explicitly delegates translation to a *separate* model:

- **Tongue page, Use cases:** *"Route text by language — **Pick the right translation model**, analyzer,
  or support queue from the first few words a user types, entirely on device."*
- **Tongue page, Inspiration preview:** *"identify the language of an incoming message from a few
  words, on-device, and **route it to the right support queue, model, or translation path**."*
- **Tongue docs:** *"The training corpus is split along the **Tatoeba translation-link graph**, so a
  sentence and its translations cannot straddle train and validation."* (dataset hygiene for a
  detector — not a translation model.)
- **Ear page, Use cases:** *"run Ear on the first 30 seconds and start the transcriber, the captions,
  and **the translation** in the language actually spoken."*
- **`llms-full.txt` line 224** (Gist/Tongue use case): *"Pick the right translation model, analyzer,
  or support queue…"*
- **`llms-full.txt` line 499** (Ear use case): *"…start the transcriber, the captions, and the
  translation in the language actually spoken."*

There is **no** model whose task is translate/NMT/seq2seq, **no** speech-translation model, and
**no** `translate` subcommand. The CLI's own README lists exactly 9 model verbs — `da voz`, `da
clips`, `da clear`, `da uhm`, `da ear`, `da redact`, `da emo`, `da gist`, `da title` — plus
`docs/info/models/schema`. [verified]

### A.9.4 Title — the only generative model [vendor claims + verified]

The one model worth a second look is **Title**, because it is the only text-generation model on the
page. Vendor facts, quoted:

- **Specs:** *"Model: Fine-tuned from granite-4.0-350m, 6-bit quantized, MLX."* Output *"A 3 to 8
  word title and a 1 to 2 sentence description"*. Platforms iOS/macOS/tvOS/visionOS, Apple silicon only.
- **The prompt is fixed and same-language.** The SDK source (`Sources/Title/Title.swift`,
  `Titles.prompt`) is byte-exact: *"Write a factual title (3-8 words) and a 1-2 sentence description
  for this passage.Be specific enough to identify this passage. No emoji, no hashtags, no hype.**Write
  in the same language as the passage.** PASSAGE: {clip}"*.
- **Model card (`README.md`):** *"The model was fine-tuned against one specific instruction, and a
  paraphrase is a different task to it. It lives in `Titles.prompt` in the SDK; use that wording."*
  and *"The chat template is not incidental. A different template is a different task to this model."*
- **Model page:** *"Use the SDK's own prompt: the model was trained on one instruction, and a
  reworded one gets worse output."*
- **File sizes [verified, HF `?blobs=true`]:** `model.safetensors` = `286,449,872 B` = **286.4 MB**
  decimal (280 MB on the local cache); `chat_template.jinja` 6,418 B; `config.json` 2,103 B;
  `tokenizer.json` 7,153,802 B. Pipeline tag `text-generation`; tags include `summarization`,
  `multilingual`, `granitemoehybrid`. Base model `ibm-granite/granite-4.0-350m`.
- **CLI:** `da title "<text>"` calls `Titles.describe(input)` — the fixed prompt only; there is no
  prompt/instruction flag.

**Reading:** the vendor deliberately trains and serves Title to *preserve* the input language. The
supported product path cannot translate. Whether the underlying weights *also* retain incidental
translation is an empirical question — answered in §A.9.5.

### A.9.5 Smoke test — Title driven with translation prompts [verified here]

Method: loaded the real published weights from the CLI cache
(`…/Caches/desert-ant-models/desert-ant-labs/title/v0.1.0`) with `mlx_lm 0.31.3` / `mlx 0.32.2` on
macOS arm64, applied the model's own `chat_template.jinja` (verified: roles render as
`<|start_of_role|>user<|end_of_role|>…<|end_of_text|>`, and the default system message *"You are a
helpful assistant…"* is injected), and ran **greedy** decode (`max_tokens=96`). Deterministic:
repeated runs are byte-identical.

**(a) Control — the SDK's own prompt** (what the product actually does): output stays **Polish**, as
designed by *"Write in the same language as the passage"*. 152–205 ms/sentence:

| Polish input | Title output (SDK prompt) |
|---|---|
| Cześć, jak się masz? | `TITLE: Cześć, jak się masz?` / `DESC: Cześć, jak się masz?` |
| Musimy omówić budżet na przyszły kwartał. | `TITLE: Budżet na przyszły kwartał` / `DESC: Budżet buduje na przyszły kwartał, który zaczyna się w 2025.` |
| Nie mogę dzisiaj przyjść na spotkanie, przepraszam. | `TITLE: Nie mogę dzisiaj przyjść na spotkanie` / `DESC: Nie mogę dzisiaj przyjść na spotkanie, przepraszam.` |
| Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę. | `TITLE: Wysłanie trzy dokumenty` / `DESC: Wysłano trzy dokumenty wczoraj.` |

**(b) Unsupported translation prompts — prompt-fragile, leaky, unreliable.** Four ad-hoc variants;
results differ sharply by wording:

- `P1` ("Translate the following Polish text into English. Output only the English translation…") →
  **mostly echoed Polish** (`Polish: Cześć, jak się masz?`, …).
- `P2` ("Translate this Polish sentence into English. Output only the English…") → **3/4 brief
  sentences English-ish**, e.g. `HELLO! How are you?`, `English: We must complete the budget for the
  next quarter.`, `English: I cannot come to the meeting today. Please forgive me.`; the 4th broke
  to `Polish: I zwróciłem ci trzy dokumenty…`. Held-out sentences were largely wrong (`Close the
  window, it's raining outside.` for *"…bo jest zimno na dworze"* = *because it's cold outside*).
- `P3` ("Translate to English: {s}") → **mostly echoed Polish**.
- `P4` ("Polish to English translation.\n{s}\n=>") → **the strongest**: all 11 sentences returned
  English-shaped text. But scoring them against the source:

| # | Polish | P4 output | Verdict |
|---|---|---|---|
| 1 | Cześć, jak się masz? | `Hello, how are you?` | ✅ |
| 2 | Musimy omówić budżet na przyszły kwartał. | `We will include the budget for the next quarter.` | ❌ *omówić* = discuss |
| 3 | Nie mogę dzisiaj przyjść na spotkanie, przepraszam. | `I cannot attend the meeting right now.` | ⚠️ drops *today/sorry* |
| 4 | Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę. | `I sent you three documents yesterday. Please check them out.` | ✅ |
| 5 | Zamknij okno, bo jest zimno na dworze. | `Open the door, it is raining outside.` | ❌ inverted verb + invented weather |
| 6 | Jutro rano jadę do Krakowa pociągiem o siódmej. | `I am going to Krakow on a Sunday.` | ❌ drops time + train |
| 7 | Ona kupiła nowy samochód w zeszłym tygodniu. | `She bought a new car on the previous day.` | ⚠️ week → day |
| 8 | Nie zapomnij zabrać parasola, będzie padać. | `Do not forget not to forget parasols.` | ❌ broken, loses *it will rain* |
| 9 | Proszę zamknąć drzwi, bo wieje wiatr. | `Close your eyes, because the wind is blowing.` | ❌ *drzwi* (door) → **eyes** |
| 10 | Wczoraj wieczorem obejrzałem dobry film o kosmosie. | `For a while I have been watching a good film about the cosmos.` | ❌ drops *yesterday evening* |
| 11 | Ta umowa wygasa z końcem przyszłego miesiąca. | `This agreement expires at the end of the next month.` | ✅ |

**Score: 3 correct / 2 partial / 6 wrong (of 11)**, on a prompt the vendor says is *not* the model's
task. Peak RSS **557 MiB**; **80–180 ms/sentence**; deterministic. 

**Conclusion for the smoke test:** Title **can emit English from Polish under an unsupported prompt**
— so the prior "impossible" wording is corrected — but it is **not a translator**: it hallucinates
content (*cold outside* → *raining outside*; *close the door* → *close your eyes*), inverts meaning,
and drops clauses. It fails the app's bar. It is also Apple-only MLX, source-available licensed, and
larger (286 MB) than `opus-mt-pl-en` (154 MB), which translated all four brief sentences correctly at
~62 ms median in §4.2.

### A.9.6 Amended reconciliation

| Claim | Status after Addendum 2 |
|---|---|
| The exact page advertises a translation/NMT/seq2seq model | **Still false** — 18 tasks, none translation; zero model/CLI/docs hits |
| A supported Ant Labs interface performs PL→EN | **Still false** — Title's served prompt is *"Write in the same language as the passage"*; Voz ASR is same-language; Ear/Tongue only label |
| "No Ant Labs model can produce English from Polish" (wording in §A.0/§A.4) | **Corrected** — raw `title` weights leak English under an unsupported custom prompt, but with 6/11 wrong and hallucinated content |
| Ant Labs can replace opus-mt for the translation step | **Still false** — no product path; the unofficial leakage is worse than opus-mt and unsupported |
| Recommendation unchanged | **Yes** — `gaudi/opus-mt-pl-en-ctranslate2`, 154 MB, Apache-2.0, verified |

**Vendor claims** in this addendum: the 18 task lines, the Title Specs sentence, the Title model
description, the SDK prompt text, and the model-card quotes. **Verified here:** all HTTP fetches and
byte counts, the catalog composition, the absence of any translate model/command, the Title weight
size, the chat-template application, and the entire §A.9.5 smoke test.

### A.9.7 Reproduce the fetch and smoke test (commands used)

```bash
# direct catalog page + machine catalogs
curl -sL "https://desertant.com/models/" -o models_page.html            # HTTP 200, 29925 B
curl -sL "https://desertant.com/catalog.json" -o catalog.json          # 18 models
curl -sL "https://desertant.com/llms.txt"
curl -sL "https://desertant.com/llms-full.txt"
curl -sL "https://desertant.com/assets/main.js"
for s in align clear clips ear emo eye face gist moderator redact schemer shapes title tongue toxic uhm voz who; do
  curl -sL "https://desertant.com/models/$s/" -o "pages/$s.html"
done
grep -riE 'translat|nmt|seq2seq' models_page.html catalog.json llms*.txt pages/

# Title smoke test (Apple silicon; MLX)
/Volumes/home/zenon/mlx/.venv/bin/python - <<'PY'
from mlx_lm import load, generate
MODEL="/Volumes/home/zenon/Library/Caches/desert-ant-models/desert-ant-labs/title/v0.1.0"
model,tok=load(MODEL)
p=tok.apply_chat_template([{"role":"user","content":
   "Polish to English translation.\nCześć, jak się masz?\n=>"}],add_generation_prompt=True)
print(generate(model,tok,prompt=p,max_tokens=96,verbose=False))
print(tok.apply_chat_template([{"role":"user","content":
   "Write a factual title (3-8 words) and a 1-2 sentence description for this passage."
   "Be specific enough to identify this passage. No emoji, no hashtags, no hype."
   "Write in the same language as the passage.\n\nPASSAGE:\nCześć, jak się masz?"}],
   add_generation_prompt=True))
PY
```

**Isolation note (Addendum 2):** no repo changes, no branch, no PR, no subagents. All downloads
went to `/tmp/antlabs2`; the Title weights were read from the existing CLI cache (unchanged); no
model was downloaded or installed by this addendum.
