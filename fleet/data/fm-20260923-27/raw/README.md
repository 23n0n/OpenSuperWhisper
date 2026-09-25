# fm-20260923-27 raw evidence

Everything here was produced by this task's probe and by `server-experiment.sh`; nothing in the repository
writes to this directory.

The probe itself (`OpenSuperWhisperTests/FM27ProbeTests.swift`) was a **scratch instrument and was deleted
with the task** — it is not part of the commit, and only the one committed test remains. Its records are
self-describing: every JSON line carries the tag, direction, model, run number, sha256, wall time, byte
count, the full output text and the knobs that were in force.

## In-process probe records (`*.jsonl`)

One JSON object per request: `tag`, `direction`, `model`, `run`, `sha256` (of the output text),
`seconds`, `bytes`, `text`, plus the knobs in force (`nThreads`, `metalDevices`; the two earliest runs
predate that field).

| tag file | configuration | runs | distinct hashes |
|---|---|---|---|
| `plen-launch1.jsonl`, `plen-launch2.jsonl` | 1.5B, PL→EN, shipped settings, two separate test-process launches | 6 + 6 | 1 + 1 (`894391652c73cced…`) |
| `enpl-launch1.jsonl`, `enpl-launch2.jsonl` | 8B, EN→PL, shipped settings, two separate launches | 6 + 6 | 1 + 1 (`7c9fc36c…`) |
| `enpl15b.jsonl` | 1.5B, EN→PL — fm-20260923-13's exact configuration | 10 | 1 (`789ceda6…`) |
| `plen-metal.jsonl` | 1.5B, PL→EN, shipped settings, with the device report | 6 | 1 (`894391652c73cced…`) |
| `plen-nthreads1.jsonl` | 1.5B, PL→EN, `n_threads = n_threads_batch = 1` | 6 | 1 (same as shipped) |
| `plen-nometal.jsonl` | 1.5B, PL→EN, `GGML_METAL_DEVICES=0` (no MTL0 registered) | 6 | 1 (`b43b1494…`), 62–66 s per run |
| `plen-nogpu.jsonl`, `plen-cpuonly.jsonl` | **invalid**: the temporary hook set `n_gpu_layers = 0` after the model had already been loaded, so these are shipped-configuration runs. Kept as the evidence of that instrument bug — see the report's "Instrument failure modes". | 6 + 6 | 1 (same as shipped) |

`*.devices.txt` — `ggml_backend_dev_count/name/memory` at three points of each placement-instrumented run
(before load, while resident, after unload). `plen-nometal.devices.txt` lists only `BLAS` and `CPU`,
which is what makes that row a real GPU-disabled run.

## Endpoint experiment (`server-experiment.sh`, `attrib/`)

`server-experiment.sh <tag> <nopseed|bodyseed|cliseed>` starts brew `llama-server 0.3.0 build 10621` on
`:1924` with the app's model and flags and POSTs the app's exact request body N times to
`/v1/chat/completions`.

- `attrib/http-*` — the short input (6 requests per mode): 1 distinct output in all three modes.
- `attrib/long-*` — the long input (10 requests per mode):
  `long-nopseed` = **8 distinct**, `long-bodyseed` = 2 distinct, `long-cliseed` = 2 distinct.
- `attrib/*.body.json` — the exact body sent; `attrib/*.server.log` — the server's own log (the startup
  line shows the flags, i.e. the absence of `--seed`).
