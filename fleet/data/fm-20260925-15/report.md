# fm-20260925-15 — Polish in, Polish out; English in, English out; and his words survive

Worktree `/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/worktrees/OpenSuperWhisper-fm-bilingual`, branch
`fm/bilingual-check` @ `eaecd28`. Headless throughout: no app launch, no `osascript`, no `screencapture`, no bare
`xcodebuild test`. **Nothing in the application changed** — one new file in the test target, left untracked; no commit,
no merge, no push, no tag. This task measures and reports.

**The captain's authorisation, verbatim:** *"I check if my recordings are in good condition, and it's okay to test
them."*

## Verdict

**Both properties hold on his own voice, through the app's own code — and the transform still leaves marks on 23 of the 87 recordings, five of them the same defect the guard cannot see.**

**Language.** Polish comes back Polish and English comes back English: **not one of the 87 recordings flipped language**, and the app's own detector reads the final text as the language the engine heard on 80 of them. All seven that "differ" are accounted for and none is a flip — six are texts too short (1.1–16.8 s) for the detector to place at all, and one is the detector's own false positive on an English clip (`I think peak hour starts, freeze.`), where the gate used the engine's `en` and the output stayed English. **Both anchors: Polish→Polish and English→English, with zero words added, zero words dropped and no word replaced.** The only difference between his raw transcript and what would have been pasted is punctuation and capitalisation.

**Words.** Across the library the model changed 23 recordings' cleaned text; the ordered diff totals **36 dropped and 26 added words**, of which **21 of the drops are the deterministic clean-up** (fillers, stutter and repeated sentences — a pure function that can only remove). As a multiset, which is the count that separates a real loss from a word that merely moved: **35 words genuinely lost, 25 genuinely new** across 862 s of his speech, out of an 87-recording library. 40 recordings' final text differs from the raw transcript at all; 47 are byte-identical.

**Guard.** **Zero rejections in 87 recordings** — the guard never had to fire, and nothing was thrown away in favour of his own words. It also never fired on the one defect that is plainly visible: **five recordings where the model returned the transform prompt's own delimiter** (`TRANSCRIPT` / `TRANSKRYPCJA`) instead of, or around, the text, and it was pasted. Reported, not fixed (§8).

**The translation he complained about is in his history, not in this chain.** 49 of his 87 stored rows reproduce this chain's raw decode byte-for-byte, and the misses are not random: **14 of the 27 recordings the engine hears as Polish carry English text in his history** — `Teraz test w języku polskim…` is stored as `Now a test in Polish language.` — and two of them are stored as `(speaking in foreign language)`. Whatever wrote those rows translated; today's chain does not, and the same audio comes back Polish. The `translateEnabled = 1` and `transformTargetLanguage` keys are still in his domain, and no code path reads them.

## His configuration, read from his own preference domain at run time

`defaults export ru.starmel.OpenSuperWhisper`, read by the harness before the first decode — so the numbers below are
what **his** app does today, not a hypothetical setting:

| key | value | effect on this measurement |
|---|---|---|
| `toneEnabled` | `1` | tone rewrite on |
| `cleanUpDictation` | absent → default `true` | deterministic scrub on, grammar repair folded into the same call |
| `transformToneMode` | `neutral` | register: change as little as possible |
| `transformReference` | absent → empty | no reference block in the composed prompt |
| `initialPrompt` | `""` (empty) | the decoder is given no prompt |
| `longPausesEndSentences` | **absent → off** | `PauseBoundaryPolicy.upstream`: 0.1 s of zeros at every pause, no terminator |
| `selectedEngine` / `selectedWhisperModelPath` | `whisper` / `ggml-large-v3-turbo.bin` | the multilingual model his recordings were made with |
| `translateEnabled`, `transformTargetLanguage`, `whisperLanguage` | stale values | dead keys: no code path reads them |

**Say it plainly, because the numbers will be read as "what his app does today":** the pause work that landed today
(`fm-20260924-12`, "Long Pauses End the Sentence") is **not in this chain**. Its switch is absent from his domain and
its default is off, so every recording here was decoded with the pre-existing stitching — the switch-off arm of that
task. Nothing in this report is a measurement of the pause feature.

Both transform weights are installed and verified on this machine (`qwen2.5-1.5b-instruct-q4_k_m` and
`qwen3-8b-q4_k_m`), and the gate's own routing — `TransformModelManager.model(for:)` — sends a tone rewrite (this
policy, in either language) to the **8B**. Which model answered is printed per recording in the evidence.

## The chain, exactly as the app runs it

Every recording went through the shipping path (`OpenSuperWhisper/Indicator/IndicatorWindow.swift:305-353`):

```text
engine decode → raw transcript → DictationScrubber (clean-up) → TransformService (tone + grammar, one call) → pasted text
```

| stage | the call the harness made | what it is |
|---|---|---|
| decode | `WhisperEngine.transcribeAudioDetailed(url:settings:pausePolicy:)` | the app's own engine, his model, his decoder settings |
| clean-up | `DictationScrubber.scrub(_:)` | the same pure function the indicator calls |
| transform | `TransformService.transformDetailed(text, sourceLanguage:)` | the app's own gate, prompt, guard and model routing |
| weights | `TransformModelManager` + `TransformRuntime` | the real ones, hard-linked into a scratch directory so his Application Support was only ever read |

**Every language label in this report is the app's own `LanguageDetector.detect`**, which is also what the gate's
`TransformPolicy.resolve` falls back to; the engine's own whisper language code is printed beside it, never
substituted for it. Where the two disagree the row says so.

## Method: the word accounting

An LCS diff over case-folded words (letters and digits; punctuation ignored, so re-punctuating a sentence is not
counted as a change). Three diffs per recording:

- **raw → cleaned** — what the deterministic scrub removed. It can only remove, never invent.
- **cleaned → final** — what the model changed. This is the number that decides "the transform does not damage it".
- **raw → final** — the whole chain, which is what the pasted text is measured against.

A word in the final text that is not in the raw transcript is **added** (invented); one in the raw transcript that
never reached the final text is **dropped**. Both lists are printed in full, verbatim, per recording.

One caveat about reading those lists: an ordered LCS diff reports a *moved* or *duplicated* word as one dropped plus
one added. Where that happens the report also gives the multiset difference — **genuinely lost** and **genuinely
new** — which is what separates a real loss from a move.

## Provenance of this run

| item | value |
|---|---|
| harness | `OpenSuperWhisperTests/BilingualLibraryMeasurementTests.swift` (new, test target, untracked) |
| invocation | `Scripts/dev-run.sh test -only-testing:OpenSuperWhisperTests/BilingualLibraryMeasurementTests` |
| opts | `OSW_TEST_CAPTAIN_RECORDINGS`, `OSW_TEST_MULTILINGUAL_MODEL`, `OSW_TEST_EVIDENCE`, `OSW_TEST_LIBRARY_DB`, `OSW_TEST_TRANSFORM_MODELS_DIR` (exported in both plain and `TEST_RUNNER_` form) |
| budget | `OSW_TEST_LIBRARY_BUDGET_SECONDS=5400`; the anchors are exempt and decoded first |
| machine gate | no `xcodebuild` and no `llama-server` alive, two observations 60 s apart → launched 2026-09-25T09:21:12Z (`evidence/wait-and-run.py`, `/tmp/fm2415-gate.log`) |
| raw evidence | `evidence/decode-evidence.log` (the harness's own output), `evidence/library-rows.json` + `library-schema.sql` (read-only snapshot), `evidence/analysis.txt` |
| extraction | `evidence/analyse.py`, `evidence/build-report.py`, `evidence/assemble.py` — **validated on a synthetic log first**, then every aggregate below was re-counted against the raw blocks by hand before it was written here |
| run log | `/tmp/fm2415-run.log`, copied to `evidence/xcodebuild-run.log` |

## Integrity: what this run did not do

- **No application behaviour changed**, no file outside the test target touched, nothing committed.
- **Nothing was launched** by this task; the engine, the runtime and the weights ran inside the test host.
- **His data was read, not written**: the recordings and `recordings.sqlite` were opened read-only, and the transform
  weights are hard links in a scratch directory under `~/Library/Caches` removed by a teardown block. No preference
  was written — his domain was only exported.
- **Nothing is left resident**: the whisper engine and the transform runtime are unloaded in `defer`, and the runtime
  is in-process (no `llama-server`).
- **The library is live, and this run did not freeze it.** His own app was running throughout (not launched by me): the
  database held 87 rows when the run read it at 09:21Z and 90 rows by 09:34Z (the newest written 09:28:49Z), and the
  recordings directory grew from 91 to 95 files. **This report measures the 87 rows the run found**; the rows written
  afterwards are not in it, and are named here rather than dropped.

## 1. The two anchors, in full, verbatim — with the short English clip he made beside them

### 9039BAB0-CBA2-49B2-82E1-432FF7B94589.wav — 117.8 s — 2026-09-25 09:03:01.310

- engine language: `pl` | gate: `pl` | detector on the raw transcript: `pl` | on the final text: `pl` | flip: **no**
- policy: `Polish, neutral tone, clean-up` | model answered: `true` | guard: `none`
- words: dropped raw→final **0**, added **0**
- decode 12.3 s, transform 32.5 s

**the transcript the app stored when he dictated it**

```text
Ok, więc teraz muszę przez dwie minuty coś dyktować w języku polskim. Będzie to długi tekst. To na pewno. Nie wiem co by tutaj poczytać, bo nie mam nic pod ręką. Więc będę mówił wyłącznie o takich prostych rzeczach. Jak mój telefon, który leży na biurku. Klawiatura, myszka. I porozmawiamy trochę o rybkach. Przy czym jedna wygląda na lekko chorą. Chyba do gorywa. Tak to wygląda. Niestety ostatnie danio perłowe. Na te wszystkie dane perłowe były raczej marnego zdrowia. Z czterech ostał się jeden. Ledwo wszędzie. Na szczęście samce kupików całkiem nieźle sobie radzą. Więc im najwyraźniej nic nie grozi. Teraz delikatnie podkarmę je. Póki jeszcze lampka się nie świeci w akwarium. To kupiki nie powinny być takie aktywne w się jedzeniu. On jest tysał. Trochę powinno spać dla krewetek. To jest bardzo istotne. Jeżeli chodzi o to. Z takich mniej istotnych rzeczy. To teraz muszę dalej to nagrywać. No bo jednak coś tam musi się przetworzyć. I zobaczymy też w jaki sposób dłuższe teksty są obrabiane. Czego jestem bardzo ciekawy. Mam nadzieję, że to będzie moja wymarzona klawatura. Będę mógł odinstalować płatną wersję płatnego kuzyna Super Whispera. I zostaniemy tylko na Open Super Whisperze. Który ma najważniejsze dla mnie funkcje. Bo to, że on mi tam będzie formatował jako mail. To jest jakby niezbyt istotna funkcja. Sam jestem w stanie to zrobić. To nie jest coś, czego bardzo potrzebuję. No bo tylko sobie uszkodziłem jedną rękę. I drugą mam całkiem sprawną. Więc mogę dalej dyktować.
```

**raw — what the engine produced on this run**

```text
Ok, więc teraz muszę przez dwie minuty coś dyktować w języku polskim. Będzie to długi tekst. To na pewno. Nie wiem co by tutaj poczytać, bo nie mam nic pod ręką. Więc będę mówił wyłącznie o takich prostych rzeczach. Jak mój telefon, który leży na biurku. Klawiatura, myszka. I porozmawiamy trochę o rybkach. Przy czym jedna wygląda na lekko chorą. Chyba do gorywa. Tak to wygląda. Niestety ostatnie danio perłowe. Na te wszystkie dane perłowe były raczej marnego zdrowia. Z czterech ostał się jeden. Ledwo wszędzie. Na szczęście samce kupików całkiem nieźle sobie radzą. Więc im najwyraźniej nic nie grozi. Teraz delikatnie podkarmę je. Póki jeszcze lampka się nie świeci w akwarium. To kupiki nie powinny być takie aktywne w się jedzeniu. On jest tysał. Trochę powinno spać dla krewetek. To jest bardzo istotne. Jeżeli chodzi o to. Z takich mniej istotnych rzeczy. To teraz muszę dalej to nagrywać. No bo jednak coś tam musi się przetworzyć. I zobaczymy też w jaki sposób dłuższe teksty są obrabiane. Czego jestem bardzo ciekawy. Mam nadzieję, że to będzie moja wymarzona klawatura. Będę mógł odinstalować płatną wersję płatnego kuzyna Super Whispera. I zostaniemy tylko na Open Super Whisperze. Który ma najważniejsze dla mnie funkcje. Bo to, że on mi tam będzie formatował jako mail. To jest jakby niezbyt istotna funkcja. Sam jestem w stanie to zrobić. To nie jest coś, czego bardzo potrzebuję. No bo tylko sobie uszkodziłem jedną rękę. I drugą mam całkiem sprawną. Więc mogę dalej dyktować.
```

**cleaned — after the deterministic scrub**

```text
Ok, więc teraz muszę przez dwie minuty coś dyktować w języku polskim. Będzie to długi tekst. To na pewno. Nie wiem co by tutaj poczytać, bo nie mam nic pod ręką. Więc będę mówił wyłącznie o takich prostych rzeczach. Jak mój telefon, który leży na biurku. Klawiatura, myszka. I porozmawiamy trochę o rybkach. Przy czym jedna wygląda na lekko chorą. Chyba do gorywa. Tak to wygląda. Niestety ostatnie danio perłowe. Na te wszystkie dane perłowe były raczej marnego zdrowia. Z czterech ostał się jeden. Ledwo wszędzie. Na szczęście samce kupików całkiem nieźle sobie radzą. Więc im najwyraźniej nic nie grozi. Teraz delikatnie podkarmę je. Póki jeszcze lampka się nie świeci w akwarium. To kupiki nie powinny być takie aktywne w się jedzeniu. On jest tysał. Trochę powinno spać dla krewetek. To jest bardzo istotne. Jeżeli chodzi o to. Z takich mniej istotnych rzeczy. To teraz muszę dalej to nagrywać. No bo jednak coś tam musi się przetworzyć. I zobaczymy też w jaki sposób dłuższe teksty są obrabiane. Czego jestem bardzo ciekawy. Mam nadzieję, że to będzie moja wymarzona klawatura. Będę mógł odinstalować płatną wersję płatnego kuzyna Super Whispera. I zostaniemy tylko na Open Super Whisperze. Który ma najważniejsze dla mnie funkcje. Bo to, że on mi tam będzie formatował jako mail. To jest jakby niezbyt istotna funkcja. Sam jestem w stanie to zrobić. To nie jest coś, czego bardzo potrzebuję. No bo tylko sobie uszkodziłem jedną rękę. I drugą mam całkiem sprawną. Więc mogę dalej dyktować.
```

**final — what would have been pasted**

```text
Ok, więc teraz muszę przez dwie minuty coś dyktować w języku polskim. Będzie to długi tekst. To na pewno. Nie wiem, co by tutaj poczytać, bo nie mam nic pod ręką. Więc będę mówił wyłącznie o takich prostych rzeczach. Jak mój telefon, który leży na biurku. Klawiatura, myszka. I porozmawiamy trochę o rybkach. Przy czym jedna wygląda na lekko chorą. Chyba do gorywa. Tak to wygląda. Niestety, ostatnie danio perłowe. Na te wszystkie dane perłowe były raczej marnego zdrowia. Z czterech ostał się jeden. Ledwo wszędzie. Na szczęście samce kupików całkiem nieźle sobie radzą. Więc im najwyraźniej nic nie grozi. Teraz delikatnie podkarmę je. Póki jeszcze lampka się nie świeci w akwarium. To kupiki nie powinny być takie aktywne w się jedzeniu. On jest tysał. Trochę powinno spać dla krewetek. To jest bardzo istotne. Jeżeli chodzi o to. Z takich mniej istotnych rzeczy. To teraz muszę dalej to nagrywać. No bo jednak coś tam musi się przetworzyć. I zobaczymy też, w jaki sposób dłuższe teksty są obrabiane. Czego jestem bardzo ciekawy. Mam nadzieję, że to będzie moja wymarzona klawatura. Będę mógł odinstalować płatną wersję płatnego kuzyna Super Whispera. I zostaniemy tylko na Open Super Whisperze. Który ma najważniejsze dla mnie funkcje. Bo to, że on mi tam będzie formatował jako mail. To jest jakby niezbyt istotna funkcja. Sam jestem w stanie to zrobić. To nie jest coś, czego bardzo potrzebuję. No bo tylko sobie uszkodziłem jedną rękę. I drugą mam całkiem sprawną. Więc mogę dalej dyktować.
```

- scrub delta: `removed fillers 0 repetitions 0 annotations 0 | dropped 0 [] | added 0 []`
- model delta (cleaned→final): `dropped 0 [] | added 0 []`
- whole delta (raw→final): `dropped 0 [] | added 0 []`
- foreign tokens: ` (pl in): ["to", "To", "do", "to", "To", "On", "To", "to", "To", "to", "No", "to", "to", "on", "To", "to", "To", "No"]`
- **words that arrived from the other language: none** (derived: words the model added, carrying the other language's alphabet — the harness's own FOREIGN TOKENS line above scans the whole text and therefore counts Polish homographs like *to*, *do*, *on*, *no*, so it is not evidence on its own)

### 29EA0AEA-06B0-4FE1-B189-18A21822F35A.wav — 131.1 s — 2026-09-25 09:06:40.001

- engine language: `en` | gate: `en` | detector on the raw transcript: `en` | on the final text: `en` | flip: **no**
- policy: `English, neutral tone, clean-up` | model answered: `true` | guard: `none`
- words: dropped raw→final **0**, added **0**
- decode 11.3 s, transform 18.9 s

**the transcript the app stored when he dictated it**

```text
Okay, now I'm recording in English. So we can have some reference material. I will say something about my keyboard that is laying on my desk, about mouse, about the aquarium and the shrimps that are basically in them. There are two species of shrimps. Mono shrimp and the red cherry shrimp. Some guppies, a sick, danio, peruv danio. And there's also snails. I'm very proud of my own desk on this aquarium. Also, I have few stages. Of characters from the Friends sitcom laying on my monitor. Figurine of Alien. From Alien vs Predator also hanging from my monitor that I printed myself with my FDM printer. So I'm recording something pretty long. There is a traffic outside and today it's very cloudy. Yeah, very cloudy, not really pleasant and cold outside. And starting, yeah, fall is starting. So it's cold, it's wet. It's not pleasant to be outside. The leaves are falling off the trees. The grass is still green, but it will not take long to pretty much stop growing. So I sleep for a winter. So yeah, this is the longer recording that I'm recording to test the English transcription function. My wife is sitting next to me playing Heroes Might of Magic 3. And she is really pretty damn looking. She is like a hot one.
```

**raw — what the engine produced on this run**

```text
Okay, now I'm recording in English. So we can have some reference material. I will say something about my keyboard that is laying on my desk, about mouse, about the aquarium and the shrimps that are basically in them. There are two species of shrimps. Mono shrimp and the red cherry shrimp. Some guppies, a sick, danio, peruv danio. And there's also snails. I'm very proud of my own desk on this aquarium. Also, I have few stages. Of characters from the Friends sitcom laying on my monitor. Figurine of Alien. From Alien vs Predator also hanging from my monitor that I printed myself with my FDM printer. So I'm recording something pretty long. There is a traffic outside and today it's very cloudy. Yeah, very cloudy, not really pleasant and cold outside. And starting, yeah, fall is starting. So it's cold, it's wet. It's not pleasant to be outside. The leaves are falling off the trees. The grass is still green, but it will not take long to pretty much stop growing. So I sleep for a winter. So yeah, this is the longer recording that I'm recording to test the English transcription function. My wife is sitting next to me playing Heroes Might of Magic 3. And she is really pretty damn looking. She is like a hot one.
```

**cleaned — after the deterministic scrub**

```text
Okay, now I'm recording in English. So we can have some reference material. I will say something about my keyboard that is laying on my desk, about mouse, about the aquarium and the shrimps that are basically in them. There are two species of shrimps. Mono shrimp and the red cherry shrimp. Some guppies, a sick, danio, peruv danio. And there's also snails. I'm very proud of my own desk on this aquarium. Also, I have few stages. Of characters from the Friends sitcom laying on my monitor. Figurine of Alien. From Alien vs Predator also hanging from my monitor that I printed myself with my FDM printer. So I'm recording something pretty long. There is a traffic outside and today it's very cloudy. Yeah, very cloudy, not really pleasant and cold outside. And starting, yeah, fall is starting. So it's cold, it's wet. It's not pleasant to be outside. The leaves are falling off the trees. The grass is still green, but it will not take long to pretty much stop growing. So I sleep for a winter. So yeah, this is the longer recording that I'm recording to test the English transcription function. My wife is sitting next to me playing Heroes Might of Magic 3. And she is really pretty damn looking. She is like a hot one.
```

**final — what would have been pasted**

```text
Okay, now I'm recording in English. So we can have some reference material. I will say something about my keyboard that is laying on my desk, about mouse, about the aquarium and the shrimps that are basically in them. There are two species of shrimps. Mono shrimp and the red cherry shrimp. Some guppies, a sick, danio, peruv danio. And there's also snails. I'm very proud of my own desk on this aquarium. Also, I have few stages. Of characters from the Friends sitcom laying on my monitor. Figurine of Alien. From Alien vs Predator also hanging from my monitor that I printed myself with my FDM printer. So I'm recording something pretty long. There is a traffic outside and today it's very cloudy. Yeah, very cloudy, not really pleasant and cold outside. And starting, yeah, fall is starting. So it's cold, it's wet. It's not pleasant to be outside. The leaves are falling off the trees. The grass is still green, but it will not take long to pretty much stop growing. So I sleep for a winter. So yeah, this is the longer recording that I'm recording to test the English transcription function. My wife is sitting next to me playing Heroes Might of Magic 3. And she is really pretty damn looking. She is like a hot one.
```

- scrub delta: `removed fillers 0 repetitions 0 annotations 0 | dropped 0 [] | added 0 []`
- model delta (cleaned→final): `dropped 0 [] | added 0 []`
- whole delta (raw→final): `dropped 0 [] | added 0 []`
- foreign tokens: ` (en in): []`
- **words that arrived from the other language: none** (derived: words the model added, carrying the other language's alphabet — the harness's own FOREIGN TOKENS line above scans the whole text and therefore counts Polish homographs like *to*, *do*, *on*, *no*, so it is not evidence on its own)

### FD7B4C64-0AD7-4431-84D6-6F9EAFC77512.wav — 29.0 s — 2026-09-25 09:07:32.658

- engine language: `en` | gate: `en` | detector on the raw transcript: `en` | on the final text: `en` | flip: **no**
- policy: `English, neutral tone, clean-up` | model answered: `true` | guard: `none`
- words: dropped raw→final **0**, added **0**
- decode 2.9 s, transform 3.4 s

**the transcript the app stored when he dictated it**

```text
I check if my recordings are okay, if it's good to test with them.
```

**raw — what the engine produced on this run**

```text
I check if my recordings are okay, if it's good to test with them.
```

**cleaned — after the deterministic scrub**

```text
I check if my recordings are okay, if it's good to test with them.
```

**final — what would have been pasted**

```text
I check if my recordings are okay, if it's good to test with them.
```

- scrub delta: `removed fillers 0 repetitions 0 annotations 0 | dropped 0 [] | added 0 []`
- model delta (cleaned→final): `dropped 0 [] | added 0 []`
- whole delta (raw→final): `dropped 0 [] | added 0 []`
- foreign tokens: ` (en in): []`
- **words that arrived from the other language: none** (derived: words the model added, carrying the other language's alphabet — the harness's own FOREIGN TOKENS line above scans the whole text and therefore counts Polish homographs like *to*, *do*, *on*, *no*, so it is not evidence on its own)

## 2. The whole library, recording by recording

| # | when (UTC) | file | s | engine | raw | final | match | policy | ran | guard | dropped | added | flip |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 2026-09-25 09:03:01.310 | `9039BAB0-CBA2-49B2-82E1-432FF7B94589.wav` | 117.8 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 2 | 2026-09-25 09:06:40.001 | `29EA0AEA-06B0-4FE1-B189-18A21822F35A.wav` | 131.1 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 3 | 2026-09-25 09:07:32.658 | `FD7B4C64-0AD7-4431-84D6-6F9EAFC77512.wav` | 29.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 4 | 2026-09-23 13:02:48.869 | `8C6AE9CD-8A9A-4CE4-9C5B-FCD78614C1DA.wav` | 55.9 | pl | unknown | pl | yes | Polish, neutral tone, clean-up | true | none | 6 | 2 | **no** |
| 5 | 2026-09-23 13:03:56.460 | `F8B8FD9B-2D96-4F09-81AE-7C63A2FDE2D9.wav` | 6.6 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 6 | 2026-09-23 13:04:05.620 | `D09891A0-7D20-4A43-86C3-AF93EC9CE5A0.wav` | 5.8 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 4 | 0 | **no** |
| 7 | 2026-09-23 13:04:34.355 | `CB983C4C-B2F1-4852-AA42-5E88E6273D6A.wav` | 4.2 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 6 | 0 | **no** |
| 8 | 2026-09-23 13:05:03.972 | `E768C6B6-CFF6-423A-AA5B-CCEB459DC694.wav` | 4.1 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 9 | 2026-09-23 13:05:13.093 | `7982916A-1DF9-46EF-A69B-A06E1AEFD5B6.wav` | 4.2 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 10 | 2026-09-23 13:05:24.989 | `8BF93E24-77F8-4F88-BB9B-9E908308CEC5.wav` | 4.9 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 5 | 0 | **no** |
| 11 | 2026-09-23 13:08:13.520 | `737B7767-5563-47B8-B3BB-5EEC8A628F7D.wav` | 16.8 | en | unknown | unknown | no | English, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 12 | 2026-09-23 13:08:29.604 | `0D5AA205-7FC2-4F53-AA7B-C2E17A3A33B6.wav` | 2.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 13 | 2026-09-23 13:08:40.747 | `7DE55EF3-3187-4D4A-8ABE-8368FEBE01D3.wav` | 7.3 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 14 | 2026-09-23 13:08:53.976 | `D8579DB2-6CE5-49CE-9155-6F60834CAD9F.wav` | 3.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 15 | 2026-09-23 13:09:10.063 | `DFBAFE0D-DD94-4ADE-819D-F914EA18FB86.wav` | 6.6 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 16 | 2026-09-23 13:09:18.132 | `07D414C8-D3D9-4CE2-8B3B-9CCFC5F23A25.wav` | 4.5 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 17 | 2026-09-23 13:11:19.856 | `3880A6AD-6CA3-4198-888F-BC4492034169.wav` | 3.2 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 18 | 2026-09-23 13:11:34.033 | `B67BC3EC-1AB0-48B7-8998-BEB7B4EEE5E2.wav` | 5.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 19 | 2026-09-23 17:29:09.469 | `20594DC7-489A-494E-ACCC-4D8ED151A01D.wav` | 5.0 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 20 | 2026-09-23 17:29:17.200 | `ACDC9B38-16AC-4512-BB76-0D1AB436FBFD.wav` | 2.4 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 21 | 2026-09-23 17:29:45.874 | `369C2074-CDB1-4AC4-BBB5-A47239B71C94.wav` | 1.8 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 22 | 2026-09-23 17:30:00.376 | `4B614AE1-E769-4776-859E-1BD969B3F8E2.wav` | 2.5 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 23 | 2026-09-23 17:30:09.372 | `8F9F9F94-CE6A-4CA4-8E71-1ABC4BD5462D.wav` | 2.8 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 24 | 2026-09-23 17:30:17.981 | `3DB73D67-251B-4E8F-9057-814D9423CE2F.wav` | 5.2 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 25 | 2026-09-23 17:30:27.578 | `CB5FB432-3D32-460C-83EC-0B862495DE27.wav` | 7.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 26 | 2026-09-23 17:32:41.453 | `58D13F1F-7A39-4622-AB05-5D4068AB867D.wav` | 3.2 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 27 | 2026-09-24 09:05:08.211 | `FDCE39F7-48F7-48A3-A85E-0E55A1B1087C.wav` | 3.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 28 | 2026-09-24 09:05:15.322 | `EA4AE368-6639-431B-85A9-9FA44FFFF6E9.wav` | 2.9 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 29 | 2026-09-24 09:05:32.569 | `DC187FEA-7E34-4EA3-A8A7-D38482BCD2B5.wav` | 1.8 | pl | unknown | unknown | no | Polish, neutral tone, clean-up | true | none | 0 | 2 | **no** |
| 30 | 2026-09-24 09:08:10.108 | `44D378F5-C3AA-4EA6-B904-DE677A2A8D3E.wav` | 1.3 | ru | unknown | unknown | no | none | false | none | 0 | 0 | **no** |
| 31 | 2026-09-24 09:08:16.429 | `FBA76318-617C-47E4-AE5C-CB8BFB8AD66C.wav` | 2.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 32 | 2026-09-24 09:08:22.063 | `F5201D71-1EFD-4257-8553-62A0E7E99991.wav` | 2.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 33 | 2026-09-24 09:15:24.848 | `04C6FA9C-1C82-4DAC-B2B1-E63E22E78A7B.wav` | 4.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 34 | 2026-09-24 09:16:08.729 | `6BF473E5-C9D6-413C-AB7F-F81B9E5CEC08.wav` | 1.3 | en | unknown | unknown | no | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 35 | 2026-09-24 09:16:19.089 | `84579AFC-DD0C-4F39-8B9F-1E8CB7403F79.wav` | 2.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 36 | 2026-09-24 09:34:15.613 | `58E8C9C3-576B-43DA-8019-E360250AA232.wav` | 3.9 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 37 | 2026-09-24 09:51:37.335 | `3F281183-2585-4FDE-941C-DCCC18ADDE07.wav` | 2.2 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 38 | 2026-09-24 09:53:34.940 | `DE9093AC-17EA-4286-A7DC-AF1DF3F8881C.wav` | 2.7 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 39 | 2026-09-24 09:54:00.224 | `BBE968B1-9218-4035-93A7-EB2AC9CD4045.wav` | 2.8 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 40 | 2026-09-24 13:57:22.570 | `33E54ED5-6D1D-4EBB-A9E8-FBB7C655B426.wav` | 4.1 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 41 | 2026-09-25 05:30:45.008 | `8A3495F7-2F39-4747-9A6A-83EC2FE25E60.wav` | 3.9 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 42 | 2026-09-25 05:31:01.975 | `1C265C78-A4FF-43E3-963B-034B71D8DD36.wav` | 5.0 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 43 | 2026-09-25 05:31:45.803 | `AFD26284-90AD-42AE-B611-1AB2B7055C19.wav` | 26.5 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 0 | **no** |
| 44 | 2026-09-25 05:32:25.830 | `6A8A70E0-0EC2-4D41-9846-9D908A2A82E2.wav` | 4.5 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 45 | 2026-09-25 05:33:32.314 | `5C68BFAC-5EC8-45CC-8239-3B5659272C1A.wav` | 12.1 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 46 | 2026-09-25 05:38:47.148 | `0A7B9345-1A70-46CC-8370-0A423D0738E2.wav` | 5.7 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 47 | 2026-09-25 05:40:24.082 | `7F754FC2-3C5E-413F-A62F-5F7D42F0BE39.wav` | 16.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 0 | **no** |
| 48 | 2026-09-25 05:43:45.882 | `B1C7319C-2AF4-444E-A33E-F41AEB564C1E.wav` | 6.3 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 49 | 2026-09-25 05:47:35.952 | `B2EA9010-97C9-40AB-A7A2-746323A45297.wav` | 23.3 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 50 | 2026-09-25 05:48:44.577 | `D92A0B10-EB8D-4D47-80B9-A9F3A88C112F.wav` | 33.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 51 | 2026-09-25 05:49:09.143 | `0C0BB509-AB63-47C2-ACEC-294B1330AE9D.wav` | 4.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 52 | 2026-09-25 05:49:35.550 | `D3E5FB60-2C96-4534-BB40-A6871E6C3F4D.wav` | 14.1 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 53 | 2026-09-25 05:56:37.663 | `B8ABA45F-52F8-47AD-AEE9-204D03C11061.wav` | 10.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 54 | 2026-09-25 05:59:13.217 | `795074AD-6266-4FA8-87AE-30317867FF41.wav` | 27.2 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 55 | 2026-09-25 06:00:27.629 | `DE461E49-742B-4165-AF7B-65DB31A39AEB.wav` | 14.1 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 56 | 2026-09-25 06:00:58.468 | `AF2AB309-7EE4-47B1-B38B-A1C26F357865.wav` | 4.6 | en | pl | pl | no | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 57 | 2026-09-25 06:01:07.930 | `DEE9F67E-0432-4711-B66C-70702F5D6662.wav` | 2.6 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 58 | 2026-09-25 06:25:32.059 | `5F222575-8810-4742-B3B8-DCE3117481C8.wav` | 26.3 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 59 | 2026-09-25 06:26:01.765 | `98E3F31B-FA83-4FB9-A022-B0134C6E46FB.wav` | 6.6 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 60 | 2026-09-25 06:28:24.786 | `02FE5354-07AE-47E7-9C55-46B50BEEDC4D.wav` | 2.4 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 61 | 2026-09-25 06:28:37.714 | `2E44ECF5-7673-46F9-80D7-D51B4776A2C4.wav` | 2.2 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 62 | 2026-09-25 06:28:46.307 | `D75DF9D8-07C0-473C-AB8E-38C40D59EDD2.wav` | 2.4 | en | unknown | unknown | no | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 63 | 2026-09-25 06:28:54.402 | `1FBE27E3-333D-4C48-934E-FB36B32615B3.wav` | 2.5 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 64 | 2026-09-25 06:29:13.500 | `C487EA0D-FC88-4CD5-82D2-14DBD3533A65.wav` | 3.0 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 65 | 2026-09-25 06:59:24.495 | `CEE8B8D2-6BCC-41A7-B75C-8D1C442912AC.wav` | 5.3 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 66 | 2026-09-25 07:01:47.355 | `AAA66F70-4FF9-454A-875C-DDAF7E4FAE69.wav` | 7.7 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 67 | 2026-09-25 07:02:52.195 | `9568E84D-20BF-477E-AC68-E57056645CC4.wav` | 8.2 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 68 | 2026-09-25 07:03:29.494 | `F0BE688D-6EA9-4DE5-A700-69D89E597B8C.wav` | 13.7 | en | en | en | yes | English, neutral tone, clean-up | true | none | 1 | 2 | **no** |
| 69 | 2026-09-25 07:08:18.537 | `C456B7C8-97B8-4278-A5BD-9590B077F716.wav` | 3.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 70 | 2026-09-25 07:09:00.746 | `880D1B22-6A4C-4BD6-B718-06D01F55AEBD.wav` | 1.9 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 71 | 2026-09-25 07:10:48.957 | `1A9E80B4-A561-4FF5-B8E8-D89A8C60AED1.wav` | 4.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 72 | 2026-09-25 07:13:53.727 | `2E1C982B-D7C3-47EA-9C3F-6C435907E3A1.wav` | 1.1 | en | unknown | unknown | no | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 73 | 2026-09-25 07:23:53.558 | `25E06FCE-8A3C-43B9-80BE-15BF3B2FF515.wav` | 4.7 | en | en | en | yes | English, neutral tone, clean-up | true | none | 2 | 1 | **no** |
| 74 | 2026-09-25 07:29:03.237 | `D4A3E9D4-1960-4238-80F3-1D00E3D8F7C9.wav` | 3.5 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 75 | 2026-09-25 07:35:10.264 | `CECAAF27-9F1E-4A3A-A272-697F833EDFD2.wav` | 2.9 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 1 | **no** |
| 76 | 2026-09-25 07:36:45.040 | `1F71B87C-CEF9-4C83-8513-A966FE24F3FB.wav` | 4.4 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 77 | 2026-09-25 07:36:58.404 | `A462D8A6-FD35-4D8A-8186-815D4AAEFCD5.wav` | 3.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 78 | 2026-09-25 07:37:21.247 | `28F9ADC4-6026-415D-8A6B-27223805C7DB.wav` | 1.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 79 | 2026-09-25 07:46:00.528 | `68AFDB3F-4F57-4FDC-A80C-1F2248A6ED81.wav` | 2.1 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 80 | 2026-09-25 07:47:42.622 | `5BEEBA91-297A-4945-ABBD-916E4BDD5E09.wav` | 10.2 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 81 | 2026-09-25 07:58:08.994 | `81B50264-1B06-4D5A-95BA-1A88821B90CC.wav` | 2.5 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 2 | **no** |
| 82 | 2026-09-25 08:04:21.633 | `74326DBE-4FF9-4B46-8749-954536447FC5.wav` | 2.0 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 83 | 2026-09-25 08:14:01.032 | `6C341398-3355-4949-9905-2D36E82D8A67.wav` | 2.2 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 84 | 2026-09-25 08:35:35.498 | `2E8405CC-ED43-4021-BF22-9CF8321A9584.wav` | 8.8 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 1 | 1 | **no** |
| 85 | 2026-09-25 08:36:40.557 | `6AAFDC20-C276-41F4-94BE-919C259A570F.wav` | 20.6 | pl | pl | pl | yes | Polish, neutral tone, clean-up | true | none | 2 | 2 | **no** |
| 86 | 2026-09-25 08:39:18.112 | `B9F27354-458C-411A-9BD1-B041670BE72B.wav` | 2.9 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |
| 87 | 2026-09-25 09:10:15.394 | `EECE4B5C-F48A-4B20-9C93-CE434F38166C.wav` | 3.8 | en | en | en | yes | English, neutral tone, clean-up | true | none | 0 | 0 | **no** |

### Aggregates

- recordings measured: **87** of 87 blocks in the log
- transform model answered: **86** of 87
- **language flips: 0**
- final language != input language: **7**
- guard rejections: **0**
- dropped words raw→final, all recordings: **36**
- added words raw→final, all recordings: **26**

## 3. Output language vs input language — every recording that differs, quoted

`match = yes` means the app's own detector reads the final text as the language the engine heard. `no` means it does
not — which is either a real flip (raw verdict → final verdict, the `flip` column) or a text too short for the
detector to place at all (the honest "unknown"). Both are quoted below; nothing is rounded away.

For context, the engine heard `pl` on 27 recordings, `en` on 59 and `ru` on 1 across the library.

**input `en` → output `unknown` — 4 recording(s)**

- `737B7767-5563-47B8-B3BB-5EEC8A628F7D.wav` (16.8 s, raw detector `unknown`, flip `no`, policy `English, neutral tone, clean-up`)
  - raw: `I also can see keyboard simulation output.`
  - final: `I can also see keyboard simulation output.`
- `6BF473E5-C9D6-413C-AB7F-F81B9E5CEC08.wav` (1.3 s, raw detector `unknown`, flip `no`, policy `English, neutral tone, clean-up`)
  - raw: `commit tenders.`
  - final: `Commit tenders.`
- `D75DF9D8-07C0-473C-AB8E-38C40D59EDD2.wav` (2.4 s, raw detector `unknown`, flip `no`, policy `English, neutral tone, clean-up`)
  - raw: `weird as fuck`
  - final: `weird as fuck`
- `2E1C982B-D7C3-47EA-9C3F-6C435907E3A1.wav` (1.1 s, raw detector `unknown`, flip `no`, policy `English, neutral tone, clean-up`)
  - raw: `continue work.`
  - final: `Continue work.`

**input `en` → output `pl` — 1 recording(s)**

- `AF2AB309-7EE4-47B1-B38B-A1C26F357865.wav` (4.6 s, raw detector `pl`, flip `no`, policy `English, neutral tone, clean-up`)
  - raw: `I think peak hour starts, freeze.`
  - final: `I think peak hour starts, freeze.`

**input `pl` → output `unknown` — 1 recording(s)**

- `DC187FEA-7E34-4EA3-A8A7-D38482BCD2B5.wav` (1.8 s, raw detector `unknown`, flip `no`, policy `Polish, neutral tone, clean-up`)
  - raw: `font`
  - final: `<<<TRANSKRYPCJA ⏎ font ⏎ TRANSKRYPCJA>>>`

**input `ru` → output `unknown` — 1 recording(s)**

- `44D378F5-C3AA-4EA6-B904-DE677A2A8D3E.wav` (1.3 s, raw detector `unknown`, flip `no`, policy `none`)
  - raw: `Теперь собираем.`
  - final: `Теперь собираем.`

## 4. Language flips

A flip is counted only when the detector placed the **raw** transcript as Polish or English and places the **final**
text differently — i.e. the text changed language, not the detector failing to place a two-word dictation.

**None.** No tone answer was rejected in any of the 87 recordings, so there is no notice to quote: the guard never fired. What it did *not* catch is §8.

## 5. Guard rejections, with the notices

**None.** Every tone answer was accepted, so there is no notice to quote.

## 6. Words that arrived from the other language

A word is counted here only if it is **new to the text** (added by the model) *and* carries the other language's mark
— Polish diacritics for an English dictation, an English function word for a Polish one. Counting only new words is
what keeps homographs out: `to`, `do`, `on`, `no`, `i`, `w`, `z` are ordinary Polish words, so scanning the whole
final text with an English word list (which is what the harness's own `FOREIGN TOKENS` line does) flags the captain's
Polish rather than any translation. That line is kept in the raw evidence and is **not** evidence on its own.

**None.** No recording gained a word from the other language: not one final text carried a word that was both new to the text and marked with the other language's alphabet.

## 7. Everything the model changed in the cleaned text

- `8C6AE9CD-8A9A-4CE4-9C5B-FCD78614C1DA.wav` — model diff: `dropped 2 ["o", "translation"] | added 2 ["na", "tłumaczenie"]`; genuinely lost **2** ['o', 'translation'], genuinely new **2** ['na', 'tłumaczenie']
- `8BF93E24-77F8-4F88-BB9B-9E908308CEC5.wav` — model diff: `dropped 0 [] | added 1 ["Transkrypcja"]`; genuinely lost **0** [], genuinely new **1** ['transkrypcja']
- `737B7767-5563-47B8-B3BB-5EEC8A628F7D.wav` — model diff: `dropped 1 ["also"] | added 1 ["also"]`; genuinely lost **0** [], genuinely new **0** []  ← the ordered diff's one-drop-one-add pair is a move or a duplicate, not a loss
- `0D5AA205-7FC2-4F53-AA7B-C2E17A3A33B6.wav` — model diff: `dropped 0 [] | added 1 ["TRANSCRIPT"]`; genuinely lost **0** [], genuinely new **1** ['transcript']
- `7DE55EF3-3187-4D4A-8ABE-8368FEBE01D3.wav` — model diff: `dropped 1 ["m"] | added 1 ["am"]`; genuinely lost **1** ['m'], genuinely new **1** ['am']
- `4B614AE1-E769-4776-859E-1BD969B3F8E2.wav` — model diff: `dropped 0 [] | added 1 ["TRANSCRIPT"]`; genuinely lost **0** [], genuinely new **1** ['transcript']
- `CB5FB432-3D32-460C-83EC-0B862495DE27.wav` — model diff: `dropped 0 [] | added 1 ["the"]`; genuinely lost **0** [], genuinely new **1** ['the']
- `58D13F1F-7A39-4622-AB05-5D4068AB867D.wav` — model diff: `dropped 1 ["była"] | added 1 ["było"]`; genuinely lost **1** ['była'], genuinely new **1** ['było']
- `DC187FEA-7E34-4EA3-A8A7-D38482BCD2B5.wav` — model diff: `dropped 0 [] | added 2 ["TRANSKRYPCJA", "TRANSKRYPCJA"]`; genuinely lost **0** [], genuinely new **2** ['transkrypcja', 'transkrypcja']
- `04C6FA9C-1C82-4DAC-B2B1-E63E22E78A7B.wav` — model diff: `dropped 1 ["prod"] | added 1 ["product"]`; genuinely lost **1** ['prod'], genuinely new **1** ['product']
- `8A3495F7-2F39-4747-9A6A-83EC2FE25E60.wav` — model diff: `dropped 1 ["m"] | added 1 ["am"]`; genuinely lost **1** ['m'], genuinely new **1** ['am']
- `7F754FC2-3C5E-413F-A62F-5F7D42F0BE39.wav` — model diff: `dropped 1 ["the"] | added 0 []`; genuinely lost **1** ['the'], genuinely new **0** []
- `D92A0B10-EB8D-4D47-80B9-A9F3A88C112F.wav` — model diff: `dropped 0 [] | added 1 ["a"]`; genuinely lost **0** [], genuinely new **1** ['a']
- `D3E5FB60-2C96-4534-BB40-A6871E6C3F4D.wav` — model diff: `dropped 1 ["binded"] | added 1 ["bound"]`; genuinely lost **1** ['binded'], genuinely new **1** ['bound']
- `B8ABA45F-52F8-47AD-AEE9-204D03C11061.wav` — model diff: `dropped 0 [] | added 1 ["the"]`; genuinely lost **0** [], genuinely new **1** ['the']
- `795074AD-6266-4FA8-87AE-30317867FF41.wav` — model diff: `dropped 1 ["work"] | added 1 ["works"]`; genuinely lost **1** ['work'], genuinely new **1** ['works']
- `F0BE688D-6EA9-4DE5-A700-69D89E597B8C.wav` — model diff: `dropped 1 ["want"] | added 2 ["wants", "a"]`; genuinely lost **1** ['want'], genuinely new **2** ['a', 'wants']
- `880D1B22-6A4C-4BD6-B718-06D01F55AEBD.wav` — model diff: `dropped 0 [] | added 1 ["TRANSCRIPT"]`; genuinely lost **0** [], genuinely new **1** ['transcript']
- `25E06FCE-8A3C-43B9-80BE-15BF3B2FF515.wav` — model diff: `dropped 2 ["this", "ones"] | added 1 ["these"]`; genuinely lost **2** ['ones', 'this'], genuinely new **1** ['these']
- `CECAAF27-9F1E-4A3A-A272-697F833EDFD2.wav` — model diff: `dropped 0 [] | added 1 ["of"]`; genuinely lost **0** [], genuinely new **1** ['of']
- `81B50264-1B06-4D5A-95BA-1A88821B90CC.wav` — model diff: `dropped 0 [] | added 2 ["TRANSCRIPT", "TRANSCRIPT"]`; genuinely lost **0** [], genuinely new **2** ['transcript', 'transcript']
- `2E8405CC-ED43-4021-BF22-9CF8321A9584.wav` — model diff: `dropped 1 ["potestuję"] | added 1 ["poświęcę"]`; genuinely lost **1** ['potestuję'], genuinely new **1** ['poświęcę']
- `6AAFDC20-C276-41F4-94BE-919C259A570F.wav` — model diff: `dropped 2 ["chwileczkę", "zajebiaszczego"] | added 2 ["chwilkę", "zajebiścze"]`; genuinely lost **2** ['chwileczkę', 'zajebiaszczego'], genuinely new **2** ['chwilkę', 'zajebiścze']

## 8. A defect the guard does not catch: the transform's own prompt delimiter in the output

The composed user turn is `<<<TRANSCRIPT … TRANSCRIPT>>>` (the Polish word in the Polish prompt). On short
dictations the model sometimes returns that frame instead of, or around, the text — and the guard's rules
(assistant frame, label, stub, language flip) do not see it, so it reaches the pasted text. **Reported, not fixed**:
a fix is a separate decision.

- `0D5AA205-7FC2-4F53-AA7B-C2E17A3A33B6.wav` (2.8 s, engine `en`) — guard `none`, policy `English, neutral tone, clean-up`, delimiter seen: ['TRANSCRIPT']
  - raw: <redacted: captain dictation, 38 chars>
  - final: <redacted: captain dictation, 38 chars>   ⏎ TRANSCRIPT
  - verbatim:

    ```text
    <redacted: captain dictation, 38 chars>  
    TRANSCRIPT
    ```
- `4B614AE1-E769-4776-859E-1BD969B3F8E2.wav` (2.5 s, engine `en`) — guard `none`, policy `English, neutral tone, clean-up`, delimiter seen: ['TRANSCRIPT']
  - raw: Now speaking English
  - final: Now speaking English ⏎ TRANSCRIPT
  - verbatim:

    ```text
    Now speaking English
    TRANSCRIPT
    ```
- `DC187FEA-7E34-4EA3-A8A7-D38482BCD2B5.wav` (1.8 s, engine `pl`) — guard `none`, policy `Polish, neutral tone, clean-up`, delimiter seen: ['TRANSKRYPCJA']
  - raw: font
  - final: <<<TRANSKRYPCJA ⏎ font ⏎ TRANSKRYPCJA>>>
  - verbatim:

    ```text
    <<<TRANSKRYPCJA
    font
    TRANSKRYPCJA>>>
    ```
- `880D1B22-6A4C-4BD6-B718-06D01F55AEBD.wav` (1.9 s, engine `en`) — guard `none`, policy `English, neutral tone, clean-up`, delimiter seen: ['TRANSCRIPT']
  - raw: Use of pickguard
  - final: Use of pickguard ⏎ TRANSCRIPT
  - verbatim:

    ```text
    Use of pickguard
    TRANSCRIPT
    ```
- `81B50264-1B06-4D5A-95BA-1A88821B90CC.wav` (2.5 s, engine `en`) — guard `none`, policy `English, neutral tone, clean-up`, delimiter seen: ['TRANSCRIPT']
  - raw: Continue with fixes.
  - final: <<<TRANSCRIPT ⏎ Continue with fixes. ⏎ TRANSCRIPT>>>
  - verbatim:

    ```text
    <<<TRANSCRIPT
    Continue with fixes.
    TRANSCRIPT>>>
    ```

## 9. His history, against this chain

The stored transcript belongs to whatever build wrote the row — it is not a ground truth for today's chain — but
where it disagrees, the direction is worth naming. `engine heard` is the whisper language measured on this run;
`history reads` is the app's own detector run over the text his library stored.

**engine language × the language of what his history stored**

| engine heard | history reads | recordings |
|---|---|---|
| `en` | `en` | 55 |
| `pl` | `en` | 14 |
| `pl` | `pl` | 12 |
| `en` | `unknown` | 3 |
| `en` | `pl` | 1 |
| `pl` | `unknown` | 1 |
| `ru` | `unknown` | 1 |

**his stored text is byte-identical to this run's raw transcript: 49 of 87**

- rows dictated today (2026-09-25): 50, of which reproduce byte-for-byte: 27
- older rows: 37, of which reproduce byte-for-byte: 22

**the speech is Polish and his history stored English**

- `8C6AE9CD-8A9A-4CE4-9C5B-FCD78614C1DA.wav` (55.9 s)
  - stored when he dictated it: `First test of translation. First test of translation. First test of translation. First test of translation. First test of translation. First test of translation. First test of translation.`
  - this run's raw decode: `Pierwszy test o translation. Pierwszy test o translation.`
  - this run's final text: `Pierwszy test na tłumaczenie.`
- `D09891A0-7D20-4A43-86C3-AF93EC9CE5A0.wav` (5.8 s)
  - stored when he dictated it: `Now a test in Polish language.`
  - this run's raw decode: `Teraz test w języku polskim, test w języku polskim.`
  - this run's final text: `Teraz test w języku polskim.`
- `CB983C4C-B2F1-4852-AA42-5E88E6273D6A.wav` (4.2 s)
  - stored when he dictated it: `Now I'm trying to record in Spanish language`
  - this run's raw decode: `Teraz próbuję nagrać w języku polskim, teraz próbuję nagrać w języku polskim.`
  - this run's final text: `Teraz próbuję nagrać w języku polskim.`
- `20594DC7-489A-494E-ACCC-4D8ED151A01D.wav` (5.0 s)
  - stored when he dictated it: `I'm gonna ask this to you. I asked about shit.`
  - this run's raw decode: `Teraz testuję. Raz, dwa, trzy.`
  - this run's final text: `Teraz testuję. Raz, dwa, trzy.`
- `ACDC9B38-16AC-4512-BB76-0D1AB436FBFD.wav` (2.4 s)
  - stored when he dictated it: `(speaking in foreign language)`
  - this run's raw decode: `Teraz testuję. Raz, dwa, trzy.`
  - this run's final text: `Teraz testuję. Raz, dwa, trzy.`
- `369C2074-CDB1-4AC4-BBB5-A47239B71C94.wav` (1.8 s)
  - stored when he dictated it: `(speaking in foreign language)`
  - this run's raw decode: `Teraz testuję. Raz, dwa, trzy.`
  - this run's final text: `Teraz testuję. Raz, dwa, trzy.`
- `8F9F9F94-CE6A-4CA4-8E71-1ABC4BD5462D.wav` (2.8 s)
  - stored when he dictated it: `This is the first time I have a photo school.`
  - this run's raw decode: `Teraz testuję po polsku.`
  - this run's final text: `Teraz testuję po polsku.`
- `3DB73D67-251B-4E8F-9057-814D9423CE2F.wav` (5.2 s)
  - stored when he dictated it: `The rest history is now moving to the power of school, so we will be back in school.`
  - this run's raw decode: `Teraz testuję znowu, mówię po polsku, chcę, żeby było po angielsku.`
  - this run's final text: `Teraz testuję znowu, mówię po polsku, chcę, żeby było po angielsku.`
- `58D13F1F-7A39-4622-AB05-5D4068AB867D.wav` (3.2 s)
  - stored when he dictated it: `There are some people who are going to go to the airport.`
  - this run's raw decode: `Teraz mówię po polsku i chcę, żeby była po polsku.`
  - this run's final text: `Teraz mówię po polsku i chcę, żeby było po polsku.`
- `DE9093AC-17EA-4286-A7DC-AF1DF3F8881C.wav` (2.7 s)
  - stored when he dictated it: `I can do something to say in the background.`
  - this run's raw decode: `Mogę coś zarzucić z AI w tle.`
  - this run's final text: `Mogę coś zarzucić z AI w tle.`
- `BBE968B1-9218-4035-93A7-EB2AC9CD4045.wav` (2.8 s)
  - stored when he dictated it: `I can't let something go through the face.`
  - this run's raw decode: `Mogę coś zarzucić z ajaj w tle.`
  - this run's final text: `Mogę coś zarzucić z ajaj w tle.`
- `33E54ED5-6D1D-4EBB-A9E8-FBB7C655B426.wav` (4.1 s)
  - stored when he dictated it: `Now the simple thing is even clicking the mouse.`
  - this run's raw decode: `Teraz prosty test nawet kliknięcie myszką`
  - this run's final text: `Teraz prosty test – nawet kliknięcie myszką`
- `6A8A70E0-0EC2-4D41-9846-9D908A2A82E2.wav` (4.5 s)
  - stored when he dictated it: `Ok, now a quick text in the window.`
  - this run's raw decode: `Dobra, teraz szybki treścik w oknie.`
  - this run's final text: `Dobra, teraz szybki treścik w oknie.`
- `C487EA0D-FC88-4CD5-82D2-14DBD3533A65.wav` (3.0 s)
  - stored when he dictated it: `Ok, it's a weird thing.`
  - this run's raw decode: `Dobra, to jest mega dziwne.`
  - this run's final text: `Dobra, to jest mega dziwne.`

## 10. Recordings the two properties do not speak to

- `44D378F5-C3AA-4EA6-B904-DE677A2A8D3E.wav` (1.3 s): the engine measured `ru` for this clip, so the gate resolved `none` and the text was pasted as the engine wrote it: Теперь собираем.

## 11. Recordings worth the captain's ear

Short, mechanical, and in his own interest: anything where the guard rejected an answer, where the output language
does not read as the input language, where a word was genuinely lost or newly invented, or where a word arrived from
the other language.

- `8C6AE9CD-8A9A-4CE4-9C5B-FCD78614C1DA.wav` (55.9 s, engine `pl`) — the deterministic clean-up removed ['o', 'pierwszy', 'test', 'translation']; the model changed words: lost ['o', 'translation'], new ['na', 'tłumaczenie'] (diff `dropped 2 ["o", "translation"] | added 2 ["na", "tłumaczenie"]`)
- `D09891A0-7D20-4A43-86C3-AF93EC9CE5A0.wav` (5.8 s, engine `pl`) — the deterministic clean-up removed ['języku', 'polskim', 'test', 'w']
- `CB983C4C-B2F1-4852-AA42-5E88E6273D6A.wav` (4.2 s, engine `pl`) — the deterministic clean-up removed ['języku', 'nagrać', 'polskim', 'próbuję', 'teraz', 'w']
- `8BF93E24-77F8-4F88-BB9B-9E908308CEC5.wav` (4.9 s, engine `pl`) — the deterministic clean-up removed ['jeszcze', 'języku', 'polskim', 'raz', 'transkrypcja', 'w']; the model changed words: lost [], new ['transkrypcja'] (diff `dropped 0 [] | added 1 ["Transkrypcja"]`)
- `737B7767-5563-47B8-B3BB-5EEC8A628F7D.wav` (16.8 s, engine `en`) — the detector cannot place the final text at all (input was `en`) — short text, not a flip
- `0D5AA205-7FC2-4F53-AA7B-C2E17A3A33B6.wav` (2.8 s, engine `en`) — the model changed words: lost [], new ['transcript'] (diff `dropped 0 [] | added 1 ["TRANSCRIPT"]`)
- `7DE55EF3-3187-4D4A-8ABE-8368FEBE01D3.wav` (7.3 s, engine `en`) — the model changed words: lost ['m'], new ['am'] (diff `dropped 1 ["m"] | added 1 ["am"]`)
- `4B614AE1-E769-4776-859E-1BD969B3F8E2.wav` (2.5 s, engine `en`) — the model changed words: lost [], new ['transcript'] (diff `dropped 0 [] | added 1 ["TRANSCRIPT"]`)
- `CB5FB432-3D32-460C-83EC-0B862495DE27.wav` (7.8 s, engine `en`) — the model changed words: lost [], new ['the'] (diff `dropped 0 [] | added 1 ["the"]`)
- `58D13F1F-7A39-4622-AB05-5D4068AB867D.wav` (3.2 s, engine `pl`) — the model changed words: lost ['była'], new ['było'] (diff `dropped 1 ["była"] | added 1 ["było"]`)
- `DC187FEA-7E34-4EA3-A8A7-D38482BCD2B5.wav` (1.8 s, engine `pl`) — the detector cannot place the final text at all (input was `pl`) — short text, not a flip; the model changed words: lost [], new ['transkrypcja', 'transkrypcja'] (diff `dropped 0 [] | added 2 ["TRANSKRYPCJA", "TRANSKRYPCJA"]`)
- `44D378F5-C3AA-4EA6-B904-DE677A2A8D3E.wav` (1.3 s, engine `ru`) — the detector cannot place the final text at all (input was `ru`) — short text, not a flip
- `04C6FA9C-1C82-4DAC-B2B1-E63E22E78A7B.wav` (4.8 s, engine `en`) — the model changed words: lost ['prod'], new ['product'] (diff `dropped 1 ["prod"] | added 1 ["product"]`)
- `6BF473E5-C9D6-413C-AB7F-F81B9E5CEC08.wav` (1.3 s, engine `en`) — the detector cannot place the final text at all (input was `en`) — short text, not a flip
- `8A3495F7-2F39-4747-9A6A-83EC2FE25E60.wav` (3.9 s, engine `en`) — the model changed words: lost ['m'], new ['am'] (diff `dropped 1 ["m"] | added 1 ["am"]`)
- `AFD26284-90AD-42AE-B611-1AB2B7055C19.wav` (26.5 s, engine `en`) — the deterministic clean-up removed ['mmm']
- `7F754FC2-3C5E-413F-A62F-5F7D42F0BE39.wav` (16.8 s, engine `en`) — the model changed words: lost ['the'], new [] (diff `dropped 1 ["the"] | added 0 []`)
- `D92A0B10-EB8D-4D47-80B9-A9F3A88C112F.wav` (33.0 s, engine `en`) — the model changed words: lost [], new ['a'] (diff `dropped 0 [] | added 1 ["a"]`)
- `D3E5FB60-2C96-4534-BB40-A6871E6C3F4D.wav` (14.1 s, engine `en`) — the model changed words: lost ['binded'], new ['bound'] (diff `dropped 1 ["binded"] | added 1 ["bound"]`)
- `B8ABA45F-52F8-47AD-AEE9-204D03C11061.wav` (10.0 s, engine `en`) — the model changed words: lost [], new ['the'] (diff `dropped 0 [] | added 1 ["the"]`)
- `795074AD-6266-4FA8-87AE-30317867FF41.wav` (27.2 s, engine `en`) — the model changed words: lost ['work'], new ['works'] (diff `dropped 1 ["work"] | added 1 ["works"]`)
- `AF2AB309-7EE4-47B1-B38B-A1C26F357865.wav` (4.6 s, engine `en`) — the detector places the final text as `pl` where the engine heard `en` (the gate used the engine's verdict)
- `D75DF9D8-07C0-473C-AB8E-38C40D59EDD2.wav` (2.4 s, engine `en`) — the detector cannot place the final text at all (input was `en`) — short text, not a flip
- `F0BE688D-6EA9-4DE5-A700-69D89E597B8C.wav` (13.7 s, engine `en`) — the model changed words: lost ['want'], new ['a', 'wants'] (diff `dropped 1 ["want"] | added 2 ["wants", "a"]`)
- `880D1B22-6A4C-4BD6-B718-06D01F55AEBD.wav` (1.9 s, engine `en`) — the model changed words: lost [], new ['transcript'] (diff `dropped 0 [] | added 1 ["TRANSCRIPT"]`)
- `2E1C982B-D7C3-47EA-9C3F-6C435907E3A1.wav` (1.1 s, engine `en`) — the detector cannot place the final text at all (input was `en`) — short text, not a flip
- `25E06FCE-8A3C-43B9-80BE-15BF3B2FF515.wav` (4.7 s, engine `en`) — the model changed words: lost ['ones', 'this'], new ['these'] (diff `dropped 2 ["this", "ones"] | added 1 ["these"]`)
- `CECAAF27-9F1E-4A3A-A272-697F833EDFD2.wav` (2.9 s, engine `en`) — the model changed words: lost [], new ['of'] (diff `dropped 0 [] | added 1 ["of"]`)
- `81B50264-1B06-4D5A-95BA-1A88821B90CC.wav` (2.5 s, engine `en`) — the model changed words: lost [], new ['transcript', 'transcript'] (diff `dropped 0 [] | added 2 ["TRANSCRIPT", "TRANSCRIPT"]`)
- `2E8405CC-ED43-4021-BF22-9CF8321A9584.wav` (8.8 s, engine `pl`) — the model changed words: lost ['potestuję'], new ['poświęcę'] (diff `dropped 1 ["potestuję"] | added 1 ["poświęcę"]`)
- `6AAFDC20-C276-41F4-94BE-919C259A570F.wav` (20.6 s, engine `pl`) — the model changed words: lost ['chwileczkę', 'zajebiaszczego'], new ['chwilkę', 'zajebiścze'] (diff `dropped 2 ["chwileczkę", "zajebiaszczego"] | added 2 ["chwilkę", "zajebiścze"]`)

## What remains unverified

- **Sense fidelity has no measurement here.** The word account can say a word arrived that he did not say, and that
  one of his did not arrive; it cannot say whether a delivered sentence still means what he meant. There is no
  ground-truth transcript for any of these clips, so "the words survived" is measured against the engine's own raw
  decode, not against what he actually uttered. His ears are the instrument.
- **The five `.wav` files in the recordings directory with no row in `recordings.sqlite`** —
  `4CFAD7A4-4679-415F-956B-8E1756A6F599.wav`, `5B18F491-7407-45B5-98BD-9684E702B17A.wav`,
  `682A0043-CAF0-4EB4-B797-88762015973A.wav`, `CCBDED21-3BBF-4D30-BE73-C115EA1558C1.wav`,
  `D3B1C7FB-90E6-44F3-B7B4-4C57360B8073.wav` — are **not** part of the library and were **not** decoded. Each is
  4 bytes of `01 02 03 04`: a sentinel, not audio, so there is nothing to decode. They are named here rather than
  dropped.
- **The stored transcript is not the raw transcript of this run, by design.** History keeps what the engine produced
  when he dictated; this run re-decoded the audio. Where the two differ, the difference belongs to the decode, not to
  the transform — the run's own `raw` line is the baseline every delta is taken against.
- **Per-recording coverage.** The run's own summary, verbatim: `processed 87 of 87 | skipped for budget 0 |
  undecodable 0 | anchors processed 3/3 | elapsed 549.4 s`, then `audio 862.1 s | decode 212.4 s | transform 336.7 s`.
  **No recording was skipped and none failed to decode** — nothing was silently sampled, and there is no skipped file
  to name. The engine heard `pl` on 27 recordings, `en` on 59 and `ru` on 1. The clips the detector could not place at
  all are named in §3, and every one of them is 1.1–16.8 s long.
- **The one call that did not run is not a failure.** The single `didRunModel = false` row is the 1.3 s Russian clip
  (`44D378F5`): `TransformPolicy.resolve` returns nothing for a language that is neither Polish nor English, so no
  model was asked and the transcript was pasted as the engine wrote it. That is the designed behaviour, and it is
  named here so the count is not read as a broken call.

## What this measurement cannot settle

The language property is decided by the app's own code (engine language, then `LanguageDetector`) and is reported
here as it happens — but the detector is a heuristic by construction, and for a two-word dictation it is documented
as a coin flip. A "yes" in the table above therefore means *the app agreed with itself*; it is not a certificate about
the audio. The recordings with the most to gain from a human ear are listed in §11.
