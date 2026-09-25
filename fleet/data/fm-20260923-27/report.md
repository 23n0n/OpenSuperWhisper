# fm-20260923-27 — in-process transform determinism

Branch `fm/fm-20260923-27` @ **`80d114c`** (one file, the determinism test, +95 lines) · worktree
`worktrees/OpenSuperWhisper-fm-fm-20260923-27` · based on the delivery tip `c6f9546`, which was still the tip
at the end (`git -C repo log --oneline -1` = `c6f9546`, primary checkout clean) — **no rebase needed**.
Apple M4, 10 cores, 32 GB, macOS 27.0 (26A428); the only crew running.

Requirement: **same input, same settings, same model ⇒ same output, in-process, across processes.**

## Outcome

**The in-process path is deterministic on this tip, and the drift `fm-20260923-13` reported is
reproducible — on the optional HTTP endpoint path, not in process.**

- In process: **64 requests across ten test-process launches**, in both directions and in every
  configuration tried (shipped Metal, single-threaded, Metal backend removed), returned **exactly one output
  hash per configuration**. The new test adds 30 more requests in three further launches, each launch
  producing the same hash as the others.
- On the endpoint: with the app's exact request body (no `seed`) and `transform-server.sh`'s exact server
  arguments (no `--seed`), **8 of 10 identical requests produced different text**. Pinning the seed — in the
  body or on the server — makes 9 of 10 byte-identical (the outlier is the first request of a fresh server,
  which is deterministic across launches too).
- Decision: **no sampling change.** Nothing was needed, nothing was weakened, no latency was paid. The
  deliverable is the guard test the tree was missing: `OpenSuperWhisperTests/TransformDeterminismIntegrationTests.swift`.

## 1. In-process reproduction — what the app actually runs

Probe (scratch, not committed): `TransformRuntime.transform` → `LlamaModel.complete` with the shipping
sampler chain (`top_k 40 → top_p 0.95 → min_p 0.05 → temp 0.2 → dist(seed 0)`,
`OpenSuperWhisper/Llama/Llama.swift:270-278`), real weights hard-linked into a staging directory, one
resident model reused for every run in a process. `sha256` of the output text. Raw records:
`raw/*.jsonl`, one JSON object per run with the full text.

| direction | backend | process launches | runs | distinct hashes | latency (first / steady) |
|---|---|---|---|---|---|
| PL → EN | `qwen2.5-1.5b-instruct-q4_k_m` | 2 (+1 repeat with the placement instrument) | 12 (+6) | **1** — `894391652c73cced…` | 2.72 s / 0.91–0.93 s |
| EN → PL | `qwen3-8b-q4_k_m` (5.03 GB) | 2 | 12 | **1** — `7c9fc36c3de3873861c08320e4d8a00f99b20ce8de6587f2542480f5b0d3d87d` | 11.68 s / 5.35–5.48 s |
| EN → PL | **1.5B — fm-13's exact configuration** | 1 | 10 | **1** — `789ceda6e6ca5643…` | 1.52 s / 0.37–0.38 s |
| PL → EN | 1.5B, `n_threads = n_threads_batch = 1` | 1 | 6 | **1** — same as shipped | 2.74 s / 0.91–0.95 s |
| PL → EN | 1.5B, Metal backend removed (`GGML_METAL_DEVICES=0`) | 1 | 6 | **1** — `b43b1494886db4a2…` | 62.0–65.6 s every run |

PL → EN text, identical in all 18 runs of the shipped configuration:

> Good day. I am calling about order number 423 from last week. I'm concerned about the delivery time, as
> it's a birthday present for my sister-in-law, and I need to be at work for an hour. Could you check when
> the package will arrive?

EN → PL on the 8B, identical in all 12 runs (raw completion; the app strips the think block in
`TranslationService.stripReasoning`, a pure regex):

> `<think>` `</think>` Dzień dobry. Zadzwoń, by się dowiedzieć o zamowie numer 423, które złożyłem w
> ostatnim tygodniu. Jest to dla mnie bardzo ważne, ponieważ jest to prezent urodzinowy dla mojej nepotki,
> a muszę być na pracy za godzinę. Czy możesz sprawdzić, kiedy przekażą paczkę?

**fm-13's configuration deserves its own sentence.** The small model on English → Polish is *stable and
bad*: all 10 runs returned the same 48 bytes, `Dzień dobry. Słucham, ale nie mogę ci pomóc.` ("Good morning.
I'm listening, but I can't help you."), which is not a translation of the input at all. That is exactly the
quality defect `fm-13`/`-19`/`-24` describe — and it is **reproducible**, not varying. (That output is ~7
tokens, so this particular row is a weak drift detector; §2b is the sensitivity evidence, and the 8B row
above is ~90 tokens of stability.)

## 2. Attribution

### 2a. The two named discriminators, plus the instrument that made them meaningful

| configuration | how it was set | distinct | steady latency | same text as shipped | GPU memory held by the weights |
|---|---|---|---|---|---|
| shipped | — | 1 of 6 | 0.91–1.20 s | — | **−1 412 179 456 B** (MTL0 free 26 800 128 000 → 25 388 007 424 while resident, back to 26 799 865 856 after unload) |
| single-threaded | `contextParams.n_threads = n_threads_batch = 1` | 1 of 6 | 0.91–0.95 s | yes | same −1.412 GB |
| "CPU-only" via `n_gpu_layers = 0` | **invalid — the hook set it after the load** | 1 of 6 | 0.90–0.93 s | yes | same −1.412 GB (**still on Metal**) |
| Metal path absent | `GGML_METAL_DEVICES=0` — the registry reports no `MTL0` at all, only `BLAS` and `CPU` | 1 of 6 | **62.0–65.6 s** | **no** | 0 |

Neither discriminator explains drift, because the shipped in-process configuration does not drift. What
this table establishes instead:

1. **The shipped configuration really does run on the GPU.** The Metal device loses 1.412 GB of free
   memory while the 1.5B is resident and gets all of it back on unload — so "Metal accumulation is
   deterministic here" is a statement about Metal, not about a silent CPU fallback. Timing alone could not
   have said this: the row that *claimed* to be CPU-only ran at the same speed as the GPU one.
2. **Determinism is per configuration, not across configurations.** With the Metal path removed the same
   input still gave one hash in 6 runs, but a *different* text, and 60–70× slower. The entire difference is
   one token:

   > Metal: … Good day. **I am** calling about order number 423 …
   > CPU:   … Good day. **I'm** calling about order number 423 …

   So the reduction order is part of the identity of a build: on one machine and build the output is
   stable, and pinning the slower configuration would have changed the text the product produces (and paid
   62–66 s per dictation here — a Debug build of `ggml-cpu`, which the wrapper also builds with
   `GGML_MATMUL_INT8=0` and `-U__ARM_FEATURE_MATMUL_INT8`; [INFERENCE] the shipped Release gap is smaller,
   but far from free).

### 2b. The one unpinned path in the app — and the experiment that isolates the historical drift

Code path, at file:line:

- `OpenSuperWhisper/TranslationService.swift:462-486` (`buildRequestBody`; `ChatRequest` at `:660-679`)
  sends `model`, `messages`, `temperature: 0.2`, `stream`, `chat_template_kwargs` — **no `seed`**.
- `Scripts/transform-server.sh:130-140` starts `llama-server` with `--model --alias --host --port
  --ctx-size --n-gpu-layers 99` — **no `--seed`**.
- `libllama/llama.cpp/src/llama-sampler.cpp:339-353` — `get_rng_seed(LLAMA_DEFAULT_SEED)` returns
  `std::random_device()`; `llama_sampler_init_dist` seeds `std::mt19937` from it (`:1399-1409`).
  `common/arg.cpp:1992` — that sentinel is the CLI default ("use random seed for −1").

Experiment (`raw/server-experiment.sh`, brew `llama-server 0.3.0 build 10621 @ c1d0e7a00` on `:1924`,
`qwen2.5-1.5b-instruct-q4_k_m`, `--ctx-size 4096 --n-gpu-layers 99`, the app's exact request shape, my long
Polish input, 10 identical requests per row; texts in `raw/attrib/`):

| seed | distinct outputs | hashes (first 16) |
|---|---|---|
| none — what the app sends and what the script starts | **8 of 10** | `c479de05…`, `12924566…`, `caab1c90…`, `e28e053c…`, `8181b14f…`, `6344441a…`, `b70bc3a2…`, `a7741ee8…` ×3 |
| `"seed": 0` in the request body | 2 of 10 | `7553a530…` (run 1), then `a7741ee8…` ×9 |
| server started with `--seed 0` | 2 of 10 | `7553a530…` (run 1), then `a7741ee8…` ×9 |

The differing part, runs 1 and 2 of the unpinned row:

> 1: **Good day.** I'm calling about order number 423 from last week. I'm concerned about **the delivery
>    time since** it's a birthday present for my sister-in-law **and** I need to be at work for an hour.
>    Could you check **when the package will arrive?**
> 2: **Hello.** I'm calling about order number 423 from last week. I'm concerned about the delivery time
>    **because** it's a birthday present for my sister-in-law**,** and I need to be at work for an hour.
>    Could you check **the delivery time?**

Reading it honestly:

- **The drift needs a long generation.** On a one-sentence input (6 output tokens) all three rows were
  byte-identical 6/6 — that experiment would have "proved" the unpinned seed harmless. This is also why the
  in-process probes use long inputs, and why the short fm-13-configuration row is not evidence on its own.
- With the seed pinned, runs 2…10 agree byte for byte; **run 1 of a freshly started server differs**, the
  same way in both pinned modes (`7553a530…`), so it is not randomness — it is the first request having no
  prompt cache to reuse. The app's steady state is runs 2…10, i.e. deterministic.
- This is the only mechanism in the app that can produce "8 of 10 identical requests differ", and it
  reproduces that number. `fm-20260923-24`'s byte-identical ×3 is the same code with `--seed 0` passed.

## 3. Decision

1. **No change to the in-process sampling or backend configuration.** It is already deterministic with the
   sampler the product chose; there is nothing to pin, no latency to trade, and the two configurations that
   *are* deterministic alternatives (single-thread, Metal removed) buy nothing: one is identical to what
   ships, the other is 60–70× slower **and** changes the output text.
2. **The endpoint path is untouched.** It is outside this task's scope (the requirement says *in-process*;
   the endpoint is off by default, `AppPreferences.swift:296`), its body shape is asserted by
   `Scripts/verify-transform.sh` (162 checks), and the standing instruction is to change nothing the brief
   does not ask for. If the captain wants that path pinned too, the change is one field or one flag:
   `"seed": 0` in `buildRequestBody`, or `--seed 0` in `transform-server.sh` — §2b is the measured effect of
   both. **This is the one decision left to the captain**, with both numbers on the table.
3. **The guard landed.** The tree now fails if the in-process contract breaks.

## 4. The determinism test

`OpenSuperWhisperTests/TransformDeterminismIntegrationTests.swift` (new, 95 lines): per direction one fixed
input run **5 times on one loaded model**, asserting every output is byte-identical to the first, plus a
non-empty check; both cases print their sha256 through `TestFixtures.report`; skipped when the weights are
absent, like its neighbours (`LlamaRuntimeIntegrationTests`, `PolishOutputBackendIntegrationTests`).

Passing, on the reverted tree:

```
TEST_RUNNER_OSW_TEST_EVIDENCE=/tmp/fm27/determinism-evidence-3.txt \
  Scripts/dev-run.sh test \
  -only-testing:OpenSuperWhisperTests/TransformDeterminismIntegrationTests
→ ** TEST SUCCEEDED **, both cases passed (21.188 s and 2.775 s)
[determinism] english→polish on Qwen3-8B-Q4_K_M.gguf: 5 runs in 14.05s, 1 distinct output(s),
              sha256 5ba778d653984b30cc026094b605ecfe2406e4875f09d2d84e29faa6c13912f5 (134 bytes)
[determinism] polish→english on qwen2.5-1.5b-instruct-q4_k_m.gguf: 5 runs in 2.05s, 1 distinct output(s),
              sha256 11968128660b0baa5c9e8ba46bca2e8d5c8615151c52d1abedd7cb966533d319 (85 bytes)
```

Those two hashes were **identical in three separate launches of the test** (13:38, 13:42, 13:48 — the
`det-2`, stray and `det-3` runs in `/tmp/fm27/`), which is the committed test proving the *across
processes* half of the contract, not just within one process.

Non-vacuity — there is no fix to revert, so the check runs the other way, with the sampler deliberately
**unpinned** (`LlamaModel.seed = LLAMA_DEFAULT_SEED`, `0xFFFF_FFFF`), everything else untouched:

```
sed -i '' 's/static let seed: UInt32 = 0$/static let seed: UInt32 = 0xFFFF_FFFF/' OpenSuperWhisper/Llama/Llama.swift
TEST_RUNNER_OSW_TEST_EVIDENCE=/tmp/fm27/unpinned-evidence.txt \
  Scripts/dev-run.sh test \
  -only-testing:OpenSuperWhisperTests/TransformDeterminismIntegrationTests/testPolishToEnglishIsIdenticalOnEveryRepeat
→ ** TEST FAILED ** (exit 65): Test case '…testPolishToEnglishIsIdenticalOnEveryRepeat()' failed (3.938 s)
[determinism] polish→english on qwen2.5-1.5b-instruct-q4_k_m.gguf: 5 runs in 2.11s,
              3 distinct output(s), sha256 606e571e89517a41678af83ce6916664c28dde577c1438659abb73a784696874 (88 bytes)
```

The seed was then restored and the file reverted (`git checkout -- OpenSuperWhisper/Llama/Llama.swift`), the
probe deleted, and the class re-run green — the run quoted above. **The test can fail, and fails on exactly
the thing it claims to guard.**

## 5. Suite and bundle

Clean state (`rm -rf build libllama/build libwhisper/build`), whole unit bundle headless:

```
Scripts/dev-run.sh test > /tmp/fm27-suite.log 2>&1     # exit 0, 2m42s wall
```

**389 passed / 0 failed / 54 skipped** (counted from the `Test case … passed|failed|skipped on` lines;
`grep -c "passed on 'My Mac" /tmp/fm27-suite.log` = 389, `failed` = 0, `skipped` = 54), including both
determinism cases — `…testEnglishToPolishIsIdenticalOnEveryRepeat()` and
`…testPolishToEnglishIsIdenticalOnEveryRepeat()`, both `passed` on the same process. `** TEST SUCCEEDED **`.
The class ran in the parallel-test phase, so one of its two result lines was interleaved byte-for-byte with
an xcodebuild log line in the captured file; the counts above are taken from the completed lines and the
zero failure count.

Bundle afterwards: **identity-signed, single binary** — `codesign -d -r-` reads
`designated => identifier "ru.starmel.OpenSuperWhisper.dev" and certificate leaf = H"32266bcc51546f68f9347324bd3c81d853fde5a4"`
(never a bare `cdhash`); worktree bundle id `ru.starmel.OpenSuperWhisper.dev`, unchanged by this task.

## 6. What I did not do / could not reproduce

- **`fm-13`'s provenance is not in the fleet.** `fleet/data/fm-20260923-13/` holds only a brief and a status
  log; the raw 10 outputs and the instrument that produced them are gone. The claim that reached the
  captain ("in-process, 8/10 differed") cannot be traced further than `fm-20260923-19`'s quotation of it.
  What *is* established here is the negative (in-process is stable, 64/64) and the positive (the endpoint
  path yields exactly that 8/10).
- I did not measure the `llama-server` path's first-request-vs-rest difference beyond the table in §2b, and
  I did not chase it to a line of code; it is reproducible and deterministic, so it is not drift.
- The 62–66 s CPU-only figure is from this Debug test build; a Release measurement was out of scope because
  no configuration that slow could ship.
- Endpoint-body pinning was **not** landed (out of scope, §3.2) — it is a one-field change with the measured
  effect documented.
- The fleet's 10-minute idle-unload and the `noTimestamps = false` rationale were not touched.

## 7. Raw evidence

`fleet/data/fm-20260923-27/raw/`:

| file | what it is |
|---|---|
| `plen-launch1/2.jsonl`, `enpl-launch1/2.jsonl` | the 4 launch probe: 6 runs each, PL→EN 1.5B and EN→PL 8B |
| `enpl15b.jsonl` | fm-13's configuration (1.5B, EN→PL), 10 runs |
| `plen-nthreads1.jsonl`, `plen-nometal.jsonl` | single-thread, Metal-absent |
| `plen-metal.jsonl`, `plen-nogpu.jsonl`, `plen-cpuonly.jsonl` | placement-instrumented runs; **`plen-cpuonly`/`plen-nogpu` are the invalid `n_gpu_layers = 0` runs (see instrument failure modes), `plen-metal` is the valid one** |
| `*.devices.txt` | ggml device report before / resident / after unload for those runs |
| `server-experiment.sh`, `attrib/` | the endpoint experiment: 6 bodies + 60 response texts + 3 server logs |
| `determinism-evidence-2.txt`, `determinism-evidence-3.txt` | the committed test's own evidence lines from two launches of the same tree (hashes identical across launches) |
| `unpinned-evidence.txt` | the same test with `LlamaModel.seed = LLAMA_DEFAULT_SEED`: `3 distinct output(s)` in 5 runs, and the case fails |
| every `.jsonl` | one JSON object per request: `run`, `sha256`, `seconds`, `bytes`, `text`, and the knobs in force |

## Instrument failure modes (read before trusting any table above)

1. **My first "CPU-only" knob was a no-op, and only a second instrument caught it.** The temporary hook set
   `modelParams.n_gpu_layers = 0` *after* `llama_model_load_from_file` had already loaded the model with 99
   layers, so that row was really the shipped configuration — same hash, same text, and it still held
   1.412 GB of GPU memory. Timing could not tell (0.90 s vs 0.91 s, equally consistent with "CPU is
   bandwidth-bound here"); the device report did. The authoritative GPU-disabled row is the library-level
   `GGML_METAL_DEVICES=0`.
2. **`Scripts/dev-run.sh test` does not carry the test process's stdout into the log.**
   `grep -c fm27 /tmp/fm27/plen-launch1.log` = 0 while `Test case … passed on 'My Mac -
   OpenSuperWhisper (86636)'` is present, and no llama.cpp runtime line appears anywhere in a 3.3 MB log.
   All hashes therefore come from the probe's own file channel, and the committed test reports through
   `TestFixtures.report`, which needs `OSW_TEST_EVIDENCE` (forwarded as `TEST_RUNNER_OSW_TEST_EVIDENCE`) to
   land in a file.
3. **A green hash table is not sensitivity.** The instrument compares sampled text, so its resolution is a
   sampling boundary, not the last bit of a logit — §2b's 6-token row and §4's deliberately unpinned run are
   what show it can see a difference at all.
4. **Two bugs in my own experiment script** (macOS bash 3.2 `set -u` with an empty array; a comma-decimal
   locale breaking `printf`) produced one run that aborted before starting the server and one whose timings
   printed as `0,00s`. Fixed and re-run; §2b is from the fixed script.
5. **One infrastructure failure, not a test result:** the first run of the new test reported
   `** TEST FAILED **` with no case lines — `Failed to create a bundle instance representing
   …/OpenSuperWhisperTests.xctest. Check that the bundle exists on disk.` Two `dev-run.sh test` invocations
   overlapped on the same derived data (a parked job of my own was still holding `sleep` after I tried to
   cancel it). Re-run alone: green. The log of the raced run was interleaved in
   `/tmp/fm27/determinism-green.log`, so the quoted results come from `determinism-2.log` and
   `determinism-3.log`.
