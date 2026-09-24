# Task fm-20260923-02 — OpenSuperWhisper — scout

## Captain's intent

"Check if smaller model for translation is feasible. I don't need general intelligence, I need only
translate feature. Basically search HuggingFace and look for something small yet effective."

Context: the fork currently sends the Polish transcript to a general LLM endpoint for PL→EN
translation + tone. The captain wants to know whether a much smaller, translate-only model is
feasible, and which one is small yet effective. This is a read-only investigation: deliverable is a
self-contained report, NOT a branch or PR.

## Firstmate spec

Produce `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/fleet/data/fm-20260923-02/report.md` containing:

1. **Environment reality** (verified by the first mate):
   - The plan's "local MLX Qwen" is NOT set up: `/Volumes/home/zenon/mlx/.venv` does not exist, and
     `~/.cache/huggingface/hub` holds no Qwen3-14B (only a 28M cache). The launchd job
     `com.dsh.mlx-qwen` points at the missing venv.
   - A separate GUI app `oMLX` (MLX server) is installed and configured on `127.0.0.1:1991` with an
     empty model dir `~/.omlx/models`.
   - `llama.cpp` (`llama-server`, `llama-cli`) is installed; an existing GGUF lives at
     `/Volumes/home/zenon/models/Qwen3-30B-A3B-Instruct-2507-q4_k_m.gguf`.
   - `whisper-cli` supports `--translate` (any speech language → English) natively.
   - Python 3.14.7 only; CTranslate2 4.8.2 has a cp314 macOS arm64 wheel (installable).

2. **Candidate table** with measured/queried weight sizes and the translating runtime:
   - `Helsinki-NLP/opus-mt-pl-en` (Marian, dedicated pl→en): 309 MB fp32; CT2 build
     `gaudi/opus-mt-pl-en-ctranslate2` = 154 MB; Xenova ONNX int8 ≈ 110 MB (encoder 52 + merged
     decoder 59). No tone.
   - `facebook/nllb-200-distilled-600M`: 2.46 GB fp32; CT2 int8 `JustFrederik/nllb-200-distilled-600M-ct2-int8`
     = 623 MB. No tone.
   - `Qwen2.5-1.5B-Instruct` GGUF (Q5_K_S ≈ 1.1 GB, Q4 ≈ 1.0 GB) via `llama-server` (OpenAI API).
     Translate + tone.
   - `Qwen3-1.7B-4bit` MLX ≈ 968 MB via oMLX/mlx_lm. Translate + tone.
   - `gemma-3-1b-it` GGUF Q5 ≈ 836 MB via `llama-server`. Translate + tone.
   - Whisper `--translate`: 0 MB extra, one pass, no tone.
   State size, runtime, tone capability, and integration cost for each.

3. **Empirical smoke test of the leading candidate.** The first mate already prepared it:
   - venv `/tmp/mt-venv` has `ctranslate2==4.8.2` + `sentencepiece` + `huggingface_hub`.
   - model already downloaded to `/tmp/opus-pl-en` (`model.bin` 154 MB, `source.spm`, `target.spm`,
     `shared_vocabulary.json`).
   Write a short script using `ctranslate2.Translator("/tmp/opus-pl-en", device="cpu",
   compute_type="int8")` and `sentencepiece` to translate at least these into English:
   `"Cześć, jak się masz?"`, `"Musimy omówić budżet na przyszły kwartał."`,
   `"Nie mogę dzisiaj przyjść na spotkanie, przepraszam."`,
   `"Wysłałem ci wczoraj trzy dokumenty, sprawdź je proszę."`
   Record: exact outputs, wall-clock latency per sentence (and total), whether the model needs a
   language prefix token, and peak RSS if easy. Warm it up before timing. If int8 fails, try float32
   and say so.

4. **Quality caveat.** Note that a dedicated NMT (opus-mt / NLLB) generally beats a same-size general
   LLM for translation, but cannot do tone. If tone must stay, the smallest drop-in options are the
   1.5–1.7B LLMs. That is the core tradeoff to present.

5. **Integration options** (ranked by app change required), given the app posts to an
   OpenAI-compatible `/v1/chat/completions` endpoint:
   - llama-server + a small GGUF: zero app change (change endpoint/model prefs only).
   - oMLX/mlx_lm + a 1.7B MLX model: zero app change.
   - CT2 opus-mt behind a ~40-line local HTTP wrapper that mimics `/v1/chat/completions` (or a native
     `/translate` route requiring a small TranslationService change): smallest model, more setup.
   - whisper.cpp `--translate`: no second call, but couples translation into STT and loses the
     separate Polish transcript path.

6. **Recommendation** with numbers: smallest effective = opus-mt-pl-en (~154 MB, ~70x smaller than a
   14B-6bit LLM, ~6x smaller than Qwen3-1.7B-4bit); drop-in + tone = Qwen2.5-1.5B-Instruct Q5 GGUF
   (~1.1 GB). State the decision the captain must make (tone vs size).

Keep the report evidence-based: every size from the HF API, every timing from the smoke test. Mark
anything unverified as unverified. Do not modify the OpenSuperWhisper repo; no branch, no PR.

## Worktree isolation assertion

This is a scout task with NO repository changes. Do not touch `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo`
or the ship worktree. The only artifact is the report under the firstmate home.

## Delegation guard

You are a crew member. Do not spawn subagents.

## Definition of done (scout)

- `data/fm-20260923-02/report.md` exists and is self-contained (question, method, evidence, numbers,
  recommendation, decision to make).
- The smoke test was actually run and its real outputs and timings are in the report.
- No repo changes, no PR.
