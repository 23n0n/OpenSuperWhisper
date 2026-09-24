# fm-20260923-06 — Is Desert Ant Labs' **Ear** usable for this app?

**Question (captain, verbatim):** "https://desertant.com/models/ear/ check if you can use this model."

**Scope of this scout:** whether the *Ear* spoken-language detector is usable here, with measurements.
The *gate* design (what the app does with a detected language) belongs to `fm-20260923-04` and is not
touched here. Read-only: no branch, no commit, nothing under
`/Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo` was modified. All work in `/tmp`.

---

## 0. Verdict in one paragraph

**Yes, it builds and runs here, and it is small and fast — but it is only usable for recordings of
about ten seconds and longer.** On this machine's own real dictation recordings Ear was perfect at
10-30 s (37/37) and ≥30 s (3/3), 91.4% at 5-10 s, 74.2% at 2-5 s and 40% below 2 s. Dictation clips
are 2-10 s, and in that band Ear scored **83.3% with 6.1% of clips *confidently wrong*** — wrong while
`isReliable == true`, i.e. wrong in a way a routing gate cannot detect. The free alternative already
inside the app does better in exactly that band: whisper.cpp's own detection on the same 111 clips
scored **93.7% overall vs Ear's 87.4%, and 93.5% vs 74.2% at 2-5 s**. Ear also cannot meet the plan's
"no external requests" criterion: each `identify` records a usage call that the SDK POSTs to
`events.desertant.com` — captured live against the production endpoint, HTTP 202 — and the licence
forbids switching that reporting off.

**If the honest answer must be one line: usable only for long recordings, not for dictation.**

---

## 1. What was run, where

| | |
|---|---|
| Machine | Apple M4, 32 GB, macOS 27.0 (build 26A428), arm64 |
| Toolchain | Apple Swift 6.4 (swiftlang-6.4.0.34.1), `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` |
| Probe package | `/tmp/ear-probe` (throwaway SwiftPM executable `earprobe`) |
| SDK | `https://github.com/Desert-Ant-Labs/desert-ant-core.git`, `from: "3.1.0"` |
| Whisper harness | `/tmp/whisper-build/bin/whisper-cli`, built out-of-tree from the fork's `libwhisper/whisper.cpp` |
| Model for whisper | the app's own `~/Library/Application Support/superwhisper/ggml-large-v3-turbo.bin` (1.62 GB) |
| Raw data | `/tmp/ear-probe/ear-results.jsonl`, `ear-noisy.jsonl`, `ear-real.jsonl`, `whisper-results.tsv`, `report_rows.json`, `ingest.log` |

No subagents were spawned (delegation guard).

---

## 2. Can it run here at all? — yes

```
cd /tmp/ear-probe
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build -c release
```

`Package.swift` of the probe:

```swift
// swift-tools-version: 6.2
let package = Package(
    name: "earprobe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git", from: "3.1.0"),
    ],
    targets: [
        .executableTarget(name: "earprobe",
            dependencies: [.product(name: "Ear", package: "desert-ant-core")]),
    ]
)
```

**Resolved version: `3.3.1`** (revision `7e9107f47d8f2c56fbd5a1b93bae637f1c92a92c`), plus transitive
`swift-numerics 1.1.1`. `from: "3.1.0"` resolves up to the newest 3.x, so the pinned manifest version
became 3.3.1 — the SDK's own `EarModel.sdkVersion` in that checkout is also `3.3.1`. The package
declares `platforms: [.iOS(.v17), .macOS(.v14), .tvOS(.v16), .visionOS(.v1)]`.

The first full build took ~20 s; `Build complete! (1.72 secs)` on the rebuild. **The SDK itself
compiled with no errors or warnings of its own.** One failure occurred, and it was in *my* probe code,
not the SDK — recorded verbatim for honesty:

```
/private/tmp/ear-probe/Sources/earprobe/main.swift:48:45: error: mutation of captured var 'lastProgress'
in concurrently-executing code [#SendableClosureCaptures]
```

Fixed by boxing the progress callback. Run form:

```
./.build/release/earprobe identify <file.wav> ...      # prints one JSON object per clip
./.build/release/earprobe --dir <path> download        # fetches/prepares weights
./.build/release/earprobe --dir <path> load            # forces the model to load, timed
./.build/release/earprobe --windows <n> identify ...   # override the window count
```

`supportedLanguages()` → **99 codes**, including `pl` and `en` (read from `languages.json` in the
weights, not from the web page).

---

## 3. Weights and offline shipping

**Where the first-use download lands.** The managed layout is
`<Caches>/desert-ant-models/<repo>/<revision>` (`Sources/ModelStore/ModelStore.swift:41`); for Ear that
is:

```
~/Library/Caches/desert-ant-models/desert-ant-labs/ear/v0.1.0/
  ear.mlmodelc/            (compiled Core ML program: weights/weight.bin, model.mil, coremldata.bin, analytics/)
  languages.json  ear_meta.json  mel_filters.f32  .dal-meta/manifest
```

**Caveat on the "first-use" measurement:** that directory already existed, timestamped **11:14 today,
before this session** — an earlier session on this machine had already fetched it. So my first
`download` call was a cache hit (1.43 s, `isDownloaded` already true). A *genuine* first download was
measured into a fresh explicit directory instead:

```
rm -rf /tmp/ear-fresh && ./.build/release/earprobe --dir /tmp/ear-fresh download
  -> {"event":"download","finalProgress":1,"isDownloaded":true,"seconds":6.195}   (network, wifi)
```

**Size: 13,895,166 bytes = 13.25 MiB / 13.90 MB** across 8 files. Breakdown: `weights/weight.bin`
13,696,070 · `model.mil` 128,922 · `mel_filters.f32` 64,328 · `ear_meta.json` 3,894 ·
`.dal-meta/manifest` 745 · `languages.json` 595 · two `coremldata.bin` 369 + 243. The vendor's
"13.7 MB" matches.

**Does `Ear(directory:)` run offline from copied weights? — Yes, tested.** I copied the weights to
`/tmp/ear-offline` and ran the process with the network denied by the kernel sandbox:

```
cp -R /tmp/ear-fresh /tmp/ear-offline
sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  ./.build/release/earprobe --dir /tmp/ear-offline identify clips/wav/pla_30s.wav
  -> {"language":"pl","confidence":0.9827,"isReliable":true,"windows":1,
       "firstCallSeconds":1.433,"warmSeconds":[0.037],...}
```

Control, same sandbox, weights **absent** — proving the local check is real and there is no silent
fallback:

```
mkdir -p /tmp/ear-empty
sandbox-exec -p '(version 1)(allow default)(deny network*)' \
  ./.build/release/earprobe --dir /tmp/ear-empty identify clips/wav/pla_30s.wav
  -> {"error":"Error Domain=NSPOSIXErrorDomain Code=1 \"Operation not permitted\" ...
       \"_NSURLErrorNWPathKey=satisfied ...\"","errorType":"NSURLError",...}
```

**Can the app bundle the weights for a fully offline install? — Yes.** The SDK doc comment says
"Nothing is bundled with this package", and `Ear(directory:)` is documented as: *"If it already
contains the model (you pre-downloaded or shipped it there) it is used offline; otherwise the model is
downloaded into it."* The licence permits it explicitly — §2 grants the right to *"embed and
distribute them inside your application"*, and §6's restriction is only that you may not distribute
the models *"as a standalone product, model, SDK, or hosted service"*. Shipping the directory above as
an app resource and constructing `Ear(directory:)` with that path gives a fully offline install; the
only difference in that mode is that no download step exists at all (and `Ear.isDownloaded(directory:)`
can be used to gate a "download model" UI).

Two related cache paths the app will also get: the Neural Engine compile cache at
`~/Library/Caches/desertant/com.apple.e5rt.e5bundlecache` (22 MB, 16 entries), and the SDK note that
Core ML keys this cache on the compiled model's *path* — a bundled model inside the `.app` therefore
has a stable path and hits that cache.

---

## 4. The decisive measurement — accuracy at our clip lengths

### 4.1 Corpus

| set | how it was made | clips |
|---|---|---|
| synthetic clean | `say -v Zosia` (pl_PL) / `say -v Samantha` (en_US), 2 texts per language, trimmed with ffmpeg to 2 / 5 / 10 / 30 s at 16 kHz mono | 16 |
| synthetic noisy | the 2 / 5 / 10 s clips with white noise added at 25 dB and 15 dB SNR (stdlib `wave`+`array`, seeded) | 24 |
| synthetic ultra-short | one short phrase per language ("thank you very much" / "dziękuję bardzo" and "yes, of course" / "tak, oczywiście"), 1.29-1.66 s | 4 |
| **real dictation** | 111 of the 159 dictation recordings on this machine | 111 |

**On the real recordings.** The app under discussion has **no recordings of its own**:
`~/Library/Application Support/ru.starmel.OpenSuperWhisper/recordings` is empty and its
`recordings.sqlite` has 0 rows. The real clips therefore come from the *other* dictation app installed
on the same machine, `/Volumes/home/zenon/superwhisper/recordings/<id>/output.wav` — 159 folders of
16 kHz mono WAV plus `meta.json`, captured from an Anker PowerConf C200 USB mic. They were read **in
place**; nothing was copied off the machine and no transcript content is quoted anywhere in this
report. 111 of the 159 carry a confident language label:

- label = script classification of the app's *own stored transcript* (Polish diacritics + Polish vs
  English function words, requiring a 1.5× margin) — 74 English, 37 Polish;
- cross-checked against `meta.json`'s `languageSelected` (`en-UK` for 86, `auto` for 71, `en` for 2)
  and against whisper.cpp's independent detection;
- 48 excluded: 35 with no usable transcript (0 words), 7 ambiguous, 6 with no markers.

Duration spread of the 111 — this is what dictation actually looks like on this machine, and it is the
reason the 2-10 s band matters:

| <2 s | 2-5 s | 5-10 s | 10-30 s | ≥30 s | median |
|---|---|---|---|---|---|
| 5 | 31 | 35 | 37 | 3 | **6.96 s** |

### 4.2 The vendor's "single window under thirty seconds" warning — confirmed in code and at runtime

`Sources/Ear/Frontend.swift` `windowOffsets(_:count:)` returns `[0]` whenever
`samples.count <= geometry.windowSamples`, i.e. whenever the audio is 30 s or shorter, regardless of the
requested `windows` (default 3). Measured: **every one of the 44 synthetic clips and 109 of the 111 real
clips reported `windows == 1`**; the only exceptions were the two real recordings longer than 30 s
(2 and 3 windows). So for dictation the answer really is a single 30 s window padded with silence —
93% of the encoder input is silence padding for a 2 s clip (1 - 2/30).

### 4.3 Accuracy by clip length

**Synthetic, clean TTS**

| band | n | Ear correct | Ear acc | Ear `isReliable=false` | of those, top-1 correct | confidently wrong | whisper correct | Ear latency |
|---|---|---|---|---|---|---|---|---|
| 2-5s | 4 | 4/4 | 100.0% | 0 | 0 | 0 | 4/4 | 37-38 ms |
| 5-10s | 4 | 4/4 | 100.0% | 0 | 0 | 0 | 4/4 | 37-37 ms |
| 10-30s | 4 | 4/4 | 100.0% | 0 | 0 | 0 | 4/4 | 37-39 ms |
| >=30s | 4 | 4/4 | 100.0% | 0 | 0 | 0 | 4/4 | 37-38 ms |
| (all) | 16 | 16/16 | 100.0% | 0 | 0 | 0 | 16/16 | 37-39 ms |

**Synthetic, +white noise at 25 / 15 dB SNR**

| band | n | Ear correct | Ear acc | Ear `isReliable=false` | of those, top-1 correct | confidently wrong | whisper correct | Ear latency |
|---|---|---|---|---|---|---|---|---|
| 2-5s | 8 | 8/8 | 100.0% | 1 | 1 | 0 | 8/8 | 38-38 ms |
| 5-10s | 8 | 8/8 | 100.0% | 0 | 0 | 0 | 8/8 | 38-42 ms |
| 10-30s | 8 | 8/8 | 100.0% | 0 | 0 | 0 | 8/8 | 37-38 ms |
| (all) | 24 | 24/24 | 100.0% | 1 | 1 | 0 | 24/24 | 37-42 ms |

**Synthetic, ultra-short (<1.7 s)**

| band | n | Ear correct | Ear acc | Ear `isReliable=false` | of those, top-1 correct | confidently wrong | whisper correct | Ear latency |
|---|---|---|---|---|---|---|---|---|
| <2s | 4 | 4/4 | 100.0% | 1 | 1 | 0 | 4/4 | 38-40 ms |
| (all) | 4 | 4/4 | 100.0% | 1 | 1 | 0 | 4/4 | 38-40 ms |

**REAL DICTATION — 111 recordings of this machine**

| band | n | Ear correct | Ear acc | Ear `isReliable=false` | of those, top-1 correct | confidently wrong | whisper correct | Ear latency |
|---|---|---|---|---|---|---|---|---|
| <2s | 5 | 2/5 | 40.0% | 3 | 2 | 2 | 3/5 | 38-38 ms |
| 2-5s | 31 | 23/31 | 74.2% | 5 | 0 | 3 | 29/31 | 38-40 ms |
| 5-10s | 35 | 32/35 | 91.4% | 4 | 2 | 1 | 32/35 | 38-50 ms |
| 10-30s | 37 | 37/37 | 100.0% | 2 | 2 | 0 | 37/37 | 39-44 ms |
| >=30s | 3 | 3/3 | 100.0% | 0 | 0 | 0 | 3/3 | 39-123 ms |
| (all) | 111 | 97/111 | 87.4% | 14 | 6 | 6 | 104/111 | 38-123 ms |

**REAL DICTATION, audible only (peak ≥ 1000 of 32768; drops 2 near-silent clips)**

| band | n | Ear correct | Ear acc | Ear `isReliable=false` | of those, top-1 correct | confidently wrong | whisper correct | Ear latency |
|---|---|---|---|---|---|---|---|---|
| <2s | 4 | 2/4 | 50.0% | 3 | 2 | 1 | 2/4 | 38-38 ms |
| 2-5s | 30 | 23/30 | 76.7% | 4 | 0 | 3 | 28/30 | 38-40 ms |
| 5-10s | 35 | 32/35 | 91.4% | 4 | 2 | 1 | 32/35 | 38-50 ms |
| 10-30s | 37 | 37/37 | 100.0% | 2 | 2 | 0 | 37/37 | 39-44 ms |
| >=30s | 3 | 3/3 | 100.0% | 0 | 0 | 0 | 3/3 | 39-123 ms |
| (all) | 109 | 97/109 | 89.0% | 13 | 6 | 5 | 102/109 | 38-123 ms |

### 4.4 `isReliable == false`: how often, and would it have mis-routed?

Across all 155 clips, `isReliable` was false **16 times (10.3%)**; on the 111 real clips, **14 times
(12.6%)**. Of the 14 real clips Ear got wrong, **8 were flagged `isReliable == false`** — a gate that
routes only on reliable answers would have *declined* those, which is the safe outcome — and **6 were
wrong while `isReliable == true`**. Those six are the dangerous class: the answer looks routable and is
not.

The six confidently-wrong recordings, with their measured signal level:

| dur | truth | Ear said | confidence | margin | peak (of 32768) | rms |
|---|---|---|---|---|---|---|
| 1.28 s | en | ru | 0.631 | 0.524 | 11549 | 1292 |
| **1.89 s** | en | **tr** | **0.784** | 0.748 | **307** | **36** |
| 2.15 s | pl | cs | 0.408 | 0.325 | 13590 | 1587 |
| 3.11 s | pl | cs | 0.746 | 0.577 | 11961 | 1213 |
| 4.18 s | pl | en | 0.543 | 0.454 | 5137 | 590 |
| 6.01 s | en | cs | 0.461 | 0.307 | 9750 | 796 |

One of them is near-inaudible — peak 307 of 32768 (0.9% of full scale, ≈ -41 dBFS), rms 36: Ear has
**no VAD and no level normalisation**, so that 1.89 s clip is fed in at 0.9% amplitude and comes back
"Turkish, 0.784, reliable". A second near-silent failure (peak 518, 2.36 s, also English) was at least
flagged `isReliable == false`. The app's existing whisper path has a VAD and a `no_speech_thold` before
it ever reaches a model; a gate that runs Ear on raw mic buffers would not.

**So: an unreliable answer did *not* get routed in any of the 8 observed cases (it correctly declined),
but 6 answers that a gate *would* have routed were wrong.** In the 2-10 s band that is **4 confident
misroutes out of 66 clips = 6.1%** (7 of 66 = 10.6% under the pessimistic labelling in §4.6), on top of
a ~12% rate of "unreliable", which a gate has to have an answer for anyway.

### 4.5 Latency

Warm, per clip, in-process: **36.7-41.6 ms** for single-window clips (37 ms typical); 78 ms for a 2-window
and 123 ms for a 3-window recording. The vendor's "~250 ms per identification" was not reproduced — it
is faster here. The distribution is tight because the encoder always runs on a padded 30 s window, so
latency is essentially independent of clip length.

### 4.6 Honest caveat: 5 clips of unresolved ground truth

Five real recordings are labelled English (their stored transcript reads as English — 67-100% of its
tokens are common English words) while whisper.cpp calls them **Polish with p from 0.64 to 0.998**.
The speaker is a Polish first-language user, so **Polish-accented English** is the most likely
explanation; two of the five clips are also very quiet (peak 307 and 518 of 32768). There is no way to
settle it without listening to the clips, so here are both labelings:

| | Ear overall | Ear acc, 2-10 s | Ear confident-wrong, 2-10 s | whisper overall |
|---|---|---|---|---|
| as recorded (whisper is wrong on those 5) | 87.4% | 83.3% | 4 of 66 | 93.7% |
| those 5 relabelled Polish (my labels wrong) | 84.7% | 78.8% | 7 of 66 | 98.2% |

whisper.cpp leads in both. If accent is the cause, that is itself a finding for the gate: **accented
English may be classified as Polish**, and for this app that means English speech would be sent to the
Polish→English transform.

### 4.7 Per-clip raw values — synthetic sets

| clip | dur | truth | Ear | conf | margin | isReliable | Ear top-2 | Ear ms | whisper.cpp | whisper p |
|---|---|---|---|---|---|---|---|---|---|---|
| `ena_10s.wav` | 10.00 s | en | en | 0.993 | 0.992 | true | en 0.993, zh 0.001 | 39.1 | en | 0.9997 |
| `ena_2s.wav` | 2.00 s | en | en | 0.973 | 0.968 | true | en 0.973, la 0.004 | 38.2 | en | 0.9947 |
| `ena_30s.wav` | 30.00 s | en | en | 0.996 | 0.995 | true | en 0.996, zh 0.001 | 38.0 | en | 0.9999 |
| `ena_5s.wav` | 5.00 s | en | en | 0.987 | 0.985 | true | en 0.987, la 0.002 | 37.1 | en | 0.9994 |
| `enb_10s.wav` | 10.00 s | en | en | 0.989 | 0.987 | true | en 0.989, zh 0.002 | 37.0 | en | 0.9988 |
| `enb_2s.wav` | 2.00 s | en | en | 0.986 | 0.984 | true | en 0.986, cy 0.002 | 36.8 | en | 0.9993 |
| `enb_30s.wav` | 30.00 s | en | en | 0.997 | 0.996 | true | en 0.997, zh 0.001 | 36.8 | en | 0.9999 |
| `enb_5s.wav` | 5.00 s | en | en | 0.991 | 0.989 | true | en 0.991, zh 0.002 | 37.0 | en | 0.9996 |
| `pla_10s.wav` | 10.00 s | pl | pl | 0.928 | 0.899 | true | pl 0.928, ru 0.029 | 37.3 | pl | 0.9991 |
| `pla_2s.wav` | 2.00 s | pl | pl | 0.822 | 0.773 | true | pl 0.822, ja 0.049 | 36.8 | pl | 0.9985 |
| `pla_30s.wav` | 30.00 s | pl | pl | 0.983 | 0.978 | true | pl 0.983, ru 0.005 | 37.0 | pl | 0.9994 |
| `pla_5s.wav` | 5.00 s | pl | pl | 0.878 | 0.837 | true | pl 0.878, ru 0.041 | 37.4 | pl | 0.9988 |
| `plb_10s.wav` | 10.00 s | pl | pl | 0.993 | 0.991 | true | pl 0.993, ru 0.003 | 37.1 | pl | 0.9988 |
| `plb_2s.wav` | 2.00 s | pl | pl | 0.992 | 0.990 | true | pl 0.992, sk 0.002 | 36.7 | pl | 0.9988 |
| `plb_30s.wav` | 30.00 s | pl | pl | 0.994 | 0.992 | true | pl 0.994, ru 0.002 | 37.5 | pl | 0.9995 |
| `plb_5s.wav` | 5.00 s | pl | pl | 0.993 | 0.991 | true | pl 0.993, ru 0.002 | 37.0 | pl | 0.9991 |
| `noisy_ena_10s_15db.wav` | 10.00 s | en | en | 0.994 | 0.994 | true | en 0.994, zh 0.001 | 37.8 | en | 0.9929 |
| `noisy_ena_10s_25db.wav` | 10.00 s | en | en | 0.997 | 0.996 | true | en 0.997, zh 0.001 | 37.5 | en | 0.9965 |
| `noisy_ena_2s_15db.wav` | 2.00 s | en | en | 0.959 | 0.954 | true | en 0.959, la 0.005 | 38.3 | en | 0.9768 |
| `noisy_ena_2s_25db.wav` | 2.00 s | en | en | 0.971 | 0.964 | true | en 0.971, la 0.007 | 37.9 | en | 0.9894 |
| `noisy_ena_5s_15db.wav` | 5.00 s | en | en | 0.989 | 0.988 | true | en 0.989, zh 0.001 | 37.7 | en | 0.9921 |
| `noisy_ena_5s_25db.wav` | 5.00 s | en | en | 0.992 | 0.991 | true | en 0.992, la 0.001 | 37.7 | en | 0.9925 |
| `noisy_enb_10s_15db.wav` | 10.00 s | en | en | 0.994 | 0.993 | true | en 0.994, zh 0.001 | 37.8 | en | 0.9812 |
| `noisy_enb_10s_25db.wav` | 10.00 s | en | en | 0.995 | 0.994 | true | en 0.995, zh 0.001 | 37.7 | en | 0.9748 |
| `noisy_enb_2s_15db.wav` | 2.00 s | en | en | 0.987 | 0.985 | true | en 0.987, la 0.002 | 37.7 | en | 0.9676 |
| `noisy_enb_2s_25db.wav` | 2.00 s | en | en | 0.987 | 0.985 | true | en 0.987, la 0.002 | 37.5 | en | 0.9632 |
| `noisy_enb_5s_15db.wav` | 5.00 s | en | en | 0.992 | 0.990 | true | en 0.992, zh 0.001 | 37.7 | en | 0.9478 |
| `noisy_enb_5s_25db.wav` | 5.00 s | en | en | 0.993 | 0.993 | true | en 0.993, zh 0.001 | 37.7 | en | 0.9522 |
| `noisy_pla_10s_15db.wav` | 10.00 s | pl | pl | 0.942 | 0.919 | true | pl 0.942, ru 0.023 | 37.8 | pl | 0.9986 |
| `noisy_pla_10s_25db.wav` | 10.00 s | pl | pl | 0.917 | 0.881 | true | pl 0.917, ru 0.036 | 37.7 | pl | 0.9984 |
| `noisy_pla_2s_15db.wav` | 2.00 s | pl | pl | 0.331 | 0.159 | **false** | pl 0.331, tr 0.172 | 37.6 | pl | 0.9966 |
| `noisy_pla_2s_25db.wav` | 2.00 s | pl | pl | 0.762 | 0.716 | true | pl 0.762, ru 0.046 | 37.6 | pl | 0.9959 |
| `noisy_pla_5s_15db.wav` | 5.00 s | pl | pl | 0.838 | 0.766 | true | pl 0.838, ru 0.072 | 37.6 | pl | 0.9977 |
| `noisy_pla_5s_25db.wav` | 5.00 s | pl | pl | 0.889 | 0.846 | true | pl 0.889, ru 0.043 | 37.8 | pl | 0.9964 |
| `noisy_plb_10s_15db.wav` | 10.00 s | pl | pl | 0.994 | 0.992 | true | pl 0.994, ru 0.002 | 37.6 | pl | 0.9983 |
| `noisy_plb_10s_25db.wav` | 10.00 s | pl | pl | 0.990 | 0.986 | true | pl 0.990, ru 0.004 | 38.1 | pl | 0.9981 |
| `noisy_plb_2s_15db.wav` | 2.00 s | pl | pl | 0.917 | 0.908 | true | pl 0.917, tr 0.009 | 38.1 | pl | 0.9978 |
| `noisy_plb_2s_25db.wav` | 2.00 s | pl | pl | 0.969 | 0.963 | true | pl 0.969, sk 0.006 | 37.6 | pl | 0.9983 |
| `noisy_plb_5s_15db.wav` | 5.00 s | pl | pl | 0.957 | 0.946 | true | pl 0.957, ru 0.011 | 41.6 | pl | 0.9955 |
| `noisy_plb_5s_25db.wav` | 5.00 s | pl | pl | 0.981 | 0.975 | true | pl 0.981, ru 0.006 | 40.3 | pl | 0.9983 |
| `pl_short.wav` | 1.28 s | pl | pl | 0.447 | 0.233 | **false** | pl 0.447, it 0.215 | 39.7 | pl | 0.9989 |
| `en_short.wav` | 1.41 s | en | en | 0.995 | 0.994 | true | en 0.995, la 0.001 | 38.5 | en | 0.9959 |
| `pl_vshort.wav` | 1.66 s | pl | pl | 0.989 | 0.985 | true | pl 0.989, en 0.004 | 38.4 | pl | 0.9987 |
| `en_vshort.wav` | 1.52 s | en | en | 0.979 | 0.973 | true | en 0.979, la 0.007 | 38.2 | en | 0.9994 |

### 4.8 Per-clip raw values — the 111 real recordings

`sel` = the language the recording app was configured with, `ASR` = the model that produced the
transcript the label is derived from, `peak` = absolute peak sample.

| recording | dur | truth | sel | ASR | Ear | conf | margin | isReliable | Ear top-2 | Ear ms | whisper.cpp | whisper p | peak |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1790148594 | 1.28 s | en | en-UK | large-v3-turbo | ru | 0.631 | 0.524 | true | ru 0.631, uk 0.107 | 37.9 | ru | 0.7694 | 11549 |
| 1790148983 | 1.47 s | en | en-UK | large-v3-turbo | en | 0.442 | 0.178 | **false** | en 0.442, de 0.264 | 37.6 | en | 0.5628 | 7715 |
| 1790143287 | 1.58 s | en | auto | cohere-transcribe-q4 | en | 0.197 | 0.050 | **false** | en 0.197, ko 0.148 | 37.8 | ru | 0.4423 | 2260 |
| 1790084444 | 1.86 s | pl | auto | cohere-transcribe-q4 | tr | 0.278 | 0.112 | **false** | tr 0.278, de 0.166 | 38.0 | pl | 0.3282 | 8041 |
| 1790158605 | 1.89 s | en | en-UK | large-v3-turbo | tr | 0.784 | 0.748 | true | tr 0.784, ru 0.036 | 37.9 | en | 0.7871 | 307 |
| 1790082999 | 2.03 s | pl | auto | cohere-transcribe-q4 | pl | 0.661 | 0.486 | true | pl 0.661, ru 0.175 | 39.0 | pl | 0.9370 | 13087 |
| 1790084113 | 2.13 s | pl | auto | cohere-transcribe-q4 | pl | 0.768 | 0.706 | true | pl 0.768, ro 0.062 | 37.9 | pl | 0.9919 | 12896 |
| 1790084089 | 2.15 s | pl | auto | cohere-transcribe-q4 | cs | 0.408 | 0.325 | true | cs 0.408, ar 0.083 | 38.3 | pl | 0.9666 | 13590 |
| 1790165903 | 2.30 s | en | en-UK | large-v3-turbo | pl | 0.442 | 0.138 | **false** | pl 0.442, en 0.303 | 39.7 | en | 0.6922 | 5409 |
| 1790157618 | 2.36 s | en | en-UK | large-v3-turbo | tr | 0.322 | 0.120 | **false** | tr 0.322, ru 0.201 | 39.6 | en | 0.5443 | 518 |
| 1790164857 | 2.36 s | en | en-UK | large-v3-turbo | en | 0.667 | 0.624 | true | en 0.667, la 0.043 | 39.9 | en | 0.8538 | 9414 |
| 1790086087 | 2.39 s | pl | auto | cohere-transcribe-q4 | fi | 0.150 | 0.009 | **false** | fi 0.150, pl 0.141 | 39.0 | pl | 0.8365 | 3409 |
| 1790149048 | 2.49 s | en | en-UK | large-v3-turbo | en | 0.487 | 0.257 | true | en 0.487, ru 0.230 | 38.2 | en | 0.7310 | 7510 |
| 1790087036 | 2.51 s | en | auto | cohere-transcribe-q4 | en | 0.370 | 0.280 | true | en 0.370, pl 0.090 | 38.6 | en | 0.9710 | 7943 |
| 1790083660 | 2.69 s | pl | auto | cohere-transcribe-q4 | pl | 0.981 | 0.969 | true | pl 0.981, cs 0.012 | 38.5 | pl | 0.9972 | 8794 |
| 1790148072 | 2.74 s | en | en-UK | cohere-transcribe-q4 | ru | 0.239 | 0.130 | **false** | ru 0.239, en 0.109 | 38.6 | pl | 0.9937 | 8628 |
| 1790148446 | 2.78 s | en | en-UK | large-v3-turbo | en | 0.562 | 0.415 | true | en 0.562, de 0.147 | 38.8 | pl | 0.9958 | 6039 |
| 1790165182 | 2.92 s | en | en-UK | large-v3-turbo | en | 0.574 | 0.429 | true | en 0.574, fil 0.145 | 38.8 | en | 0.6623 | 10241 |
| 1790165217 | 3.00 s | en | en-UK | large-v3-turbo | en | 0.446 | 0.288 | true | en 0.446, de 0.158 | 38.0 | en | 0.7730 | 8469 |
| 1790165230 | 3.04 s | en | en-UK | large-v3-turbo | en | 0.849 | 0.830 | true | en 0.849, fil 0.018 | 37.8 | en | 0.6875 | 10349 |
| 1790084014 | 3.11 s | pl | auto | cohere-transcribe-q4 | cs | 0.746 | 0.577 | true | cs 0.746, pl 0.169 | 37.8 | pl | 0.9957 | 11961 |
| 1790087126 | 3.17 s | en | auto | cohere-transcribe-q4 | en | 0.952 | 0.942 | true | en 0.952, de 0.009 | 37.6 | en | 0.9685 | 8628 |
| 1790154460 | 3.27 s | en | en-UK | large-v3-turbo | en | 0.938 | 0.928 | true | en 0.938, ja 0.010 | 38.2 | en | 0.8709 | 5055 |
| 1790147767 | 3.56 s | pl | auto | cohere-transcribe-q4 | cs | 0.158 | 0.023 | **false** | cs 0.158, pl 0.136 | 38.7 | pl | 0.9988 | 7700 |
| 1790149159 | 3.64 s | en | en-UK | large-v3-turbo | en | 0.880 | 0.860 | true | en 0.880, de 0.020 | 38.4 | en | 0.5829 | 11587 |
| 1790149008 | 3.70 s | en | en-UK | large-v3-turbo | en | 0.786 | 0.762 | true | en 0.786, es 0.024 | 38.5 | en | 0.9085 | 8447 |
| 1790085087 | 3.74 s | en | auto | cohere-transcribe-q4 | en | 0.906 | 0.896 | true | en 0.906, cy 0.010 | 38.4 | en | 0.9505 | 6964 |
| 1790164554 | 3.85 s | en | en-UK | large-v3-turbo | en | 0.592 | 0.444 | true | en 0.592, ms 0.147 | 38.0 | en | 0.9748 | 8812 |
| 1790155310 | 4.08 s | en | en-UK | large-v3-turbo | en | 0.824 | 0.803 | true | en 0.824, la 0.021 | 39.2 | en | 0.7086 | 5889 |
| 1790082712 | 4.18 s | pl | auto | cohere-transcribe-q4 | en | 0.543 | 0.454 | true | en 0.543, de 0.089 | 39.3 | pl | 0.9756 | 5137 |
| 1790153906 | 4.19 s | en | en-UK | large-v3-turbo | en | 0.694 | 0.629 | true | en 0.694, cs 0.066 | 38.4 | en | 0.6290 | 8545 |
| 1790154740 | 4.43 s | en | en-UK | large-v3-turbo | en | 0.748 | 0.706 | true | en 0.748, la 0.042 | 38.1 | en | 0.6967 | 6335 |
| 1790086884 | 4.56 s | en | auto | cohere-transcribe-q4 | en | 0.754 | 0.723 | true | en 0.754, de 0.032 | 38.6 | en | 0.9761 | 5261 |
| 1790148020 | 4.62 s | pl | en | cohere-transcribe-q4 | pl | 0.574 | 0.510 | true | pl 0.574, it 0.064 | 38.8 | pl | 0.9965 | 9308 |
| 1790085179 | 4.68 s | en | auto | cohere-transcribe-q4 | en | 0.647 | 0.600 | true | en 0.647, es 0.047 | 39.2 | en | 0.9892 | 6834 |
| 1790085075 | 4.71 s | en | auto | cohere-transcribe-q4 | en | 0.727 | 0.654 | true | en 0.727, fi 0.073 | 39.1 | en | 0.9204 | 7327 |
| 1790084340 | 5.05 s | en | auto | cohere-transcribe-q4 | en | 0.209 | 0.118 | **false** | en 0.209, it 0.091 | 39.9 | en | 0.8718 | 11575 |
| 1790158992 | 5.14 s | en | en-UK | large-v3-turbo | en | 0.656 | 0.545 | true | en 0.656, cs 0.111 | 38.8 | en | 0.7894 | 15705 |
| 1790148459 | 5.17 s | en | en-UK | large-v3-turbo | en | 0.588 | 0.432 | true | en 0.588, nn 0.156 | 38.8 | en | 0.6881 | 4580 |
| 1790084585 | 5.24 s | pl | auto | cohere-transcribe-q4 | pl | 0.982 | 0.975 | true | pl 0.982, ru 0.007 | 38.4 | pl | 0.9983 | 9039 |
| 1790154653 | 5.25 s | en | en-UK | large-v3-turbo | en | 0.612 | 0.460 | true | en 0.612, cs 0.152 | 39.0 | en | 0.9015 | 6992 |
| 1790085578 | 5.54 s | en | auto | cohere-transcribe-q4 | en | 0.479 | 0.376 | true | en 0.479, ru 0.104 | 38.8 | en | 0.5224 | 6480 |
| 1790087211 | 5.62 s | en | auto | cohere-transcribe-q4 | en | 0.798 | 0.755 | true | en 0.798, pt 0.043 | 38.8 | en | 0.9920 | 6874 |
| 1790149457 | 5.80 s | en | en-UK | large-v3-turbo | en | 0.941 | 0.926 | true | en 0.941, nn 0.015 | 38.2 | en | 0.9133 | 10287 |
| 1790164575 | 5.81 s | en | en-UK | large-v3-turbo | en | 0.834 | 0.782 | true | en 0.834, fi 0.053 | 40.2 | en | 0.9020 | 7281 |
| 1790148481 | 5.87 s | en | en-UK | large-v3-turbo | en | 0.659 | 0.549 | true | en 0.659, sv 0.110 | 39.4 | en | 0.9299 | 8560 |
| 1790148989 | 5.99 s | en | en-UK | large-v3-turbo | en | 0.794 | 0.723 | true | en 0.794, zh 0.070 | 41.0 | pl | 0.6439 | 11069 |
| 1790148151 | 6.01 s | en | en-UK | large-v3-turbo | cs | 0.461 | 0.306 | true | cs 0.461, pl 0.154 | 40.9 | pl | 0.9983 | 9750 |
| 1790082896 | 6.11 s | pl | auto | cohere-transcribe-q4 | pl | 0.956 | 0.938 | true | pl 0.956, ru 0.018 | 42.0 | pl | 0.9983 | 8709 |
| 1790165401 | 6.26 s | en | en-UK | large-v3-turbo | de | 0.247 | 0.088 | **false** | de 0.247, nl 0.160 | 41.5 | en | 0.9615 | 5327 |
| 1790149373 | 6.40 s | en | en-UK | large-v3-turbo | en | 0.767 | 0.709 | true | en 0.767, nn 0.058 | 42.5 | en | 0.9329 | 8118 |
| 1790084755 | 6.51 s | en | auto | cohere-transcribe-q4 | en | 0.495 | 0.378 | true | en 0.495, ms 0.118 | 41.4 | en | 0.5125 | 10758 |
| 1790084532 | 6.74 s | pl | auto | cohere-transcribe-q4 | cs | 0.485 | 0.070 | **false** | cs 0.485, pl 0.415 | 41.5 | pl | 0.9985 | 10347 |
| 1790162935 | 6.90 s | en | en-UK | large-v3-turbo | en | 0.796 | 0.763 | true | en 0.796, de 0.034 | 40.7 | pl | 0.7005 | 10707 |
| 1790083117 | 6.92 s | pl | auto | cohere-transcribe-q4 | pl | 0.999 | 0.998 | true | pl 0.999, ru 0.001 | 42.4 | pl | 0.9961 | 5782 |
| 1790165389 | 6.96 s | en | en-UK | large-v3-turbo | en | 0.707 | 0.661 | true | en 0.707, pt 0.046 | 42.8 | en | 0.9663 | 10269 |
| 1790149581 | 7.18 s | en | en-UK | large-v3-turbo | en | 0.430 | 0.177 | **false** | en 0.430, pl 0.253 | 41.0 | en | 0.9859 | 10810 |
| 1790149964 | 7.18 s | en | en-UK | large-v3-turbo | en | 0.907 | 0.842 | true | en 0.907, nn 0.064 | 50.3 | en | 0.9978 | 8401 |
| 1790164925 | 7.28 s | en | en-UK | large-v3-turbo | en | 0.649 | 0.532 | true | en 0.649, fi 0.117 | 41.5 | en | 0.9556 | 10754 |
| 1790082597 | 7.84 s | pl | auto | cohere-transcribe-q4 | pl | 0.989 | 0.984 | true | pl 0.989, cs 0.005 | 40.8 | pl | 0.9986 | 6586 |
| 1790086076 | 7.86 s | pl | auto | cohere-transcribe-q4 | pl | 0.989 | 0.985 | true | pl 0.989, ru 0.003 | 41.7 | pl | 0.9982 | 6128 |
| 1790162403 | 8.09 s | en | en-UK | large-v3-turbo | en | 0.800 | 0.768 | true | en 0.800, nn 0.032 | 41.6 | en | 0.9977 | 9783 |
| 1790161726 | 8.11 s | en | en-UK | large-v3-turbo | en | 0.703 | 0.596 | true | en 0.703, id 0.108 | 41.2 | en | 0.9733 | 15736 |
| 1790165350 | 8.57 s | en | en-UK | large-v3-turbo | en | 0.829 | 0.799 | true | en 0.829, la 0.029 | 41.0 | en | 0.9474 | 9355 |
| 1790143077 | 8.70 s | en | auto | cohere-transcribe-q4 | en | 0.855 | 0.828 | true | en 0.855, la 0.027 | 41.1 | en | 0.9803 | 4074 |
| 1790162944 | 9.47 s | en | en-UK | large-v3-turbo | en | 0.942 | 0.932 | true | en 0.942, nn 0.010 | 40.7 | en | 0.9950 | 11421 |
| 1790148384 | 9.50 s | pl | en-UK | large-v3-turbo | pl | 0.987 | 0.980 | true | pl 0.987, cs 0.006 | 40.7 | pl | 0.9980 | 9827 |
| 1790149754 | 9.72 s | pl | en-UK | large-v3-turbo | pl | 0.759 | 0.677 | true | pl 0.759, ru 0.083 | 41.1 | pl | 0.9970 | 6034 |
| 1790164644 | 9.81 s | en | en-UK | large-v3-turbo | en | 0.688 | 0.592 | true | en 0.688, pl 0.097 | 41.0 | en | 0.9960 | 11529 |
| 1790162364 | 9.90 s | en | en-UK | large-v3-turbo | en | 0.473 | 0.399 | true | en 0.473, de 0.074 | 41.3 | en | 0.9830 | 6380 |
| 1790083872 | 9.96 s | pl | auto | cohere-transcribe-q4 | pl | 0.972 | 0.968 | true | pl 0.972, hu 0.004 | 41.9 | pl | 0.9977 | 9938 |
| 1790084915 | 10.01 s | en | auto | cohere-transcribe-q4 | en | 0.814 | 0.795 | true | en 0.814, la 0.019 | 44.0 | en | 0.9455 | 9914 |
| 1790084804 | 10.25 s | pl | auto | cohere-transcribe-q4 | pl | 0.973 | 0.963 | true | pl 0.973, sk 0.010 | 42.1 | pl | 0.9981 | 7088 |
| 1790148174 | 10.38 s | en | en-UK | large-v3-turbo | en | 0.671 | 0.591 | true | en 0.671, pl 0.080 | 42.3 | en | 0.9644 | 10894 |
| 1790083141 | 10.67 s | pl | auto | cohere-transcribe-q4 | pl | 0.997 | 0.995 | true | pl 0.997, cs 0.002 | 40.5 | pl | 0.9989 | 7386 |
| 1790083127 | 11.15 s | pl | auto | cohere-transcribe-q4 | pl | 0.998 | 0.998 | true | pl 0.998, ru 0.001 | 41.2 | pl | 0.9987 | 9547 |
| 1790084647 | 11.31 s | pl | auto | cohere-transcribe-q4 | pl | 0.979 | 0.973 | true | pl 0.979, ru 0.007 | 40.8 | pl | 0.9984 | 6274 |
| 1790149314 | 11.40 s | en | en-UK | large-v3-turbo | en | 0.621 | 0.569 | true | en 0.621, pl 0.051 | 41.2 | en | 0.9936 | 5063 |
| 1790148035 | 11.48 s | pl | auto | nvidia_parakeet-v3_494MB | pl | 0.326 | 0.095 | **false** | pl 0.326, nn 0.231 | 42.2 | pl | 0.9979 | 7998 |
| 1790084667 | 11.98 s | en | auto | cohere-transcribe-q4 | en | 0.837 | 0.817 | true | en 0.837, nn 0.020 | 41.0 | en | 0.9782 | 7155 |
| 1790083101 | 12.04 s | pl | auto | cohere-transcribe-q4 | pl | 0.972 | 0.962 | true | pl 0.972, ru 0.010 | 41.2 | pl | 0.9974 | 10736 |
| 1790082561 | 12.30 s | pl | auto | cohere-transcribe-q4 | pl | 0.981 | 0.978 | true | pl 0.981, de 0.003 | 41.0 | pl | 0.9987 | 6288 |
| 1790086097 | 12.44 s | pl | auto | cohere-transcribe-q4 | pl | 0.980 | 0.974 | true | pl 0.980, ru 0.007 | 41.4 | pl | 0.9981 | 4628 |
| 1790082918 | 12.46 s | pl | auto | cohere-transcribe-q4 | pl | 0.953 | 0.939 | true | pl 0.953, cs 0.014 | 40.7 | pl | 0.9987 | 8134 |
| 1790149535 | 12.49 s | en | en-UK | large-v3-turbo | en | 0.869 | 0.831 | true | en 0.869, nn 0.038 | 44.2 | en | 0.9731 | 9890 |
| 1790149349 | 13.58 s | en | en-UK | large-v3-turbo | en | 0.449 | 0.337 | true | en 0.449, nn 0.113 | 41.5 | en | 0.9925 | 11380 |
| 1790165451 | 13.62 s | en | en-UK | large-v3-turbo | en | 0.753 | 0.724 | true | en 0.753, tr 0.028 | 41.0 | en | 0.9928 | 10409 |
| 1790149230 | 13.64 s | en | en-UK | large-v3-turbo | en | 0.587 | 0.483 | true | en 0.587, la 0.104 | 41.2 | en | 0.9944 | 11772 |
| 1790082870 | 13.99 s | pl | auto | cohere-transcribe-q4 | pl | 0.939 | 0.929 | true | pl 0.939, hr 0.010 | 41.4 | pl | 0.9985 | 8319 |
| 1790149076 | 14.02 s | en | en-UK | large-v3-turbo | en | 0.300 | 0.126 | **false** | en 0.300, bg 0.174 | 41.3 | en | 0.9846 | 14882 |
| 1790148308 | 14.16 s | pl | en-UK | large-v3-turbo | pl | 0.979 | 0.970 | true | pl 0.979, cs 0.009 | 41.2 | pl | 0.9978 | 9907 |
| 1790082579 | 14.54 s | pl | auto | cohere-transcribe-q4 | pl | 0.994 | 0.993 | true | pl 0.994, ru 0.001 | 42.1 | pl | 0.9988 | 8738 |
| 1790082607 | 15.02 s | pl | auto | cohere-transcribe-q4 | pl | 0.989 | 0.986 | true | pl 0.989, cs 0.003 | 41.9 | pl | 0.9988 | 7464 |
| 1790164744 | 16.20 s | en | en-UK | large-v3-turbo | en | 0.754 | 0.723 | true | en 0.754, la 0.031 | 41.8 | en | 0.9916 | 6932 |
| 1790083556 | 16.58 s | pl | auto | cohere-transcribe-q4 | pl | 0.985 | 0.977 | true | pl 0.985, cs 0.008 | 42.0 | pl | 0.9977 | 10860 |
| 1790162512 | 17.08 s | en | en-UK | large-v3-turbo | en | 0.889 | 0.868 | true | en 0.889, la 0.021 | 40.5 | en | 0.9973 | 5535 |
| 1790165328 | 17.09 s | en | en-UK | large-v3-turbo | en | 0.761 | 0.728 | true | en 0.761, la 0.033 | 41.0 | en | 0.9937 | 8601 |
| 1790142969 | 18.56 s | en | auto | cohere-transcribe-q4 | en | 0.859 | 0.814 | true | en 0.859, la 0.046 | 41.1 | en | 0.9957 | 6656 |
| 1790086612 | 19.82 s | en | auto | cohere-transcribe-q4 | en | 0.667 | 0.590 | true | en 0.667, pl 0.077 | 39.8 | en | 0.9464 | 6703 |
| 1790086035 | 20.09 s | pl | auto | cohere-transcribe-q4 | pl | 0.999 | 0.998 | true | pl 0.999, cs 0.000 | 39.7 | pl | 0.9988 | 6010 |
| 1790149632 | 20.80 s | en | en-UK | large-v3-turbo | en | 0.724 | 0.667 | true | en 0.724, nn 0.057 | 38.8 | en | 0.9993 | 11497 |
| 1790154364 | 21.28 s | en | en-UK | large-v3-turbo | en | 0.857 | 0.807 | true | en 0.857, la 0.051 | 40.0 | en | 0.9896 | 6646 |
| 1790084992 | 21.91 s | en | auto | cohere-transcribe-q4 | en | 0.774 | 0.728 | true | en 0.774, la 0.046 | 39.9 | en | 0.9947 | 6886 |
| 1790085268 | 23.73 s | en | auto | cohere-transcribe-q4 | en | 0.626 | 0.552 | true | en 0.626, pl 0.074 | 38.9 | en | 0.9152 | 9133 |
| 1790086113 | 25.05 s | pl | auto | cohere-transcribe-q4 | pl | 0.974 | 0.965 | true | pl 0.974, ru 0.008 | 38.8 | pl | 0.9986 | 6059 |
| 1790166095 | 25.39 s | en | en-UK | large-v3-turbo | en | 0.733 | 0.693 | true | en 0.733, pl 0.041 | 38.6 | en | 0.9978 | 8136 |
| 1790083067 | 27.04 s | pl | auto | cohere-transcribe-q4 | pl | 0.998 | 0.997 | true | pl 0.998, ru 0.001 | 38.8 | pl | 0.9985 | 8862 |
| 1790148494 | 29.68 s | en | en-UK | large-v3-turbo | en | 0.847 | 0.797 | true | en 0.847, fi 0.050 | 38.8 | en | 0.9938 | 11658 |
| 1790149771 | 34.51 s | en | en-UK | large-v3-turbo | en | 0.907 | 0.888 | true | en 0.907, ja 0.019 | 38.5 | en | 0.9990 | 11066 |
| 1790082625 | 44.03 s | pl | auto | cohere-transcribe-q4 | pl | 0.992 | 0.988 | true | pl 0.992, ru 0.003 | 78.1 | pl | 0.9991 | 11964 |
| 1790148681 | 156.41 s | en | en-UK | large-v3-turbo | en | 0.651 | 0.582 | true | en 0.651, pl 0.069 | 123.4 | en | 0.9972 | 11643 |

---

## 5. The free alternative the app already contains — whisper.cpp

**It was practical, and it wins where it matters.** I built `whisper-cli` out-of-tree (the fork ships
sources but no CLI binary — `libwhisper/build` contains only Debug static libs from the app's Xcode
build):

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
cmake -S /Volumes/home/zenon/Projects/OpenSuperWhisper-fork/repo/libwhisper/whisper.cpp -B /tmp/whisper-build \
  -DCMAKE_BUILD_TYPE=Release -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF -DGGML_METAL=ON
cmake --build /tmp/whisper-build --config Release -j 8      # ggml 0.20.2, whisper-cli + libwhisper

# per clip:
/tmp/whisper-build/bin/whisper-cli -m "$HOME/Library/Application Support/superwhisper/ggml-large-v3-turbo.bin" \
  -f <clip.wav> -l auto -dl
  -> whisper_full_with_state: auto-detected language: pl (p = 0.998538)
```

All 155 clips were processed (6-way parallel, 4 min 10 s, **0 errors**). Results:

| band | n | Ear acc | whisper acc |
|---|---|---|---|
| <2 s | 5 | 40.0% | 60.0% |
| 2-5 s | 31 | 74.2% | **93.5%** |
| 5-10 s | 35 | 91.4% | 91.4% |
| 10-30 s | 37 | 100% | 100% |
| ≥30 s | 3 | 100% | 100% |
| **all** | **111** | **87.4%** | **93.7%** |
| 2-10 s band | 66 | 83.3% | **92.4%** |

On the 44 synthetic clips both were perfect (44/44 each). whisper.cpp's seven real-clip misses were all labelled English by
me: five came back Polish (p 0.64-0.998, three of them ≥0.99) and two Russian (p 0.44 and 0.77) — the
same accented-English cluster described in §4.6. So on this corpus the two detectors fail on the *same*
kind of input, and whisper simply fails less often.

**What it costs.** Language detection in whisper.cpp is *not* free but needs nothing new:
`whisper_lang_auto_detect_with_state` calls `whisper_encode_with_state` itself
(`libwhisper/whisper.cpp:4064`), and the transcription loop encodes again, so it is **one extra encoder
pass**. Measured on a 10 s clip with large-v3-turbo + Metal:

```
-l pl   (no detection):  encode time = 1546 ms / 1 run   total 3694 ms
-l auto (detection):     encode time = 3019 ms / 2 runs  total 4336 ms
```

The doubling is structural — *two* encoder runs against one — so it holds regardless of load; the
absolute milliseconds were taken while another agent may have been using the machine, and are the
softest numbers in this report. Accuracy (§5) is unaffected by contention.

**The integration point already exists.** `WhisperEngine.makeFullParams` (WhisperEngine.swift:337-352)
does:

```swift
let isAutoDetect = settings.selectedLanguage == "auto"
params.language = isAutoDetect ? nil : settings.selectedLanguage
params.detectLanguage = false
```

and whisper.cpp treats `language == nullptr` as "auto" (`whisper.cpp:6849`). The C struct is built by
`WhisperFullParams.toC()` as `var cParams = whisper_full_params()` — Swift's zero-initialisation, **not**
`whisper_full_default_params()` (whose `language` default is `"en"`) — so a nil `language` really does
leave `cParams.language == NULL`. Therefore **whenever the user has "auto" selected the app already runs
a detection on every recording and already discards it**; the result only reaches the log.
Surfacing that existing value costs nothing at all; forcing detection while a language *is* pinned is
what costs the extra encoder pass above.

**Transcript-text heuristic, one line:** classifying the finished transcript's script (Polish
diacritics/function words) is free and needs no model, but it only runs *after* transcription, so it
cannot choose which recogniser or transform to use — the sibling scout `fm-20260923-04` owns whether
that is good enough.

---

## 6. Footprint and integration cost

| | measured |
|---|---|
| Weights on disk | 13,895,166 B (13.25 MiB / 13.90 MB), 8 files in one directory |
| Resident memory while loaded | **36.2 MiB** RSS (`ps -o rss` = 37120 KB, probe process incl. Swift runtime + Foundation); no separate ANE working-set figure was measured |
| Cold load (first ever at a new weights path) | **1.44 s** — Core ML specialises `ear.mlmodelc` for the Neural Engine |
| Warm load (new process, same path) | 59-74 ms |
| In-process second call | ~10-60 µs (already loaded) |
| Warm identification | 36.7-41.6 ms per single-window clip |
| ANE compile cache | `~/Library/Caches/desertant/com.apple.e5rt.e5bundlecache`, 22 MB |

**What the app would have to add:** a SwiftPM/Xcode dependency on `desert-ant-core` (product `Ear`);
either the managed-cache download path (needs network on first run) or ~13.9 MB of weights bundled in
the app's resources plus `Ear(directory:)`; an attribution line (below); and a decision about the
telemetry (below).

### 6.1 Licence obligations

`https://license.desertant.com/1.0` (Desert Ant Labs Source-Available License v1.0, 3 July 2026 —
source-available, **not** open source, SPDX `LicenseRef-DAL-Source-Available-1.0`, perpetual):

- **Free below 100,000 monthly active devices (MAD) per platform, per model**; macOS counts as its own
  platform (§3), so a local fork is many orders of magnitude below the threshold. Above it, a
  commercial licence is required.
- **Attribution (§9)** is mandatory: a short "Powered by Desert Ant Labs" line, linked to
  https://desertant.com where the medium allows, in one reasonably discoverable place (an about,
  settings, credits or licences screen). *I did not verify where this fork's licences/about surface is.*
- **§6/§7/§19(f): do not tamper with the telemetry or interfere with its reporting.**
- §6 also bars using the models or their outputs to train a competing model, and bars redistributing the
  models as a standalone product (embedding in the app is expressly allowed).
- §9 additionally requires keeping the licence and copyright notices *inside the model files as
  delivered* — a file-level requirement, so the `.dal-meta/manifest` (and any licence file shipped with
  the weights) must travel with the bundled copy.
- §7 makes Desert Ant Labs the **controller** of the telemetry (not the app's processor) and puts a duty
  on the developer to disclose the telemetry in the app's privacy notice where the law requires it.

### 6.2 Telemetry — verified live, not merely read from the licence

The licence says the SDK sends MAD-counting telemetry; I verified that `identify` in normal use really
does, and captured the wire body. Path: `Ear.identify` → `session.run` → the session built by
`Inference/SessionFactory.swift:26` is wrapped by `tracked(...)` (`Inference/UsageTracking.swift:13`) →
`TrackedSession` records **one call per `run`** (one per window) and flushes on a 3 s debounce →
`UsageClient` → POST to `Sources/Usage/Transport.swift:12`
`defaultIngestEndpoint = "https://events.desertant.com/api/v1/ingest"`.

Two independent observations: a redirected capture endpoint received a POST after `identify`, and with
`DAL_HTTP_DEBUG=1` and no override the real endpoint was used —

```
[usage] POST https://events.desertant.com/api/v1/ingest
[usage] body: {"app":{"id":"earprobe"},"events":[{"callCount":2,"deviceId":"probe-fresh-31744",
              "name":"load"}],"platform":"server","sdk":{"name":"Ear","version":"3.3.1"},
              "sentAt":"2026-09-23T12:23:25.930Z"}
[usage] response: 202 {"accepted":1}
```

So: **normal `identify` sends an outbound request**, no API key is needed, and the production server
accepts it. What is on the wire is an app id (on macOS the bundle identifier), a per-install device id,
a call count, the platform tag, the SDK name/version and a timestamp — **no audio, no transcript, no
detected language, no user content**, which matches §7. On macOS the platform tag is `"server"` and the
SDK coalesces re-emits hourly (`emitIntervalMs = hourMs` when `platform == "server"`), so a long-running
app posts at most about once an hour per device.

**Against the plan's §10 criterion "Fully offline with local backends; no external requests": Ear
cannot satisfy it** while its telemetry is intact, and the licence requires that it stay intact. The SDK
*does* ship a kill switch — `DAL_USAGE_DISABLED` (`Sources/Usage/AppIdentity.swift:54`) and a
`DAL_INGEST_ENDPOINT` override — but using the former is exactly what §6/§19(f) forbid. Bundling the
weights removes the *download*, not the *usage event*.

---

## 7. Verdict

**Usable only for long recordings. Not usable for our dictation as a routing input, on this evidence.**

- **≥10 s: yes.** 37/37 at 10-30 s and 3/3 at ≥30 s on real recordings, zero confidently-wrong, 1.4 s worst
  cold load and ~40 ms per identification. This is a good detector for files and long dictations.
- **2-10 s: no.** 83.3% accuracy in the band that dictation produces, with **6.1% confidently wrong** —
  and the confidently-wrong cases are exactly the ones a gate acts on. Below 2 s it is 40%, and one of
  the failures is a near-silent clip misread as Turkish at 0.784 confidence.
- **The free alternative is better here.** whisper.cpp's detection, already present in the app
  (large-v3-turbo), scored 93.7% vs 87.4% overall and 93.5% vs 74.2% at 2-5 s, at the cost of one extra
  encoder pass (~1.5 s) and no new dependency, no weights, no licence, no telemetry. When the user has
  "auto" selected, the app is already computing that detection today and throwing it away.
- **What Ear would cost if pursued anyway:** the attribution surface and the §6/§9 file-level notice
  requirements; an outbound POST to `events.desertant.com` that cannot be disabled without breaching the
  licence — a direct conflict with the plan's "no external requests"; 13.9 MB bundled (or a network
  fetch on first run); a new SwiftPM dependency that resolves to 3.3.1 even when pinned `from: "3.1.0"`;
  and a first-load ANE compile of ~1.4 s.

---

## 8. What I did **not** verify

1. **I never listened to the real recordings.** Ground truth is the app's own stored transcript plus a
   script/function-word classifier, cross-checked with `languageSelected` and whisper. 5 of 111 clips
   are ambiguous (§4.6) and shift Ear's overall real-clip accuracy by ~3 points; both labelings keep
   whisper ahead.
2. **Accented English.** The most plausible cause of those 5 is Polish-accented English; unresolved
   without listening, and it would matter a lot to the gate.
3. **No OpenSuperWhisper recordings exist on this machine**, so Ear was never measured on *this app's*
   microphone path. The real clips come from a different app on the same machine.
4. **The app's own audio preparation was not reproduced.** I fed 16 kHz mono WAVs directly; the app
   resamples and applies a VAD before models. Ear's behaviour on the app's pre-VAD buffers is only
   partially covered (the near-silent failures suggest it is weak there).
5. **macOS only.** No iOS/ANE-constrained measurement; no measurement of the ANE working set as distinct
   from process RSS.
6. **The vendor's side of MAD counting** was not verified beyond the HTTP 202 from the ingest endpoint;
   the 6.2 s download time is one wifi measurement, not a controlled bandwidth figure.
7. **The fork's licences/about screen** was not checked for suitability as the attribution placement, and
   I did not build the app or verify `desert-ant-core` compiles inside its Xcode project at the fork's
   deployment target (the SDK's floor is macOS 14).
8. **The 99-language claim** was verified only as far as `languages.json` listing 99 codes including
   `pl` and `en`; per-language accuracy outside `pl`/`en` was not measured.
9. Licence notes above are a reading of the published text, **not legal advice**.
10. The whisper.cpp detection timings were taken on a machine that may have had concurrent work from
    another agent; only their ratio (2 encoder runs vs 1) is load-independent.

---

## 9. One accidental side effect on the repo — found, fixed, disclosed

Building `whisper-cli` standalone in `/tmp` had one write-back into the fork's whisper.cpp submodule:
whisper.cpp's `CMakeLists.txt:47` calls

```cmake
if (CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)   # standalone build only
    configure_file(${CMAKE_SOURCE_DIR}/bindings/javascript/package-tmpl.json
                   ${CMAKE_SOURCE_DIR}/bindings/javascript/package.json @ONLY)
endif()
```

so a *standalone* configure rewrites a **tracked** file inside the source tree
(`bindings/javascript/package.json`, `"1.9.3"` → `"1.9.3-dev"`). The app's own in-repo build is not
standalone (whisper.cpp is a subdirectory of `libwhisper`), so it does not do this — the change was
mine. I restored it with `git -C libwhisper/whisper.cpp checkout -- bindings/javascript/package.json`
and verified `git status --porcelain` is empty for both the submodule and the superproject, on branch
`feat/local-translate-tone` at `bd5ad0e`. **The repo is left exactly as found: no branch, no commit, no
modification.** Anyone else building whisper.cpp standalone from that submodule will hit the same
write-back; the sibling worktree `OpenSuperWhisper-fm-fm-20260923-05` showed the same file touched at
14:31, which is not mine to fix.
