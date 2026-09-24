# Scout report — language awareness + tone switch for OpenSuperWhisper dictation

Task: `fm-20260923-04` (read-only scout). Author: crew `fm-20260923-04`.
Deliverable: this file. **No branch, no commit, no file inside either checkout was modified.**

Captain's intent (verbatim):
> "The app should also understand if I'm using Polish or English, because I'm sometimes, right now,
> speaking English and I don't need always a translate feature. I also want to sometimes use Polish
> without translate, so they need to be a toggle for translation enabled."

Added mid-task (verbatim):
> "Ton adjustment should also have a toggle to be enabled and disabled by a user."

## 0. Verdict up front

1. **The language signal is free to obtain on the default engine, but it is not free to compute.**
   With the multilingual whisper model, the fork can report the language of one utterance by reading
   `whisper_full_lang_id_from_state` after the `whisper_full` call the dictation path already makes —
   zero extra calls, zero extra model — but only if the app runs the engine in `auto` mode, and
   `auto` mode costs **+861…+1247 ms (median ≈ +930 ms)** per utterance versus a fixed language
   (measured, large-v3-turbo, M4). Today the value *is* computed by whisper.cpp in that mode and is
   then dropped, because `Settings.whisperLanguage` defaults to `"en"` (`AppPreferences.swift:65`),
   which makes whisper skip detection entirely.
2. **Recommended gate:** engine-reported language when available (whisper + multilingual model) →
   transcript text heuristic (fallback, e.g. FluidAudio) → for `unknown` only, let a single
   translate-or-passthrough model call decide. No separate classification call by default.
3. **Recommended policy:** English + translation on ⇒ **raw passthrough, zero model call**
   (measured: every model call mutates English: `"Do it tomorrow."` → `"I'll do it tomorrow."`).
   Polish + translation on ⇒ translate (+ tone if the tone switch is on). Translation off ⇒ no
   transform, except English with the tone switch on.
4. **New preference needed (tone switch): `toneEnabled`, default `false`** — default `true` would
   silently start rewriting dictation for installs that have translation off today.
5. Two independent things are conflated in the captain's ask and both are needed:
   **(a)** the STT engine must be told/deduce the spoken language (transcription quality: with
   `whisperLanguage = "en"` Polish is transcribed as mangled English, measured), and
   **(b)** the transform gate must know the language to avoid translating English.
   The captain's live config currently fails both (fixed `en` + English-only model — see §1.1).

---

## 1. Where the language signal can come from, per STT engine

### 1.1 Current configuration (evidence)

| Fact | Evidence |
|---|---|
| Default engine is whisper | `AppPreferences.swift:38-39` (`selectedEngine` default `"whisper"`), live `defaults read ru.starmel.OpenSuperWhisper` → `selectedEngine = whisper` |
| Default language setting is a **fixed** `"en"` | `AppPreferences.swift:65-66` (`whisperLanguage` default `"en"`); live prefs → `whisperLanguage = en` |
| Live model is **English-only** | live prefs → `selectedWhisperModelPath = ".../OpenSuperWhisper/ggml-tiny.en.bin"`; `WhisperModelManager.swift:90-110` copies `ggml-tiny.en.bin` as the default model |
| Language flows into params as fixed, detection off | `WhisperEngine.swift:349-351`: `let isAutoDetect = settings.selectedLanguage == "auto"; params.language = isAutoDetect ? nil : settings.selectedLanguage; params.detectLanguage = false` |
| Settings → prefs, no engine reload needed | `Settings.swift:80-85` (`selectedLanguage` didSet writes the pref), `Settings.swift:699-701` (`Settings()` re-reads prefs per transcription), `OpenSuperWhisperApp.swift:383-423` (menu bar picker writes the same pref); nothing reloads the engine on language change (only `OpenSuperWhisperApp.swift:270-273` re-checks the menu) |
| Dictation path only gets text | `IndicatorWindow.swift:244-250` (`transcribeAudio(...)`) → `IndicatorWindow.swift:280` (`transformIfEnabled(text)`) |

Consequence of the live config, measured on Polish audio (`say -v Zosia`, 16 kHz):
`ggml-tiny.en.bin` cannot transcribe Polish at all — `"Dzisiaj muszę wysłać raport do klienta."` →
`"Gisha Emoševiš was a reporter to the clean town."`; `"Zrób to jutro."` → `"(speaking in foreign
language)"`; its internal language detection returned `fa` / `ur` at `p = 0.0100`
(`whisper_is_multilingual == 0`). **The live config is a hard blocker for the captain's ask and must
change independently of the gate.**

### 1.2 Whisper engine (default) — verdict: yes, with exact call and cost

**Verdict: the detected language is available for one utterance, either (a) as a side effect of the
`whisper_full` call the app already makes when the setting is `auto`, or (b) from a dedicated
`langAutoDetect` call that costs one extra encoder pass. Option (a) is what the fork should use.**

Exact calls (fork wrappers, all currently **unused** — `grep` for `fullLangId|langAutoDetect|langStr(|
isMultilingual|pcmToMel` finds only the definitions in `Whis.swift`):

| Wrapper | Line | Underlying C call |
|---|---|---|
| `MyWhisperContext.fullLangId` | `Whis.swift:742-748` | `whisper_full_lang_id_from_state(state)` / `whisper_full_lang_id(ctx)` (`whisper.h:634-637`) |
| `MyWhisperContext.langAutoDetect(offsetMs:nThreads:langProbs:)` | `Whis.swift:248-254` | `whisper_lang_auto_detect_with_state(...)` (`whisper.h:384`) |
| `MyWhisperContext.langStr(id:)` | `Whis.swift:238-241` | `whisper_lang_str(id)` |
| `MyWhisperContext.isMultilingual` | `Whis.swift:281-284` | `whisper_is_multilingual(ctx)` |
| `MyWhisperContext.pcmToMel(samples:nSamples:nThreads:)` | `Whis.swift:175-181` | `whisper_pcm_to_mel_with_state` |

Where the value is **already computed and then dropped**:

* `whisper.cpp:6848-6864` — when `params.language == nullptr` (the fork's `auto` setting) or
  `params.detect_language`, whisper runs `whisper_lang_auto_detect_with_state(ctx, state, 0, …)` and
  writes `state->lang_id`. If `detect_language` was set, `whisper_full` then **returns immediately
  without transcribing** (`whisper.cpp:6861-6863`).
* `WhisperEngine.swift:261` calls `context.full(samples:params:)`; right after that,
  `context.fullLangId` holds the answer — but `WhisperEngine.swift:314-317` returns
  `DetailedTranscription(text:segments:)` (`WhisperEngine.swift:54-57`), which has **no language
  field**, and `WhisperEngine.swift:155` (`defer { context.freeState() }`) frees the state that holds
  it before the value can escape. `WhisperEngine.swift:120-122` (`transcribeAudio(url:settings:) ->
  String`) and `TranscriptionEngine.swift:9` (protocol) are text-only. That is the drop point.
* With a fixed setting the same getter merely echoes the setting (measured `set=en → reported=en`,
  `set=pl → reported=pl`) — no detection happens, so a fixed setting is an authoritative answer, not
  a measurement.

**Measured cost** (Apple M4, 8 threads = `min(activeProcessorCount, 8)`, Metal, fresh
`whisper_state` per utterance, `no_context = true`, model `ggml-large-v3-turbo.bin`; probe
`/tmp/fm04/probe.cpp`, 17 utterances: 16 synthetic 1.0–3.2 s + repo `jfk.wav` 11 s):

| Measurement | median | min–max |
|---|---|---|
| isolated `lang_auto_detect` (mel already computed) — warm | **908.7 ms** | 846.5 – 1327.0 |
| `whisper_full(detect_language=true)` (detect and return) | 906.1 ms | 848.2 – 1211.5 |
| `whisper_full(language=nil)` = detect **+** transcribe | 1945.2 ms | 1755.0 – 2571.5 |
| `whisper_full(language="en")` = fixed, no detect | 1039.8 ms | 894.4 – 1324.7 |
| **delta (auto − fixed)** | **+930 ms** | **+861 … +1247** |

Repeated run (4 files × 3 reps, same model): detect 904.9 ms, auto 1926.3 ms, fixed 1008.8 ms —
the delta is stable. Cost is **independent of utterance length**: it is one fixed 30 s encoder pass
plus one decoder step (`whisper.cpp:4045-4118`), confirmed on the repo's 106.6 s `long_ru` fixture
(detect 849.6 ms) — same as on a 1.06 s utterance.

Separate-detect-then-transcribe in the same state (`DETECTTHEN`) totals 1872–2017 ms median versus
1755–1945 ms for the engine's own internal detection: **doing an explicit `langAutoDetect` call buys
nothing** (whisper re-encodes window 0 either way, `whisper.cpp:6842` + `whisper.cpp:2388-2400`).

**Accuracy** (language of the utterance, gold from the file name):
turbo **17/17** + repo fixtures `long_ru` → `ru` (p = 0.9996) and `long_en` → `en` (p = 0.9982, tiny);
tiny multilingual **17/17** + same 2 fixtures. Lowest turbo confidence was a 3-word Polish utterance
(`"Zrób to jutro."`, p = **0.479**, still the correct argmax); everything else ≥ 0.96. Tiny's Polish
confidences were lower (0.591–0.991). **Do not gate on `p ≥ 0.5`** — use the argmax with a floor
around 0.3, or a top-2 margin.

**Cheap alternative — a second, tiny multilingual model used only as a detector**
(`ggml-tiny.bin`, 77.7 MB, md5 `ab7280bbcf29e334f7e3b2a9ac0ca386`; the same file the test suite
already looks for, `LongFormTranscriptionTests.swift:405-413`):

| Measurement (tiny, 39 M params) | median | min–max |
|---|---|---|
| isolated detect | **25.7 ms** | 24.9 – 26.7 |
| detect + transcribe | 70.4 ms | 58.6 – 148.6 |
| accuracy | 17/17 + 2 repo fixtures | — |

Detect-with-tiny then transcribe-with-turbo ≈ **26 ms + ~1.0–1.3 s ≈ 1.03–1.35 s**, versus
**~1.94 s** for full `auto` with turbo, i.e. it recovers most of the ~0.9 s, at the price of a second
resident model (measured warm load 85–90 ms; **first load in a fresh process was 9.8 s for tiny and
9.4 s for turbo** — mechanism not verified, most likely one-time Metal pipeline/graph setup; a ship
task that adds a second model must warm it at launch, the app already warms the main engine via
`TranscriptionService.prepareForRecording()` / `WhisperEngine.prepareForRecording()`).

### 1.3 Fixed language setting vs. detection — semantics

* `whisperLanguage = "auto"` (`Settings.swift:928-932` picker, `LanguageUtil.swift:5-7` list) ⇒ the
  engine detects inside the same `full()` call; the answer is `fullLangId` right after
  `WhisperEngine.swift:261`; the gate uses it. Costs the +0.93 s.
* `whisperLanguage = "pl" | "en"` ⇒ **no detection runs**; the gate must take the setting as
  authoritative (it is also what the decoder is conditioned on, so the transcript and the gate agree
  by construction), and must not spend a detection call to second-guess it.
* The gate must additionally check `context.isMultilingual` (`Whis.swift:281-284`): on an English-only
  model (`ggml-tiny.en`, `whisper_is_multilingual == 0`) `fullLangId` still returns a value
  (measured `fa`/`ur` at p = 0.01) and is meaningless.
* Practical guidance for the captain's bilingual use: set the picker to **Auto-detect** and use a
  multilingual model (`Turbo V3 large` / turbo q5/q8, `Settings.swift:606-627`). "Auto-detect" today
  still transcribes correctly *and* is the only source of the language signal.

### 1.4 FluidAudio / Parakeet (the other engine) — verdict: no language signal

`FluidAudioEngine.swift:70-107` consumes `AsrManager.transcribe(url, decoderState:)`; the returned
`ASRResult` (`FluidAudio/.../ASR/Parakeet/AsrTypes.swift:76-101`) contains `text`, `confidence`,
`duration`, `processingTime`, `tokenTimings`, `performanceMetrics`, `ctcDetectedTerms`,
`ctcAppliedTerms` — **no language field**. In FluidAudio, `language` is only an *input* hint
(`AsrManager.swift:234`, `:288-335`: script-aware token filtering, v3 only). So for `fluidaudio` the
gate must fall back to the transcript heuristic (§2). FluidAudio is not the default engine
(`AppPreferences.swift:38`), and its language list is restricted (`LanguageUtil.swift:16-29`).

---

## 2. Fallback detection when the engine gives no signal

Method: 22-utterance core set (12 Polish incl. 2 diacritic-free chat-style, 10 English incl. 2–4-word
utterances) plus a 32-utterance adversarial set (1–3 words, diacritic-free Polish, Polish words that
look English), fed (a) as clean text, (b) as the *actual engine transcripts* from the turbo `auto` run.
Backend: the live local endpoint `http://127.0.0.1:1919/v1/chat/completions`, served model
`qwen2.5-1.5b-instruct-q4_k_m` — i.e. exactly the model `Scripts/transform-server.sh` serves and the
new `AppPreferences.transformModel` default (`AppPreferences.swift:145`).

### 2.1 Text heuristic (diacritics + function words + bigrams)

Rule set (`/tmp/fm04/heuristic.py`): score Polish = `3.0 + min(#diacritic letters, 4)` if any of
`ąćęłńóśźż` appear, plus `1.5 ×` Polish-unique function words (`nie, się, że, jest, są, czy, ale, już,
tylko, może, muszę, wiem, żeby, proszę, dziękuję, jutro, wczoraj, dzisiaj, …`), plus `0.5 ×` weak
Polish markers (`w, z, na, do, po, za, od`), plus `0.5 ×` Polish bigrams
(`cz, sz, rz, dz, ść, prz, trz, się, nie, owa, ego, ych, ami, iem`); English score = English function
words (`the, is, are, of, to, in, for, with, this, that, you, we, can, should, my, please, thank,
need, send, report, …`) plus `0.5 ×` English bigrams. Higher score wins; **equal scores ⇒ `unknown`**;
both zero ⇒ `unknown`.

| Test set | n | accuracy | PL | EN |
|---|---|---|---|---|
| clean text, realistic sentences | 22 | **100.0 %** | 100 % | 100 % |
| **actual engine transcripts** (turbo `auto`) | 16 | **100.0 %** | 100 % | 100 % |
| adversarial: 1–3 words / diacritic-free | 32 | **71.9 %** | 75.0 % | 68.8 % |

Honest caveat: I wrote the fixtures and the rule set in the same sitting, so the two 100 % rows are
optimistic (they do show the rule fires correctly on realistic dictated sentences; they do not prove
generalisation). The adversarial row is the useful number.

Failure modes observed (adversarial set), verbatim:
* `"Ok"`, `"Okay"`, `"Yes"`, `"Good"`, `"Wiem"`, `"Musimy isc"`, `"Chce nowy laptop"` → `unknown`
  (no signal at all) — 7 of 9 failures.
* `"Zrob to"` (PL, no diacritics) → `en`; `"I know"` (EN) → `pl` (both scores ~1.0–1.5: the rule is a
  coin flip on 2-word utterances).
* `"Do it"` → tie (`pl = en = 2.0`) → `unknown` (correct behaviour, wrong verdict — the tie rule is
  doing its job).

Cost: microseconds (pure string work, no I/O). No new dependency; lives naturally beside
`Utils/LanguageUtil.swift`.

### 2.2 Single classification call to the local endpoint

Prompt: `"You are a language classifier. Reply with exactly one word: Polish, English, or Other."`
(app body shape: temperature 0.2, `stream: false`, `chat_template_kwargs.enable_thinking: false`).

| Metric | Result |
|---|---|
| Accuracy (22 utterances) | **20/22 = 90.9 %** |
| Latency | median **361 ms**, min 101 ms, max 634 ms (server warm, prompt cache effective) |
| Failure | `"Czy możesz mi pomóc z tym projektem?"` (PL) → `English`; `"Yes, please."` (EN) → `Other` |

Verdict: **not worth it as a first-line signal.** It is ~14× more expensive than the whole heuristic
and *less* accurate on the realistic set, and it inherits the endpoint's availability. Its one good
use is when a transform is going to happen anyway — then classification rides along for free (§2.3).

### 2.3 Unified "translate if Polish, else unchanged" prompt (measured)

Same endpoint, one call, used instead of detect+translate (6.2 s vs two batches measured earlier):

* 22 utterances, accuracy by my rule (PL ⇒ output English; EN ⇒ output unchanged): **19/22 = 86.4 %**.
* **English identity was only 7/10.** Verbatim mutations: `"I don't know if we'll make it in time."` →
  `"I'm not sure if we'll make it in time."`; `"Can you help me with this project?"` → `"Can you assist
  me with this project?"`; `"I sent you a message yesterday on WhatsApp."` → `"I sent you a message on
  WhatsApp yesterday."`
* Polish side: 12/12 correct (`"Tak, proszę."` → `"Sure, please go ahead."`).
* Latency median **762 ms** (296–1108 ms).

Verdict: a good **fallback for `unknown` only** (where the alternative is doing nothing), never the
default for text whose language is already known.

### 2.4 Ranked options + recommended fallback chain

| Rank | Option | Cost | Accuracy | Verdict |
|---|---|---|---|---|
| 1 | whisper `auto` + `fullLangId` (same call) | +0.93 s/utterance | 17/17 + 2 fixtures | **primary**, and free to read |
| 2 | tiny multilingual detector, then transcribe at that language | +26 ms detect (≈ +0.0 s net vs `auto`) | 17/17 + 2 fixtures | best latency; needs a 2nd model + warm-up |
| 3 | transcript heuristic | ~0 ms | 100 % realistic / 71.9 % adversarial | **fallback** (FluidAudio, no engine signal) |
| 4 | unified translate-or-passthrough call | ~0.3–1.1 s (already paying for the transform) | 19/22, English identity 7/10 | **unknown-only fallback** |
| 5 | dedicated classification call | +361 ms | 20/22 | reject as a first-line signal |
| — | explicit `langAutoDetect` before `full()` | +0.90 s | 17/17 | reject: identical cost to `auto`, more code |

Chain to implement:
`engine language (multilingual whisper)` → `heuristic(transcript)` →
if still `unknown`: `(translate ∨ tone) && words > 3` ⇒ unified single-call transform;
otherwise **raw passthrough**.

---

## 3. Gate design

### 3.1 Inputs and outputs

Inputs at the transform hook (`IndicatorWindow.swift:280`):
`translateEnabled` (existing, `AppPreferences.swift:131-132`), `toneEnabled` (new),
`transformToneMode` (`AppPreferences.swift:135-140`), source language `L ∈ {pl, en, unknown}`,
transcript word count (`short` := ≤ 3 words).

Outputs: `none` (raw text straight to `insertText`, `IndicatorWindow.swift:283`),
`translate` (PL→EN, no tone text), `toneOnly`, `translateWithTone`, or `unified`
(single translate-or-passthrough call).

Best implementation shape: a **pure** function
`static func policy(translate: Bool, tone: Bool, language: String?, wordCount: Int) -> TransformPolicy`
next to `TranslationService` — this makes §5's unit tests trivial and keeps the async service thin.

### 3.2 Decision table (with the tone switch)

| `translateEnabled` | `toneEnabled` | L | length | Action | Cost / why |
|---|---|---|---|---|---|
| off | off | any | any | **none** — raw transcript → keypress | no HTTP, no detection; also skip the language work entirely |
| off | off | — | — | — | — |
| off | **on** | `pl` | any | **none** (recommended) | measured: tone-only prompt on Polish returns **English anyway** (3/3 samples), i.e. it silently translates — see §3.4 |
| off | on | `en` | any | **toneOnly** (English in, English out) | measured: `"Do it tomorrow."` identity; `"I need to send the report to the client today."` → `"I am required to transmit the report to the client today."` (register + vocabulary drift) |
| off | on | `unknown` | any | **none** | do not gamble; a rewrite of unknown-language text may translate it |
| **on** | off | `pl` | any | **translate** (no tone sentence) | the captain's PL→EN case without tone |
| on | off | `en` | any | **none** (recommended) | measured: any model call mutates English (`"Do it tomorrow."` → `"I'll do it tomorrow."`); 7/10 identity even when told to pass through |
| on | off | `en` | any | *alt:* unified call | captain's option if he wants *some* cleanup of English |
| on | off | `unknown` | short (≤3 words) | **none** | avoid turning `"Yes, please."` into nonsense |
| on | off | `unknown` | long | **unified** | 19/22 measured; single call |
| **on** | **on** | `pl` | any | **translateWithTone** | today's behaviour (`TranslationService.swift:133-136`) |
| on | on | `en` | any | **none** *(recommended)* or **toneOnly** *(captain's call)* | see §3.3 |
| on | (either) | `unknown` | short | **none** | as above |

`none` = zero HTTP requests; text goes to `IndicatorWindow.insertText` → `applyPostProcessing`
(`IndicatorWindow.swift:344-352`) → `KeyboardSimulator.typeText`.

### 3.3 English with translation on: passthrough vs tone-only — the tradeoff

| | raw passthrough (recommended) | tone-only English rewrite |
|---|---|---|
| Latency | 0 ms, no endpoint needed | measured 311–1451 ms (1.5 B model), bounded by `transformTimeout` 8 s |
| Text fidelity | exact dictation | mutates wording: `"I need to send the report to the client today."` → `"I am required to transmit the report to the client today."`; `"Do it tomorrow."` unchanged in 1 of 2 samples |
| Own-language coherence | English dictation is not "toned" while Polish dictation is (if tone is on) | tone is consistent across languages |
| Failure mode | none (no call) | model drift/reordering of the captain's own English |

**Recommendation: raw passthrough.** The captain's complaint is precisely that English was being
processed when it should not be; mutating his English to satisfy a tone setting is the same class of
error. If he wants toned English, the tone switch gives him exactly that — this is a captain decision,
and the table row above is the one line to flip.

### 3.4 Tone-only semantics (translation off, tone on) — measured risk

Prompt used: `"Rewrite the user's text in a formal, professional tone, keeping the same language as
the input. Output ONLY the final text…"` — with and without the added sentence `"Do not translate the
text."`, against `qwen2.5-1.5b-instruct-q4_k_m`:

| Input (PL) | without "Do not translate" | with "Do not translate" |
|---|---|---|
| `"Zrób to jutro."` | `"Please do it tomorrow."` | `"Please do it tomorrow."` |
| `"Nie wiem, czy zdążymy na czas."` | `"I am unsure whether we will manage to achieve our goal on time."` | `"I am unsure if we will manage to achieve our goal on time."` |
| `"Wyślij raport."` | `"Submit the report."` | `"Submit the report."` |

**6/6 outputs were English.** The explicit instruction does not stop the small model from translating.
So for Polish input, "tone only" is not reachable with this model — the honest options are
(a) passthrough Polish (recommended default: the captain asked for "Polish without translate"), or
(b) accept that Polish with tone becomes English (defeats the request).

English tone-only is different: it stays English and mostly keeps the meaning, with vocabulary drift
(`send → transmit`, `help → assist`). Semantics to specify: **tone-only means "same language in, same
language out" — and the implementation must treat a tone-only result whose language *changed* as a
failure and fall back to the raw transcript.** The heuristic of §2.1 gives a cheap check for that
(`detect(output.language) != detect(input.language)` ⇒ discard).

### 3.5 Preferences

| Preference | Key | Default | Status |
|---|---|---|---|
| translation switch | `translateEnabled` | `false` | exists (`AppPreferences.swift:131-132`, UI `Settings.swift:1061`) — no change |
| **tone switch** | **`toneEnabled`** | **`false` (proposed)** | **new**; gates whether *any* tone text is sent |
| tone choice | `transformToneMode` | `neutral` | exists (`AppPreferences.swift:135-140`, UI `Settings.swift:1069-1077`) — unchanged, only consulted when `toneEnabled` |
| endpoint/model/timeout | `transformEndpoint` / `transformModel` / `transformTimeout` | `http://127.0.0.1:1919/v1/chat/completions` / `qwen2.5-1.5b-instruct-q4_k_m` / `8.0` | exist (`AppPreferences.swift:142-149`) — unchanged |
| transcription language | `whisperLanguage` | `"en"` code default (`AppPreferences.swift:65-66`) | exists; the *language-awareness* control. Recommend Auto-detect for the captain (see §1.3); consider surfacing a hint when `translateEnabled && whisperLanguage != "auto" && model is multilingual` |

Why `toneEnabled` must default **`false`**: the four combinations are new, and with a `true` default a
user who has translation **off** would immediately start getting tone rewrites of everything he
dictates — a behavior change that fires without him touching anything. `false` keeps every existing
install bit-identical until the captain flips the switch (translation-on users lose only the tone
sentence, which for the default `neutral` was `"Keep a neutral, natural tone."`).
If the captain prefers "translate on ⇒ toned as before", the migration belongs in
`AppPreferences.migrateOldPreferences()` (`AppPreferences.swift:24-32`): one-time
`toneEnabled = true` for installs that already had `translateEnabled == true`.
No further preference is needed for language awareness — the gate is automatic; `translateEnabled`
already is the manual override.

### 3.6 Prompt composition for the four combinations

Current code: `TranslationService.systemPrompt(for:)` (`TranslationService.swift:132-137`) always
appends `tone.instruction` (`TranslationService.swift:20-27`), and the tone picker's label text lives
in `ToneMode.displayName` (`TranslationService.swift:11-18`).

| translate | tone | System prompt must read | Notes |
|---|---|---|---|
| off | off | *(no request at all)* | never reach `buildRequestBody` |
| off | on | `You are a rewriting assistant. Rewrite the user's text in the requested tone, keeping the same language as the input. Do not translate. <tone.instruction> Output ONLY the final text, with no quotes, labels, or explanation.` + newline + `/no_think` | measured to *still* translate Polish — see §3.4; English only in practice |
| on | off | `You are a translation assistant. Translate the user's Polish text into natural English. Output ONLY the final English text, with no quotes, labels, or explanation.` + newline + `/no_think` | tone sentence and `tone.instruction` **removed entirely** (no "neutral tone" text — the current neutral instruction is exactly the text the captain wants gone) |
| on | on | unchanged from today (`TranslationService.swift:133-136`) with `tone.instruction` | — |

Everything else in the request body stays as-is for all three variants:
`temperature: 0.2`, `stream: false`, `chat_template_kwargs: {"enable_thinking": false}`, and
`model`/endpoint/timeout from prefs (`TranslationService.swift:118-129`, `:83-95`). The proposed
`systemPrompt` signature change is `systemPrompt(for tone: ToneMode?)` (or
`systemPrompt(for policy: TransformPolicy)`) — `nil`/tone-off means "no tone text", which also
removes the need for a separate "neutral means off" hack.

---

## 4. Insertion points and blast radius (exact `file:line`)

All line numbers verified at HEAD `bd5ad0e` (`feat/local-translate-tone`). Note: the primary checkout
**advanced during this session** (from `92fc012` to `bd5ad0e`, the transform-backend commits landed);
the lines below were re-verified afterwards.

**Engine → hook (language must travel with the text)**

1. `Engines/TranscriptionEngine.swift:4-11` — protocol. Changing `transcribeAudio(url:settings:)`
   (`:9`) breaks 3 fake engines in tests (`WhisperPreparationTests.swift:24`,
   `EngineLoadingTests.swift:11`, `TranscriptionCancellationTests.swift:38`). Recommend leaving the
   protocol as-is.
2. `Engines/WhisperEngine.swift:54-57` — add `let language: String?` to `DetailedTranscription`;
   set it at `:314-317` from `MyWhisperContext.langStr(id: context.fullLangId)` read **immediately
   after** `context.full(...)` at `:261` (the state is freed at `:155`), guarded by
   `context.isMultilingual` (`Whis.swift:281-284`). Empty-audio early return `:200` also constructs
   the struct.
3. `Engines/WhisperEngine.swift:120-122` (`transcribeAudio`), `:127-132`
   (`transcribeAudioDetailed`), `:134-136` (`transcribeSamples`) — the language must be surfaced
   through whichever one the dictation path uses.
4. `Engines/FluidAudioEngine.swift:37-101` (result at `:84`) — no signal available; return
   `language: nil` (`AsrTypes.swift:76-101`).
5. `TranscriptionService.swift:237-247` (`transcribeAudio(url:settings:operationID:pcmSamples:)`) —
   change the return type to a small struct (e.g. `struct TranscriptionOutput { let text: String; let
   language: String? }`); the engine result is produced at `:319`. Keep the convenience overload
   `:228-234` returning `String` (`.text`) so the 25 test call sites stay untouched; production call
   sites to update: **`Indicator/IndicatorWindow.swift:244`, `TranscriptionQueue.swift:258`,
   `ContentView.swift:215`** (plus ~4 test sites that pass `operationID`: `LongFormTranscriptionTests
   .swift:370`, `TranscriptionCancellationTests.swift:266/294/311`).
   *Alternative, zero-churn:* a `@Published private(set) var detectedLanguage: String?` on
   `TranscriptionService` set beside `transcribedText` — idiomatic here (the class already publishes
   `transcribedText`, `currentSegment`, `progress`), but it is ambient state that can go stale across
   concurrent operations; prefer the explicit return value.

**Gate**

6. `Indicator/IndicatorWindow.swift:280` — replace `TranslationService.shared.transformIfEnabled(text)`
   with `transformIfEnabled(text, sourceLanguage: output.language)` (or
   `transformIfEnabled(text, policy: …)`).
7. `TranslationService.swift:66-78` (`transformIfEnabled`) — the gate; add the pure
   `policy(...)` function (§3.1). Keep the "never throws, always returns text" contract (`:70-77`) —
   it is what makes the passthrough safe.
8. `TranslationService.swift:118-129` (`buildRequestBody`), `:132-137` (`systemPrompt`) — tone becomes
   optional (§3.6). Body keys unchanged.

**Preferences + UI**

9. `Utils/AppPreferences.swift:131-140` — add `toneEnabled` (`@UserDefault(key: "toneEnabled",
   defaultValue: false)`); optional migration in `:24-32`.
10. `Settings.swift:200-204` (add `toneEnabled` VM property mirroring `translateEnabled`),
    `:263-267` (restore from prefs in the view-model init), `:1045-1109` (the "Translation & Tone"
    section): new tone toggle above the Tone picker (`:1069-1077`) with
    `.disabled(!viewModel.toneEnabled)`. Ownership rule: **each toggle gates only its own controls** —
    `toneEnabled` gates the Tone picker alone; `translateEnabled` gates nothing by itself any more;
    the Endpoint/Model/Timeout fields are gated by `(translateEnabled || toneEnabled)` because either
    transform needs the endpoint. Today the Tone picker is disabled when *translation* is off
    (`:1076`) — that is the line whose condition must change. The Endpoint/Model/Timeout fields
    (TextFields at `:1082`, `:1090`, `:1098`; their `.disabled` modifiers at `:1084`, `:1092`, `:1103`)
    currently use the same `!translateEnabled` condition and must become
    `.disabled(!(translateEnabled || toneEnabled))` because a tone-only transform still needs the
    endpoint. **`Settings.swift:1106` caption must be rewritten** —
    it currently promises "the pasted text is the translated, tone-adjusted English"; after this change
    the pasted text is raw, translated, tone-only, or translated+toned depending on the two switches.
11. Optional: `Utils/LanguageUtil.swift` remains the language-list owner; put the heuristic in a new
    `Utils/LanguageDetector.swift` (pure, no dependencies) beside it.

**Not part of the gate today (decide explicitly)**

12. `TranscriptionQueue.swift:257-258` (regenerate-from-queue) and `ContentView.swift:215`
    (content-window dictation) transcribe but **never** call `transformIfEnabled` — only
    `IndicatorWindow.swift:280` transforms. So queued/regenerated recordings already receive the raw
    transcript. Widening the API forces a decision here; recommendation: keep the file/queue path raw
    for this ticket (it is not the hotkey dictation path the captain uses) and say so in the caption.

**Recording store** — history must keep the raw transcript: `IndicatorWindow.swift:266` stores `text`
into `Recording.transcription` (`Models/Recording.swift:16`) and `addRecordingSync` happens at `:275`
**before** the transform at `:280`. Preserve that order; the gate must not be moved above the save.

---

## 5. Tests a ship task must prove

Pure unit tests (no model, no network) — extend `OpenSuperWhisperTests/TranslationServiceTests.swift`
(its scaffolding already fits: `StubURLProtocol` `:10-70`, `setUp/tearDown` save-restore of prefs
`:106-127`, `enableTranslation` `:139-150`, "no request was attempted" assertions `:329-356`,
`applyPostProcessing` `:502-519`, `ToneMode`/pref round-trip `:521-534`):

| Case | Assertion |
|---|---|
| policy table rows with `none` | returned text == input **and** `StubURLProtocol.requestCount == 0` (mirror `:343-356`) |
| policy table rows with a transform | `requestCount == 1` |
| prompt, translate on + tone off | system message contains no tone instruction and no "neutral" wording |
| prompt, translate off + tone on | system message contains the "keep the same language / do not translate" wording, no "Translate the user's Polish text" |
| prompt, translate on + tone on | contains `tone.instruction` for each of the three `ToneMode`s |
| request body invariants per policy | `temperature == 0.2`, `stream == false`, `chat_template_kwargs == ["enable_thinking": false]`, model/endpoint from prefs |
| `toneEnabled` pref round-trip | mirror `:529-534` |
| language heuristic | own file (or extend `StorageAndLanguageSettingsTests.swift`, which already owns language-list tests `:70-107`): the pl/en table + the adversarial set + the "no signal ⇒ unknown" boundary + tie ⇒ unknown |
| engine-language → policy wiring | feed `("Cześć", language: "pl")` / `("Hello", language: "en")` / `(text, language: nil)` into the gate and assert the policy + request count (this is the test that would have caught the original bug class) |

Engine/integration (opt-in, `XCTSkip` without a model — reuse the established pattern
`LongFormTranscriptionTests.swift:405-424` (`multilingualModelURL()`, candidates:
`OSW_TEST_MULTILINGUAL_MODEL`, `.build/test-models/ggml-tiny.bin`, `./ggml-tiny.bin`) and
`fixtureURL(_:fileExtension:)` `:430-456`; `Fixtures/README.md` documents the fixtures and the
opt-in command):

| Case | Evidence it will pass |
|---|---|
| `WhisperEngine` + `selectedLanguage = "auto"` on `Fixtures/long_en.m4a` / `long_ru.m4a` ⇒ reported language `en` / `ru` | measured: tiny `en` p = 0.9982, `ru` p = 0.9974; turbo `ru` p = 0.9996 |
| `selectedLanguage = "en"` ⇒ reported language == `"en"`, detection skipped (no `langAutoDetect` call) | measured: `set=en → reported=en`, `set=pl → reported=pl` |
| `TranscriptionOutput.language` reaches the gate end-to-end | unit-level suffices; the engine half is the row above |
| non-multilingual model ⇒ `language == nil` (no `fullLangId` trust) | measured: `ggml-tiny.en` reports garbage (`fa`/`ur`, p = 0.01) |

Not unit-testable (must not be faked): whether the translate/tone model *preserves* language and tone
quality, and the endpoint's real latency. Those belong in a real-backend check — the sibling ship task
already added `Scripts/verify-transform.sh` (394 lines) as the model for that; if the ship wants the
new policy asserted against the live backend, add cases there instead of in XCTest.
`OpenSuperWhisperTests/KeyboardSimulatorTests.swift` needs **no** change: the insertion path
(`IndicatorWindow.swift:322-340`) is untouched by this feature, and the gate must not alter it.

---

## 6. What I did NOT verify (explicit)

* **No end-to-end app run.** I did not build or launch `OpenSuperWhisper.app`, did not dictate into
  it, and did not observe the indicator/paste path. All timings are whisper-level and
  HTTP-level, not full dictation latency (the app additionally does file conversion, VAD, model
  load/state setup, and — for the transform — the HTTP round trip).
* **No test suite run** (out of scope for a read-only scout).
* **The captain's own voice.** All Polish/English audio is synthetic (`say -v Zosia` /
  `-v Samantha`) plus the repo's `jfk.wav` and `long_en/long_ru` fixtures. Real speech, accents and
  code-switching inside one utterance are not covered; the 3-word Polish case (`p = 0.479`) shows the
  margin shrinks exactly where real short utterances live.
* **Code-switching** (one utterance mixing Polish and English) is not evaluated anywhere in this
  report — the engine returns a single language per utterance.
* **The 9.4–9.8 s first-load number** for both models in a fresh process is measured but its cause
  (Metal pipeline/graph setup vs. page cache) is **unverified**; the steady-state numbers (85–90 ms
  tiny, 470–1928 ms turbo) are what matter for a resident model.
* **Interaction with VAD trimming**: the app transcribes speech-only samples
  (`WhisperEngine.swift:192-206`, `speechOnlySamples` at `:387`), whereas my probe fed whole files.
  Detection quality on VAD-trimmed audio is unverified (it should improve, not degrade, but I did not
  measure it).
* **Tone quality** under the 1.5 B production model was only spot-checked (the sibling task owns that
  check); my §3.3/§3.4 conclusions about *mutation* and *translation leakage* are measured, but
  "is the toned output good" is not my verdict to give.
* The live endpoint at `127.0.0.1:1919` was used read-only for classification/rewrite probes; I did
  not start, stop or reconfigure it, and I did not touch the sibling worktree
  `OpenSuperWhisper-fm-fm-20260923-03`.
* One incidental integration fact worth knowing: the captain's **stored** preference still says
  `transformModel = "Qwen/Qwen3-14B-MLX-6bit"` while the code default is now
  `qwen2.5-1.5b-instruct-q4_k_m`. Measured: `llama-server` answers HTTP 200 for the stale id anyway,
  so nothing is broken — but a one-time reset/migration of that stored value would be tidier.

## 7. Environment and raw material (reproducibility)

* Machine: Apple M4, Darwin 27.0.0, Metal; whisper threads `min(activeProcessorCount, 8)`.
* whisper.cpp: the repo submodule source, built out-of-source
  (`cmake -B /tmp/fm04/build -S <repo>/libwhisper/whisper.cpp -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF -DGGML_MATMUL_INT8=0 -DCMAKE_CXX_FLAGS=-U__ARM_FEATURE_MATMUL_INT8
  -DWHISPER_BUILD_EXAMPLES=ON`); the repo itself was not written to (all build output under `/tmp/fm04`).
* Models: `ggml-large-v3-turbo.bin` (1.62 GB, read from `~/Library/Application Support/superwhisper/`),
  `ggml-tiny.bin` (77,691,713 B, md5 `ab7280bbcf29e334f7e3b2a9ac0ca386`, downloaded to
  `/tmp/fm04/models/`), `ggml-tiny.en.bin` (repo root).
* Audio: repo `jfk.wav` (11.0 s, 16 kHz mono s16); repo `OpenSuperWhisperTests/Fixtures/
  long_en.m4a` (97.1 s) and `long_ru.m4a` (106.6 s) converted to 16 kHz mono WAV with ffmpeg;
  16 synthetic utterances (`say -v Zosia` PL / `-v Samantha` EN → `afconvert -f WAVE -d LEI16@16000 -c 1`).
* Probes (throwaway, all under `/tmp/fm04`, outside every repo):
  `probe.cpp` (whisper C API: fresh state per utterance, `pcm_to_mel` + `lang_auto_detect`,
  `full` with `language=nil|"en"|"pl"` and with `detect_language=true`, `full_lang_id`,
  `detect-then-transcribe`, repeatable with `--repeat`), `heuristic.py`, `llm_probe.py`,
  `llm_probe2.py`; logs `turbo_all.log`, `tiny_all.log`, `turbo_repeat.log`, `adversarial.log`.
* Endpoint: live `llama-server` on `http://127.0.0.1:1919` serving
  `qwen2.5-1.5b-instruct-q4_k_m` (the model `Scripts/transform-server.sh:22-30` fetches/serves and
  `AppPreferences.swift:145` now defaults to).
* Repo revision: `bd5ad0e` on `feat/local-translate-tone` (working tree clean at the time of the last
  verification; `libwhisper/whisper.cpp` submodule clean at `bd5ad0e`).
